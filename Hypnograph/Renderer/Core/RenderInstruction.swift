//
//  RenderInstruction.swift
//  Hypnograph
//
//  Instruction format for the frame compositor
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreImage

/// Instruction for rendering a time range
/// Tells the compositor which layers to blend, how to transform them, etc.
final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    
    // MARK: - AVVideoCompositionInstructionProtocol
    
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = true
    let containsTweening: Bool = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    
    // MARK: - Custom Properties
    
    /// Track IDs for each layer (bottom to top)
    let layerTrackIDs: [CMPersistentTrackID]
    
    /// Blend mode for each layer (CIBlendMode constant names)
    let blendModes: [String]
    
    /// Transform for each layer (includes orientation from media metadata)
    let transforms: [CGAffineTransform]

    /// User-applied rotation in degrees (0, 90, 180, 270) for each layer
    let rotations: [Int]

    /// Map each layer to a source index in the recipe (for effects)
    let sourceIndices: [Int]

    /// Whether to apply render hooks
    let enableEffects: Bool

    /// Still images for layers that are images (indexed by layer, nil for video layers)
    let stillImages: [CIImage?]

    // MARK: - Initialization

    init(
        timeRange: CMTimeRange,
        layerTrackIDs: [CMPersistentTrackID],
        blendModes: [String],
        transforms: [CGAffineTransform],
        rotations: [Int] = [],
        sourceIndices: [Int],
        enableEffects: Bool = false,  // disabled in skeleton
        stillImages: [CIImage?] = []
    ) {
        self.timeRange = timeRange
        self.layerTrackIDs = layerTrackIDs
        self.blendModes = blendModes
        self.transforms = transforms
        self.rotations = rotations.isEmpty ? Array(repeating: 0, count: layerTrackIDs.count) : rotations
        self.sourceIndices = sourceIndices
        self.enableEffects = enableEffects
        self.stillImages = stillImages

        // Required track IDs for AVFoundation
        // Must wrap CMPersistentTrackID as NSNumber
        // For still images, we still need track IDs even though tracks are empty
        self.requiredSourceTrackIDs = layerTrackIDs.map { NSNumber(value: $0) }

        super.init()
    }
    
    // MARK: - Debug
    
    override var description: String {
        let range = "\(timeRange.start.seconds)s → \(timeRange.end.seconds)s"
        let layers = layerTrackIDs.count
        return "RenderInstruction[\(range), \(layers) layers]"
    }
}

