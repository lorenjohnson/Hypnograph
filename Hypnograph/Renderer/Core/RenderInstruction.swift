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

    /// Combined transform for each layer (metadata orientation + user transform)
    let transforms: [CGAffineTransform]

    /// Map each layer to a source index in the recipe (for effects)
    let sourceIndices: [Int]

    /// Whether to apply render hooks
    let enableEffects: Bool

    /// Still images for layers that are images (indexed by layer, nil for video layers)
    let stillImages: [CIImage?]

    /// The EffectManager to use for effects processing.
    /// - Preview: passes state.effectManager (mutable, changes affect playback)
    /// - Performance Display: passes performanceDisplay.effectManager (isolated instance)
    /// - Export: passes a freshly created manager from recipe.copyForExport()
    weak var hookManager: EffectManager?

    // MARK: - Initialization

    init(
        timeRange: CMTimeRange,
        layerTrackIDs: [CMPersistentTrackID],
        blendModes: [String],
        transforms: [CGAffineTransform],
        sourceIndices: [Int],
        enableEffects: Bool = false,
        stillImages: [CIImage?] = [],
        hookManager: EffectManager? = nil
    ) {
        self.timeRange = timeRange
        self.layerTrackIDs = layerTrackIDs
        self.blendModes = blendModes
        self.transforms = transforms
        self.sourceIndices = sourceIndices
        self.enableEffects = enableEffects
        self.stillImages = stillImages
        self.hookManager = hookManager

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

