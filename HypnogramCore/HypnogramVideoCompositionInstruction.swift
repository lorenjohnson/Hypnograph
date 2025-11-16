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
final class HypnogramVideoCompositor: NSObject, AVVideoCompositing {

    private let renderContextQueue = DispatchQueue(label: "HypnogramVideoCompositor.renderContextQueue")
    private let renderingQueue = DispatchQueue(label: "HypnogramVideoCompositor.renderingQueue")
    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext = CIContext(options: nil)

    // We work with 32BGRA buffers.
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

    var supportsWideColorSourceFrames: Bool {
        return false
    }

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

            let trackIDs = instruction.layerTrackIDs
            let modes = instruction.blendModes

            // Base layer: first track.
            guard
                let firstTrackID = trackIDs.first,
                let firstBuffer = request.sourceFrame(byTrackID: firstTrackID)
            else {
                // No frames? Output a blank buffer.
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

            var outputImage = CIImage(cvPixelBuffer: firstBuffer)

            // Blend each additional track onto the base.
            for (index, trackID) in trackIDs.dropFirst().enumerated() {
                guard let buffer = request.sourceFrame(byTrackID: trackID) else {
                    continue
                }

                let topImage = CIImage(cvPixelBuffer: buffer)
                // Each layer has a blend mode name in the same order.
                let modeName: String
                if index + 1 < modes.count {
                    modeName = modes[index + 1]
                } else {
                    modeName = modes.last ?? "normal"
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
            // Just drain the queue.
        }
    }

    private func composite(bottom: CIImage, top: CIImage, modeName: String) -> CIImage {
        let name = modeName.lowercased()
        let filterName: String

        switch name {
        case "multiply":
            filterName = "CIMultiplyCompositing"
        case "overlay":
            filterName = "CIOverlayBlendMode"
        case "screen":
            filterName = "CIScreenBlendMode"
        case "softlight", "soft_light", "soft-light":
            filterName = "CISoftLightBlendMode"
        case "darken":
            filterName = "CIDarkenBlendMode"
        case "lighten":
            filterName = "CILightenBlendMode"
        default:
            filterName = "CISourceOverCompositing"
        }

        guard let filter = CIFilter(name: filterName) else {
            return top.composited(over: bottom)
        }

        filter.setValue(top, forKey: kCIInputImageKey)
        filter.setValue(bottom, forKey: kCIInputBackgroundImageKey)

        return filter.outputImage ?? top.composited(over: bottom)
    }
}
