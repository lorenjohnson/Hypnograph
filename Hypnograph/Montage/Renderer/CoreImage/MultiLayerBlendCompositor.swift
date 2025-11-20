//
//  MultiLayerBlendCompositor.swift
//  Hypnograph
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import Metal

/// Custom compositor that blends multiple video tracks using CoreImage.
/// Each source frame is orientation-corrected, aspect-fill scaled into
/// the render size, then blended using the requested CoreImage blend filters.
public final class MultiLayerBlendCompositor: NSObject, AVVideoCompositing {

    private let renderContextQueue = DispatchQueue(label: "MultiLayerBlendCompositor.renderContextQueue")
    private let renderingQueue     = DispatchQueue(label: "MultiLayerBlendCompositor.renderingQueue")
    private var renderContext: AVVideoCompositionRenderContext?

    /// Core Image context, explicitly backed by Metal if available.
    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        } else {
            return CIContext(options: nil)
        }
    }()

    /// Shared compositing helper (aspect-fill + blend filters).
    private let compositor = AspectFillStackCompositor()
    
    public var sourcePixelBufferAttributes: [String : Any]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
    }

    public var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
    }

    public var supportsWideColorSourceFrames: Bool { false }

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextQueue.sync {
            renderContext = newRenderContext
        }
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderingQueue.async {
            guard
                let instruction = request.videoCompositionInstruction as? MultiLayerBlendInstruction
            else {
                let error = NSError(
                    domain: "MultiLayerBlendCompositor",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected instruction type"]
                )
                request.finish(with: error)
                return
            }

            guard let renderContext = self.renderContext else {
                let error = NSError(
                    domain: "MultiLayerBlendCompositor",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "No render context"]
                )
                request.finish(with: error)
                return
            }

            let targetSize    = renderContext.size
            let dstRect       = CGRect(origin: .zero, size: targetSize)
            let trackIDs      = instruction.layerTrackIDs
            let modes         = instruction.blendModes
            let transforms    = instruction.layerTransforms
            let sourceIndices = instruction.sourceIndices

            // Gather CIImages for all available source frames in order.
            var images: [CIImage] = []

            for (index, trackID) in trackIDs.enumerated() {
                guard let buffer = request.sourceFrame(byTrackID: trackID) else {
                    continue
                }

                var image = CIImage(cvPixelBuffer: buffer)

                // Apply the original track’s preferredTransform if we have one.
                if index < transforms.count {
                    image = image.transformed(by: transforms[index])
                }

                // Apply per-source effects BEFORE compositing
                // Use the ORIGINAL source index, not the track position
                if let manager = GlobalRenderHooks.manager {
                    let originalSourceIndex = index < sourceIndices.count ? sourceIndices[index] : index
                    var sourceContext = RenderContext(
                        frameIndex: 0,
                        time: request.compositionTime,
                        isPreview: true,
                        outputSize: targetSize,
                        frameBuffer: manager.frameBuffer, // Use manager's persistent buffer
                        params: RenderParams()
                    )
                    image = manager.applyToSource(sourceIndex: originalSourceIndex, context: &sourceContext, image: image)
                }

                images.append(image)
            }

            // Destination pixel buffer from render context.
            guard let dstBuffer = renderContext.newPixelBuffer() else {
                let error = NSError(
                    domain: "MultiLayerBlendCompositor",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to allocate destination buffer"]
                )
                request.finish(with: error)
                return
            }

            // If nothing came through, clear to black and finish.
            guard !images.isEmpty else {
                self.ciContext.clear(dstBuffer)
                request.finish(withComposedVideoFrame: dstBuffer)
                return
            }

            // Use shared CI compositor (aspect-fill + blend filters).
            let composedImage = self.compositor.composite(
                images: images,
                blendModes: modes,
                targetSize: targetSize
            )

            // Extra guard: if the output extent is empty, bail to black.
            guard !composedImage.extent.isEmpty else {
                self.ciContext.clear(dstBuffer)
                request.finish(withComposedVideoFrame: dstBuffer)
                return
            }

            // --- Render hooks: build context, apply hooks, then post-process image.

            let imageToRender: CIImage
            if let manager = GlobalRenderHooks.manager {
                // Safety check: ensure composed image is valid before applying effects
                guard !composedImage.extent.isEmpty else {
                    print("MultiLayerBlendCompositor: composedImage has empty extent at time \(request.compositionTime)")
                    request.finish(with: NSError(domain: "Compositor", code: -1, userInfo: nil))
                    return
                }

                var context = RenderContext(
                    frameIndex: 0, // TODO: thread a real frame index if you want later
                    time: request.compositionTime,
                    isPreview: true,              // this compositing path is used for preview here
                    outputSize: targetSize,
                    frameBuffer: manager.frameBuffer, // Use manager's persistent buffer
                    params: RenderParams()         // baseline params (unused for now)
                )

                let effectResult = manager.applyGlobal(to: &context, image: composedImage)

                // Safety check: ensure effect didn't produce empty image
                if effectResult.extent.isEmpty {
                    print("MultiLayerBlendCompositor: Effect produced empty image at time \(request.compositionTime)")
                    imageToRender = composedImage // Fall back to original
                } else {
                    imageToRender = effectResult
                }
            } else {
                imageToRender = composedImage
            }

            // 🔁 Global vertical flip to correct upside-down output.
            let flipTransform = CGAffineTransform(translationX: 0, y: targetSize.height)
                .scaledBy(x: 1, y: -1)

            let uprightImage = imageToRender.transformed(by: flipTransform)

            // Render CIImage → pixel buffer via CIContext (backed by Metal if available).
            self.ciContext.render(
                uprightImage,
                to: dstBuffer,
                bounds: dstRect,
                colorSpace: nil
            )

            request.finish(withComposedVideoFrame: dstBuffer)
        }
    }

    public func cancelAllPendingVideoCompositionRequests() {
        renderingQueue.sync {
            // just drain
        }
    }
}

private extension CIContext {
    /// Convenience: clear a pixel buffer to transparent black.
    func clear(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let height      = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            memset(base, 0, height * bytesPerRow)
        }
    }
}
