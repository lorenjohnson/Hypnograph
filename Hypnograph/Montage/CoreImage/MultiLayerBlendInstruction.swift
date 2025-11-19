//
//  MultiLayerBlendInstruction.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//


//
//  MultiLayerBlendInstruction.swift
//  Hypnograph
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

/// Instruction describing how to composite a single segment:
/// - which track IDs to use as layers
/// - which blend modes (one per layer, same order)
/// - per-layer transforms (usually the original track's preferredTransform)
public final class MultiLayerBlendInstruction: NSObject, AVVideoCompositionInstructionProtocol {
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
