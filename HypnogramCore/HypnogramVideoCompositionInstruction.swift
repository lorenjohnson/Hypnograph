//
//  HypnogramVideoCompositionInstruction.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//


import Foundation
import AVFoundation
import CoreImage
import CoreMedia

/// Instruction describing how to composite a single segment:
/// - which track IDs to use as layers
/// - which blend modes (one per layer, same order)
final class HypnogramVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = false
    var containsTweening: Bool = false

    /// AVVideoCompositing wants this even when we do full custom compositing.
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let layerTrackIDs: [CMPersistentTrackID]
    let blendModes: [String]

    init(timeRange: CMTimeRange,
         layerTrackIDs: [CMPersistentTrackID],
         blendModes: [String]) {
        self.timeRange = timeRange
        self.layerTrackIDs = layerTrackIDs
        self.blendModes = blendModes

        // Bridge CMPersistentTrackID to NSValue/NSNumber as required.
        self.requiredSourceTrackIDs = layerTrackIDs.map { NSNumber(value: $0) }
    }
}

/// Custom compositor that blends multiple video tracks using CoreImage.
/// Each source frame is aspect-fit into the render size (like AVPlayerView.resizeAspect),
/// then blended using the requested CoreImage blend filters.
final class HypnogramVideoCompositor: NSObject, AVVideoCompositing {

    private let renderContextQueue = DispatchQueue(label: "HypnogramVideoCompositor.renderContextQueue")
    private let renderingQueue = DispatchQueue(label: "HypnogramVideoCompositor.renderingQueue")
    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext = CIContext(options: nil)

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
                let instruction = request.videoCompositionInstruction as? HypnogramVideoCompositionInstruction
            else {
                let error = NSError(
                    domain: "HypnogramVideoCompositor",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected instruction type"]
                )
                request.finish(with: error)
                return
            }

            guard let renderContext = self.renderContext else {
                let error = NSError(
                    domain: "HypnogramVideoCompositor",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "No render context"]
                )
                request.finish(with: error)
                return
            }

            let targetSize = renderContext.size
            let trackIDs = instruction.layerTrackIDs
            let modes = instruction.blendModes

            // Base layer
            guard
                let firstTrackID = trackIDs.first,
                let firstBuffer = request.sourceFrame(byTrackID: firstTrackID)
            else {
                guard let blank = renderContext.newPixelBuffer() else {
                    let error = NSError(
                        domain: "HypnogramVideoCompositor",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output buffer"]
                    )
                    request.finish(with: error)
                    return
                }
                request.finish(withComposedVideoFrame: blank)
                return
            }

            // Scale base image to FILL the target size, cropping center.
            let baseImage = CIImage(cvPixelBuffer: firstBuffer)
            var outputImage = self.resizedToFill(baseImage, targetSize: targetSize)

            // Blend each additional track onto the base.
            for (index, trackID) in trackIDs.dropFirst().enumerated() {
                guard let buffer = request.sourceFrame(byTrackID: trackID) else {
                    continue
                }

                let rawTopImage = CIImage(cvPixelBuffer: buffer)
                let topImage = self.resizedToFill(rawTopImage, targetSize: targetSize)

                let modeName: String
                if index + 1 < modes.count {
                    modeName = modes[index + 1]
                } else {
                    modeName = modes.last ?? "CISourceOverCompositing"
                }

                outputImage = self.composite(bottom: outputImage, top: topImage, modeName: modeName)
            }

            guard let dstBuffer = renderContext.newPixelBuffer() else {
                let error = NSError(
                    domain: "HypnogramVideoCompositor",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to allocate destination buffer"]
                )
                request.finish(with: error)
                return
            }

            self.ciContext.render(outputImage, to: dstBuffer)
            request.finish(withComposedVideoFrame: dstBuffer)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        renderingQueue.sync {
            // just drain
        }
    }

    private func composite(bottom: CIImage, top: CIImage, modeName: String) -> CIImage {
        guard let filter = CIFilter(name: modeName) else {
            print("HypnogramVideoCompositor: unknown blend filter '\(modeName)', falling back to source-over")
            return top.composited(over: bottom)
        }

        filter.setValue(top, forKey: kCIInputImageKey)
        filter.setValue(bottom, forKey: kCIInputBackgroundImageKey)

        return filter.outputImage ?? top.composited(over: bottom)
    }

    /// Scale `image` to completely fill `targetSize`, then crop center.
    private func resizedToFill(_ image: CIImage, targetSize: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return image
        }

        let scale = max(
            targetSize.width  / extent.width,
            targetSize.height / extent.height
        )

        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let x = (scaled.extent.width  - targetSize.width)  / 2.0
        let y = (scaled.extent.height - targetSize.height) / 2.0
        let cropRect = CGRect(x: x, y: y, width: targetSize.width, height: targetSize.height)

        return scaled.cropped(to: cropRect)
    }
}

private extension CIContext {
    /// Convenience: clear a pixel buffer to transparent black.
    func clear(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            memset(base, 0, height * bytesPerRow)
        }
    }
}
