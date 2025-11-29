//
//  FrameCompositor.swift
//  Hypnograph
//
//  Stateless frame compositor - receives instructions, outputs frames
//  Minimal skeleton: single layer, no blending, no effects
//

import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import Metal

final class FrameCompositor: NSObject, AVVideoCompositing {

    // MARK: - Properties

    private let renderContext: CIContext = {
        // Use Metal for GPU-accelerated rendering
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
        }
        return CIContext()
    }()
    private let renderQueue = DispatchQueue(label: "com.hypnograph.framecompositor", qos: .userInteractive)

    // MARK: - Initialization

    override init() {
        super.init()
        // Compositor initialized - logging removed for performance
    }

    // MARK: - AVVideoCompositing Protocol

    var sourcePixelBufferAttributes: [String : Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferOpenGLCompatibilityKey as String: true
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferOpenGLCompatibilityKey as String: true
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Nothing to do - we're stateless
    }

    // MARK: - Frame Rendering

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // Per-frame logging removed for performance (30fps = 30 logs/sec)
        // NOTE: We capture self strongly here because AVFoundation owns the compositor
        // and can deallocate it at any time. If AVFoundation deallocates us while
        // we have pending work, that's an AVFoundation bug we can't fix with weak self.
        // Using weak self just causes the "self is nil" errors without fixing the root cause.
        renderQueue.async {
            self.renderFrame(request: request)
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        // Nothing to cancel - we process synchronously
    }
    
    // MARK: - Core Rendering
    
    private func renderFrame(request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? RenderInstruction else {
            print("🔴 FrameCompositor: Invalid instruction type")
            request.finish(with: NSError(domain: "FrameCompositor", code: 2, userInfo: nil))
            return
        }

        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            print("🔴 FrameCompositor: Failed to create output buffer")
            request.finish(with: NSError(domain: "FrameCompositor", code: 3, userInfo: nil))
            return
        }

        let outputSize = CGSize(
            width: CVPixelBufferGetWidth(outputBuffer),
            height: CVPixelBufferGetHeight(outputBuffer)
        )

        // Composite all layers
        var composited: CIImage?

        for (index, trackID) in instruction.layerTrackIDs.enumerated() {
            // Check flash solo - skip layers that shouldn't be rendered
            if instruction.enableEffects,
               let manager = GlobalRenderHooks.manager,
               !manager.shouldRenderSource(at: instruction.sourceIndices[index]) {
                continue
            }

            var layerImage: CIImage?

            // Check if this layer is a still image
            if index < instruction.stillImages.count, let stillImage = instruction.stillImages[index] {
                layerImage = stillImage
            } else {
                // Get frame from video track
                guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
                    print("⚠️ FrameCompositor: No source frame for track \(trackID) at \(request.compositionTime.seconds)s")
                    continue
                }
                layerImage = CIImage(cvPixelBuffer: sourceBuffer)
            }

            guard var img = layerImage else {
                // No image for layer - skip silently
                continue
            }

            // Apply transform (orientation correction from media metadata)
            let transform = instruction.transforms[index]
            img = img.transformed(by: transform)

            // Apply user rotation around the image center
            let rotationDegrees = instruction.rotations[index]
            if rotationDegrees != 0 {
                let radians = CGFloat(rotationDegrees) * .pi / 180.0
                let extent = img.extent
                guard extent.width > 0, extent.height > 0,
                      extent.origin.x.isFinite, extent.origin.y.isFinite else {
                    print("⚠️ Skipping rotation for layer \(index): invalid extent \(extent)")
                    continue
                }
                // Rotate around the center of the extent
                let centerX = extent.midX
                let centerY = extent.midY
                let rotateAroundCenter = CGAffineTransform(translationX: -centerX, y: -centerY)
                    .rotated(by: radians)
                    .translatedBy(x: centerX, y: centerY)
                img = img.transformed(by: rotateAroundCenter)

                // After rotation, the extent may have moved - translate back to origin
                // This ensures aspectFill will work correctly
                let rotatedExtent = img.extent
                if rotatedExtent.origin != .zero {
                    img = img.transformed(by: CGAffineTransform(
                        translationX: -rotatedExtent.origin.x,
                        y: -rotatedExtent.origin.y
                    ))
                }
            }

            // Aspect-fill to output size
            img = aspectFill(image: img, to: outputSize)

            // Apply per-source effects if enabled
            if instruction.enableEffects, let manager = GlobalRenderHooks.manager {
                let sourceIndex = instruction.sourceIndices[index]
                var sourceContext = RenderContext(
                    frameIndex: 0,
                    time: request.compositionTime,
                    isPreview: true,
                    outputSize: outputSize,
                    frameBuffer: manager.frameBuffer,
                    params: RenderParams()
                )
                img = manager.applyToSource(
                    sourceIndex: sourceIndex,
                    context: &sourceContext,
                    image: img
                )
            }

            // Blend with previous layers
            if let base = composited {
                // Get blend mode from manager if available (for dynamic changes),
                // otherwise fall back to instruction (for export)
                let blendMode: String
                if instruction.enableEffects,
                   let manager = GlobalRenderHooks.manager {
                    let sourceIndex = instruction.sourceIndices[index]
                    blendMode = manager.blendMode(for: sourceIndex)
                } else {
                    blendMode = instruction.blendModes[index]
                }

                img = blend(layer: img, over: base, mode: blendMode)
                composited = img
            } else {
                composited = img
            }
        }

        guard var finalImage = composited else {
            print("🔴 FrameCompositor: No layers composited")
            request.finish(with: NSError(domain: "FrameCompositor", code: 5, userInfo: nil))
            return
        }

        // Apply global effects if enabled
        if instruction.enableEffects, let manager = GlobalRenderHooks.manager {
            var context = RenderContext(
                frameIndex: 0,
                time: request.compositionTime,
                isPreview: true,
                outputSize: outputSize,
                frameBuffer: manager.frameBuffer,
                params: RenderParams()
            )

            let effectResult = manager.applyGlobal(to: &context, image: finalImage)
            if !effectResult.extent.isEmpty {
                finalImage = effectResult
            }
        }

        // Store the final composited frame in the frame buffer for snapshots
        if instruction.enableEffects, let manager = GlobalRenderHooks.manager {
            manager.frameBuffer.addFrame(finalImage, at: request.compositionTime)
        }

        // Render to output buffer
        renderContext.render(finalImage, to: outputBuffer)

        // Finish request
        request.finish(withComposedVideoFrame: outputBuffer)
    }
    
    // MARK: - Helpers

    private func aspectFill(image: CIImage, to size: CGSize) -> CIImage {
        let imageSize = image.extent.size
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)

        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledSize = scaledImage.extent.size

        let x = (size.width - scaledSize.width) / 2
        let y = (size.height - scaledSize.height) / 2

        let translated = scaledImage.transformed(by: CGAffineTransform(translationX: x, y: y))

        return translated.cropped(to: CGRect(origin: .zero, size: size))
    }

    private func blend(layer: CIImage, over base: CIImage, mode: String) -> CIImage {
        // Use Core Image blend filters
        let filter = CIFilter(name: mode)
        filter?.setValue(layer, forKey: kCIInputImageKey)
        filter?.setValue(base, forKey: kCIInputBackgroundImageKey)

        return filter?.outputImage ?? layer
    }
}

