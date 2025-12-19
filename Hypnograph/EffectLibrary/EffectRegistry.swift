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

/// Parameter range metadata for UI sliders
struct ParameterRange {
    let min: Double
    let max: Double
    let step: Double?

    init(_ min: Double, _ max: Double, step: Double? = nil) {
        self.min = min
        self.max = max
        self.step = step
    }

    /// Default range for unknown parameters - uses value heuristics
    static let `default` = ParameterRange(0, 100)
}

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

    /// Available single effect types (not ChainedHook) for adding to chains
    static var availableEffectTypes: [(type: String, displayName: String)] {
        factories.keys
            .filter { $0 != "ChainedHook" }
            .sorted()
            .map { type in
                let displayName = type
                    .replacingOccurrences(of: "Hook", with: "")
                    .replacingOccurrences(of: "Metal", with: " Metal")
                return (type: type, displayName: displayName)
            }
    }

    // MARK: - Parameter Ranges

    /// Parameter ranges by effect type and param name
    static let parameterRanges: [String: [String: ParameterRange]] = [
        "BlackAndWhiteHook": [
            "contrast": ParameterRange(0.5, 2.0)
        ],
        "RGBSplitSimpleHook": [
            "offsetAmount": ParameterRange(1, 100)
        ],
        "GhostBlurHook": [
            "intensity": ParameterRange(0, 1),
            "trailLength": ParameterRange(1, 20, step: 1),
            "blurAmount": ParameterRange(0, 50)
        ],
        "HoldFrameHook": [
            "freezeInterval": ParameterRange(1, 30),
            "holdDuration": ParameterRange(0.5, 20),
            "trailBoost": ParameterRange(0.5, 5)
        ],
        "ColorEchoHook": [
            "channelOffset": ParameterRange(1, 10, step: 1)
        ],
        "FrameDifferenceHook": [
            "originalBlend": ParameterRange(0, 1),
            "boost": ParameterRange(0.5, 10)
        ],
        "FeedbackLoopHook": [
            "scale": ParameterRange(0.8, 1.2),
            "rotation": ParameterRange(-0.1, 0.1),
            "intensity": ParameterRange(0, 1)
        ],
        "DatamoshMetalHook": [
            "minHistoryOffset": ParameterRange(1, 60, step: 1),
            "maxHistoryOffset": ParameterRange(10, 120, step: 1),
            "blockSize": ParameterRange(4, 64, step: 1),
            "blockMoshProbability": ParameterRange(0, 1),
            "motionSensitivity": ParameterRange(0, 1),
            "updateProbability": ParameterRange(0, 1),
            "smearStrength": ParameterRange(0, 1),
            "jitterAmount": ParameterRange(0, 1),
            "feedbackAmount": ParameterRange(0, 1),
            "blockiness": ParameterRange(0, 1),
            "burstChance": ParameterRange(0, 0.1),
            "minBurstDuration": ParameterRange(10, 300, step: 1),
            "maxBurstDuration": ParameterRange(30, 600, step: 1),
            "cleanFrameChance": ParameterRange(0, 0.1),
            "intensityVariation": ParameterRange(0, 1)
        ],
        "MirrorKaleidoHook": [
            "intensity": ParameterRange(0, 1)
        ],
        "PixelateMetalHook": [
            "blockSize": ParameterRange(2, 128, step: 1)
        ]
    ]

    /// Get parameter range for a specific effect type and parameter name
    static func range(for effectType: String, param: String) -> ParameterRange? {
        parameterRanges[effectType]?[param]
    }

    // MARK: - Default Parameters

    /// Default parameter values for each effect type (used when adding new effects)
    static let defaultParams: [String: [String: AnyCodableValue]] = [
        "BlackAndWhiteHook": [
            "contrast": .double(1.0)
        ],
        "RGBSplitSimpleHook": [
            "offsetAmount": .double(15.0),
            "animated": .bool(true)
        ],
        "GhostBlurHook": [
            "intensity": .double(0.5),
            "trailLength": .int(6),
            "blurAmount": .double(8.0)
        ],
        "HoldFrameHook": [
            "freezeInterval": .double(8.0),
            "holdDuration": .double(4.0),
            "trailBoost": .double(1.5)
        ],
        "ColorEchoHook": [
            "channelOffset": .int(2)
        ],
        "FrameDifferenceHook": [
            "originalBlend": .double(0.3),
            "boost": .double(2.0)
        ],
        "FeedbackLoopHook": [
            "scale": .double(0.95),
            "rotation": .double(0.01),
            "intensity": .double(0.5)
        ],
        "DatamoshMetalHook": [
            "minHistoryOffset": .int(15),
            "maxHistoryOffset": .int(70),
            "blockSize": .int(10),
            "blockMoshProbability": .double(0.25),
            "motionSensitivity": .double(0.85),
            "smearStrength": .double(0.45),
            "jitterAmount": .double(0.25),
            "feedbackAmount": .double(0.3)
        ],
        "MirrorKaleidoHook": [
            "intensity": .double(0.8)
        ],
        "PixelateMetalHook": [
            "blockSize": .int(8)
        ]
    ]

    /// Get default parameters for an effect type
    static func defaults(for effectType: String) -> [String: AnyCodableValue] {
        defaultParams[effectType] ?? [:]
    }
}

