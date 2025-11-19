//
//  MontageVideoInstruction.swift
//  Hypnograph
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import AVFoundation
import CoreImage
import CoreMedia
import CoreGraphics
import Metal

/// Instruction describing how to composite a single segment:
/// - which track IDs to use as layers
/// - which blend modes (one per layer, same order)
/// - per-layer transforms (usually the original track's preferredTransform)
public final class MontageVideoInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    public var timeRange: CMTimeRange
    public var enablePostProcessing: Bool = false
    public var containsTweening: Bool = false

    public var requiredSourceTrackIDs: [NSValue]?
    public var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let layerTrackIDs: [CMPersistentTrackID]
    let blendModes: [String]
    let layerTransforms: [CGAffineTransform]

    public init(
        layerTrackIDs: [CMPersistentTrackID],
        blendModes: [String],
        transforms: [CGAffineTransform],
        timeRange: CMTimeRange
    ) {
        self.timeRange       = timeRange
        self.layerTrackIDs   = layerTrackIDs
        self.blendModes      = blendModes
        self.layerTransforms = transforms
        self.requiredSourceTrackIDs = layerTrackIDs.map { NSNumber(value: $0) }
    }
}

/// Custom compositor that blends multiple video tracks using CoreImage.
/// Each source frame is orientation-corrected, aspect-fill scaled into
/// the render size, then blended using the requested CoreImage blend filters.
public final class LayeredVideoComposition: NSObject, AVVideoCompositing {

    private let renderContextQueue = DispatchQueue(label: "LayeredVideoComposition.renderContextQueue")
    private let renderingQueue     = DispatchQueue(label: "LayeredVideoComposition.renderingQueue")
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
    private lazy var compositor = HypnographCICompositor(ciContext: ciContext)
    
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
                let instruction = request.videoCompositionInstruction as? MontageVideoInstruction
            else {
                let error = NSError(
                    domain: "LayeredVideoComposition",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected instruction type"]
                )
                request.finish(with: error)
                return
            }

            guard let renderContext = self.renderContext else {
                let error = NSError(
                    domain: "LayeredVideoComposition",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "No render context"]
                )
                request.finish(with: error)
                return
            }

            let targetSize = renderContext.size
            let dstRect    = CGRect(origin: .zero, size: targetSize)
            let trackIDs   = instruction.layerTrackIDs
            let modes      = instruction.blendModes
            let transforms = instruction.layerTransforms

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

                images.append(image)
            }

            // Destination pixel buffer from render context.
            guard let dstBuffer = renderContext.newPixelBuffer() else {
                let error = NSError(
                    domain: "LayeredVideoComposition",
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

            // 🔁 Global vertical flip to correct upside-down output.
            //
            // HypnographCICompositor normalizes to (0,0,width,height),
            // so we can flip by:
            //   1. translate up by height
            //   2. scale y by -1
            let flipTransform = CGAffineTransform(translationX: 0, y: targetSize.height)
                .scaledBy(x: 1, y: -1)

            let uprightImage = composedImage.transformed(by: flipTransform)

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
