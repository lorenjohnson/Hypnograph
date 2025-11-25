//
//  MultiLayerBlendInstruction.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics
import CoreImage

/// Instruction describing how to composite a single segment:
/// - which track IDs to use as sources
/// - which blend modes (one per layer, same order)
/// - per-layer transforms (usually the original track's preferredTransform)
/// - original source indices (for applying per-source effects correctly)
/// - optional time-invariant still images for layers without video
final class MultiLayerBlendInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = false
    var containsTweening: Bool = false

    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    /// One entry per layer:
    /// - video layers: valid track ID, stillImage == nil
    /// - still layers: stillImage != nil, trackID may be ignored
    let layerTrackIDs: [CMPersistentTrackID]
    let blendModes: [String]
    var sourceTransforms: [CGAffineTransform]
    let sourceIndices: [Int] // Maps track position → original layer index
    let stillImages: [CIImage?]

    init(
        layerTrackIDs: [CMPersistentTrackID],
        blendModes: [String],
        transforms: [CGAffineTransform],
        sourceIndices: [Int],
        timeRange: CMTimeRange,
        stillImages: [CIImage?]? = nil
    ) {
        self.timeRange        = timeRange
        self.layerTrackIDs    = layerTrackIDs
        self.blendModes       = blendModes
        self.sourceTransforms = transforms
        self.sourceIndices    = sourceIndices

        // If no stillImages provided, default to "all video"
        if let provided = stillImages, provided.count == layerTrackIDs.count {
            self.stillImages = provided
        } else {
            self.stillImages = Array(repeating: nil, count: layerTrackIDs.count)
        }

        self.requiredSourceTrackIDs = layerTrackIDs.map { NSNumber(value: $0) }
    }

    // MARK: - Convenience factory to wire still images

    /// Builds an instruction from the usual render data plus the full list of sources.
    ///
    /// For each layer:
    /// - If the underlying VideoFile mediaKind == .image, we load (or fetch cached) CIImage from disk.
    /// - Otherwise, the layer is treated as a regular video layer (stillImages entry is nil).
    ///
    /// `sourceIndices` is used to map track position -> original source index.
    static func make(
        layerTrackIDs: [CMPersistentTrackID],
        blendModes: [String],
        transforms: [CGAffineTransform],
        sourceIndices: [Int],
        timeRange: CMTimeRange,
        sources: [HypnogramSource]
    ) -> MultiLayerBlendInstruction {
        var stillImages: [CIImage?] = []

        for (layerPosition, _) in layerTrackIDs.enumerated() {
            // Map track position → source index in `sources` array
            guard layerPosition < sourceIndices.count else {
                stillImages.append(nil)
                continue
            }

            let sourceIndex = sourceIndices[layerPosition]
            guard sourceIndex >= 0, sourceIndex < sources.count else {
                stillImages.append(nil)
                continue
            }

            let source = sources[sourceIndex]
            let file = source.clip.file

            if file.mediaKind == .image {
                let url = file.url
                let ci = StillImageCache.ciImage(for: url)
                stillImages.append(ci)
            } else {
                stillImages.append(nil)
            }
        }

        return MultiLayerBlendInstruction(
            layerTrackIDs: layerTrackIDs,
            blendModes: blendModes,
            transforms: transforms,
            sourceIndices: sourceIndices,
            timeRange: timeRange,
            stillImages: stillImages
        )
    }
}
