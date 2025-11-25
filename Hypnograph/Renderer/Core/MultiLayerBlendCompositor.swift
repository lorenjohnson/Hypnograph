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
final class MultiLayerBlendCompositor: NSObject, AVVideoCompositing {

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

    var sourcePixelBufferAttributes: [String : Any]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
    }

    var supportsWideColorSourceFrames: Bool { false }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextQueue.sync {
            renderContext = newRenderContext
        }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
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
            let sourceIndices = instruction.sourceIndices
            let transforms    = instruction.sourceTransforms
            let stillImages   = instruction.stillImages

            // Gather CIImages for all available source frames in order.
            var images: [CIImage] = []

            for (index, trackID) in trackIDs.enumerated() {
                // Prefer a time-invariant still image if provided
                let maybeStill = index < stillImages.count ? stillImages[index] : nil

                var image: CIImage?

                if let still = maybeStill {
                    image = still
                } else if let buffer = request.sourceFrame(byTrackID: trackID) {
                    image = CIImage(cvPixelBuffer: buffer)
                }

                guard var img = image else {
                    let error = NSError(
                        domain: "MultiLayerBlendCompositor",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey:
                            "No image for layer \(index) at time \(request.compositionTime.seconds)"]
                    )
                    print("❌ MultiLayerBlendCompositor: \(error.localizedDescription)")
                    request.finish(with: error)
                    return
                }

                // Apply the original track orientation based on preferredTransform.
                if index < transforms.count {
                    let transform = transforms[index]
                    if let exifOrientation = exifOrientation(from: transform) {
                        img = img.oriented(forExifOrientation: exifOrientation)
                    } else {
                        img = img.transformed(by: transform)
                    }
                }

                // Apply per-source effects BEFORE compositing.
                // Use the ORIGINAL source index, not the track position.
                if let manager = GlobalRenderHooks.manager {
                    let originalSourceIndex = index < sourceIndices.count ? sourceIndices[index] : index
                    var sourceContext = RenderContext(
                        frameIndex: 0,
                        time: request.compositionTime,
                        isPreview: true,
                        outputSize: targetSize,
                        frameBuffer: manager.frameBuffer,
                        params: RenderParams()
                    )
                    img = manager.applyToSource(
                        sourceIndex: originalSourceIndex,
                        context: &sourceContext,
                        image: img
                    )
                }

                images.append(img)
            }

            guard !images.isEmpty else {
                let error = NSError(
                    domain: "MultiLayerBlendCompositor",
                    code: -5,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No input images produced at time \(request.compositionTime.seconds)"]
                )
                print("❌ MultiLayerBlendCompositor: \(error.localizedDescription)")
                request.finish(with: error)
                return
            }

            // Destination pixel buffer from render context.
            guard let dstBuffer = renderContext.newPixelBuffer() else {
                let error = NSError(
                    domain: "MultiLayerBlendCompositor",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to allocate destination buffer"]
                )
                print("❌ MultiLayerBlendCompositor: \(error.localizedDescription)")
                request.finish(with: error)
                return
            }

            // Use shared CI compositor (aspect-fill + blend filters).
            let composedImage = self.compositor.composite(
                images: images,
                blendModes: modes,
                targetSize: targetSize
            )

            // Extra guard: if the output extent is empty, fail the frame.
            guard !composedImage.extent.isEmpty else {
                let error = NSError(
                    domain: "MultiLayerBlendCompositor",
                    code: -6,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Composed image has empty extent at time \(request.compositionTime.seconds)"]
                )
                print("❌ MultiLayerBlendCompositor: \(error.localizedDescription)")
                request.finish(with: error)
                return
            }

            // --- Render hooks: build context, apply hooks, then post-process image.

            let imageToRender: CIImage
            if let manager = GlobalRenderHooks.manager {
                var context = RenderContext(
                    frameIndex: 0, // TODO: thread a real frame index if you want later
                    time: request.compositionTime,
                    isPreview: true,              // this compositing path is used for preview here
                    outputSize: targetSize,
                    frameBuffer: manager.frameBuffer,
                    params: RenderParams()         // baseline params (unused for now)
                )

                let effectResult = manager.applyGlobal(to: &context, image: composedImage)

                if effectResult.extent.isEmpty {
                    imageToRender = composedImage
                } else {
                    imageToRender = effectResult
                }
            } else {
                imageToRender = composedImage
            }

            // Render CIImage → pixel buffer via CIContext (backed by Metal if available).
            self.ciContext.render(
                imageToRender,
                to: dstBuffer,
                bounds: dstRect,
                colorSpace: nil
            )

            request.finish(withComposedVideoFrame: dstBuffer)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
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

/// Map a CGAffineTransform (as used for track preferredTransform) to an EXIF orientation.
private func exifOrientation(from transform: CGAffineTransform) -> Int32? {
    // Normalize minor floating point drift
    let a = round(transform.a * 1000) / 1000
    let b = round(transform.b * 1000) / 1000
    let c = round(transform.c * 1000) / 1000
    let d = round(transform.d * 1000) / 1000

    if a == 0, b == 1, c == -1, d == 0 {
        // 90° CCW
        return 6 // right
    } else if a == 0, b == -1, c == 1, d == 0 {
        // 90° CW
        return 8 // left
    } else if a == -1, b == 0, c == 0, d == -1 {
        // 180°
        return 3 // down
    } else if a == 1, b == 0, c == 0, d == 1 {
        // 0°
        return 1 // up
    }

    return nil
}
