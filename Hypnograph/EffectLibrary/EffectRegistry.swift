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

/// Legacy parameter range metadata for UI sliders
/// Now derived from hook's parameterSpecs, but kept for API compatibility
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

    /// Create from ParameterSpec
    init(from spec: ParameterSpec) {
        if let range = spec.rangeAsDoubles {
            self.min = range.min
            self.max = range.max
        } else {
            self.min = 0
            self.max = 1
        }
        self.step = spec.step
    }
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
        },

        "BasicHook": { params in
            let opacity = params?["opacity"]?.floatValue ?? 1.0
            let contrast = params?["contrast"]?.floatValue ?? 0.0
            let brightness = params?["brightness"]?.floatValue ?? 0.0
            let saturation = params?["saturation"]?.floatValue ?? 0.0
            return BasicHook(opacity: opacity, contrast: contrast, brightness: brightness, saturation: saturation)
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
                (type: type, displayName: formatEffectTypeName(type))
            }
    }

    /// Format effect type name for display: "FrameDifferenceHook" -> "Frame Difference"
    static func formatEffectTypeName(_ type: String) -> String {
        // Remove "Hook" suffix
        var name = type
        if name.hasSuffix("Hook") {
            name = String(name.dropLast(4))
        }

        // Insert spaces before uppercase letters (camelCase to Title Case)
        var result = ""
        for (index, char) in name.enumerated() {
            if char.isUppercase && index > 0 {
                result += " "
            }
            result += String(char)
        }
        return result
    }

    // MARK: - Hook Type Mapping

    /// Map of type names to hook metatypes for parameter introspection.
    /// Each hook declares its own parameterSpecs - the hook is the source of truth.
    static let hookTypes: [String: any RenderHook.Type] = [
        "BlackAndWhiteHook": BlackAndWhiteHook.self,
        "RGBSplitSimpleHook": RGBSplitSimpleHook.self,
        "GhostBlurHook": GhostBlurHook.self,
        "HoldFrameHook": HoldFrameHook.self,
        "ColorEchoHook": ColorEchoHook.self,
        "FrameDifferenceHook": FrameDifferenceHook.self,
        "FeedbackLoopHook": FeedbackLoopHook.self,
        "DatamoshMetalHook": DatamoshMetalHook.self,
        "MirrorKaleidoHook": MirrorKaleidoHook.self,
        "PixelateMetalHook": PixelateMetalHook.self,
        "BasicHook": BasicHook.self
    ]

    // MARK: - Parameter Specs (from hooks)

    /// Get parameter specs for an effect type (from the hook's static property)
    static func parameterSpecs(for effectType: String) -> [String: ParameterSpec] {
        guard let hookType = hookTypes[effectType] else {
            return [:]
        }
        return hookType.parameterSpecs
    }

    /// Get parameter range for a specific effect type and parameter name
    /// Derived from the hook's parameterSpecs
    static func range(for effectType: String, param: String) -> ParameterRange? {
        guard let spec = parameterSpecs(for: effectType)[param] else {
            return nil
        }
        return ParameterRange(from: spec)
    }

    /// Get all parameter names for an effect type (in consistent order)
    static func parameterNames(for effectType: String) -> [String] {
        parameterSpecs(for: effectType).keys.sorted()
    }

    // MARK: - Default Parameters (from hooks)

    /// Get default parameters for an effect type
    /// Derived from the hook's parameterSpecs
    static func defaults(for effectType: String) -> [String: AnyCodableValue] {
        let specs = parameterSpecs(for: effectType)
        var defaults: [String: AnyCodableValue] = [:]
        for (name, spec) in specs {
            defaults[name] = spec.defaultValue
        }
        return defaults
    }
}

