//
//  EffectRegistry.swift
//  Hypnograph
//
//  Registry that maps effect type names to factory functions.
//  Enables JSON config to instantiate RenderHook objects by name.
//

import Foundation
import CoreGraphics

/// Factory function type - takes params dictionary, returns RenderHook
typealias EffectFactory = ([String: AnyCodableValue]?) -> RenderHook?

/// Registry of effect types that can be instantiated from config
enum EffectRegistry {
    
    /// Map of type names to factory functions
    static let factories: [String: EffectFactory] = [
        
        // MARK: - Core Effects
        
        "BlackAndWhiteHook": { params in
            let contrast = params?["contrast"]?.floatValue ?? 1.0
            return BlackAndWhiteHook(contrast: contrast)
        },
        
        "RGBSplitSimpleHook": { params in
            let offsetAmount = params?["offsetAmount"]?.floatValue ?? 10.0
            let animated = params?["animated"]?.boolValue ?? true
            return RGBSplitSimpleHook(offsetAmount: offsetAmount, animated: animated)
        },
        
        // MARK: - Temporal Effects
        
        "GhostBlurHook": { params in
            let intensity = params?["intensity"]?.floatValue ?? 0.5
            let trailLength = params?["trailLength"]?.intValue ?? 6
            let blurAmount = params?["blurAmount"]?.doubleValue.map { CGFloat($0) } ?? 8.0
            return GhostBlurHook(intensity: intensity, trailLength: trailLength, blurAmount: blurAmount)
        },
        
        "HoldFrameHook": { params in
            let freezeInterval = params?["freezeInterval"]?.doubleValue ?? 8.0
            let holdDuration = params?["holdDuration"]?.doubleValue ?? 4.0
            let trailBoost = params?["trailBoost"]?.doubleValue ?? 1.5
            return HoldFrameHook(freezeInterval: freezeInterval, holdDuration: holdDuration, trailBoost: trailBoost)
        },
        
        "ColorEchoHook": { params in
            let channelOffset = params?["channelOffset"]?.intValue ?? 2
            return ColorEchoHook(channelOffset: channelOffset)
        },
        
        "FrameDifferenceHook": { params in
            let originalBlend = params?["originalBlend"]?.floatValue ?? 0.3
            let boost = params?["boost"]?.floatValue ?? 2.0
            return FrameDifferenceHook(originalBlend: originalBlend, boost: boost)
        },
        
        "FeedbackLoopHook": { params in
            let scale = params?["scale"]?.doubleValue.map { CGFloat($0) } ?? 0.95
            let rotation = params?["rotation"]?.doubleValue.map { CGFloat($0) } ?? 0.01
            let intensity = params?["intensity"]?.floatValue ?? 0.5
            return FeedbackLoopHook(scale: scale, rotation: rotation, intensity: intensity)
        },
        
        // MARK: - Datamosh
        
        "DatamoshMetalHook": { params in
            // Build DatamoshParams from individual values
            let datamoshParams = DatamoshParams(
                minHistoryOffset: params?["minHistoryOffset"]?.intValue ?? 15,
                maxHistoryOffset: params?["maxHistoryOffset"]?.intValue ?? 70,
                freezeReference: params?["freezeReference"]?.boolValue ?? false,
                frozenHistoryOffset: params?["frozenHistoryOffset"]?.intValue,
                blockSize: params?["blockSize"]?.intValue ?? 10,
                blockMoshProbability: params?["blockMoshProbability"]?.floatValue ?? 0.25,
                motionSensitivity: params?["motionSensitivity"]?.floatValue ?? 0.85,
                updateProbability: params?["updateProbability"]?.floatValue ?? 0.0,
                smearStrength: params?["smearStrength"]?.floatValue ?? 0.45,
                jitterAmount: params?["jitterAmount"]?.floatValue ?? 0.25,
                feedbackAmount: params?["feedbackAmount"]?.floatValue ?? 0.4,
                blockiness: params?["blockiness"]?.floatValue ?? 0.0,
                burstChance: params?["burstChance"]?.floatValue ?? 0.008,
                minBurstDuration: params?["minBurstDuration"]?.intValue ?? 60,
                maxBurstDuration: params?["maxBurstDuration"]?.intValue ?? 240,
                cleanFrameChance: params?["cleanFrameChance"]?.floatValue ?? 0.0,
                intensityVariation: params?["intensityVariation"]?.floatValue ?? 0.5,
                randomSeed: UInt32(params?["randomSeed"]?.intValue ?? 0)
            )
            return DatamoshMetalHook(params: datamoshParams)
        },
        
        // MARK: - Visual Effects

        "MirrorKaleidoHook": { params in
            let intensity = params?["intensity"]?.floatValue ?? 0.8
            return MirrorKaleidoHook(intensity: intensity)
        },

        // MARK: - Metal Effects

        "PixelateMetalHook": { params in
            let blockSize = params?["blockSize"]?.intValue ?? 8
            return PixelateMetalHook(blockSize: blockSize)
        }
    ]
    
    /// Create a RenderHook from a type name and parameters
    static func create(type: String, params: [String: AnyCodableValue]?) -> RenderHook? {
        guard let factory = factories[type] else {
            print("⚠️ EffectRegistry: Unknown effect type '\(type)'")
            return nil
        }
        return factory(params)
    }
}

