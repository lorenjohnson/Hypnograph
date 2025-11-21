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

/// Instruction describing how to composite a single segment:
/// - which track IDs to use as sources
/// - which blend modes (one per layer, same order)
/// - per-layer transforms (usually the original track's preferredTransform)
/// - original source indices (for applying per-source effects correctly)
public final class MultiLayerBlendInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    public var timeRange: CMTimeRange
    public var enablePostProcessing: Bool = false
    public var containsTweening: Bool = false

    public var requiredSourceTrackIDs: [NSValue]?
    public var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let layerTrackIDs: [CMPersistentTrackID]
    let blendModes: [String]
    var sourceTransforms: [CGAffineTransform]
    let sourceIndices: [Int] // Maps track position → original layer index

    public init(
        layerTrackIDs: [CMPersistentTrackID],
        blendModes: [String],
        transforms: [CGAffineTransform],
        sourceIndices: [Int],
        timeRange: CMTimeRange
    ) {
        self.timeRange       = timeRange
        self.layerTrackIDs   = layerTrackIDs
        self.blendModes      = blendModes
        self.sourceTransforms = transforms
        self.sourceIndices   = sourceIndices
        self.requiredSourceTrackIDs = layerTrackIDs.map { NSNumber(value: $0) }
    }
}
