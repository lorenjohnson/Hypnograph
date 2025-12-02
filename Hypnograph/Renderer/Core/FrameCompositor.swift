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

            // Apply combined transform (metadata orientation + user transform)
            let transform = instruction.transforms[index]
            img = img.transformed(by: transform)

            // Aspect-fill to output size (handles origin normalization internally)
            img = ImageUtils.aspectFill(image: img, to: outputSize)

            // Apply per-source effects if enabled
            if instruction.enableEffects, let manager = GlobalRenderHooks.manager {
                let sourceIndex = instruction.sourceIndices[index]
                var sourceContext = RenderContext(
                    frameIndex: 0,
                    time: request.compositionTime,
                    isPreview: true,
                    outputSize: outputSize,
                    frameBuffer: manager.frameBuffer
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
                let opacity: CGFloat

                if instruction.enableEffects,
                   let manager = GlobalRenderHooks.manager {
                    let sourceIndex = instruction.sourceIndices[index]
                    blendMode = manager.blendMode(for: sourceIndex)
                    // Get compensated opacity from normalization strategy
                    opacity = manager.compensatedOpacity(
                        layerIndex: index,
                        totalLayers: instruction.layerTrackIDs.count,
                        blendMode: blendMode
                    )
                } else {
                    blendMode = instruction.blendModes[index]
                    opacity = 1.0  // No compensation during export (baked in)
                }

                img = ImageUtils.blend(layer: img, over: base, mode: blendMode, opacity: opacity)
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

        // Apply blend normalization (after compositing, before global effects)
        if instruction.enableEffects, let manager = GlobalRenderHooks.manager {
            finalImage = manager.applyNormalization(to: finalImage)
        }

        // Apply global effects if enabled
        if instruction.enableEffects, let manager = GlobalRenderHooks.manager {
            var context = RenderContext(
                frameIndex: 0,
                time: request.compositionTime,
                isPreview: true,
                outputSize: outputSize,
                frameBuffer: manager.frameBuffer
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
}

