//
//  EffectRegistry.swift
//  Hypnograph
//
//  Registry that maps effect type names to their metatypes.
//  Enables JSON config to instantiate Effect objects by name using init?(params:).
//

import Foundation
import CoreGraphics

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

    // MARK: - Hook Type Mapping

    /// Map of type names to hook metatypes.
    /// Each hook declares its own parameterSpecs and init?(params:) - the hook is the source of truth.
    static let hookTypes: [String: any Effect.Type] = [
        // Core Effects
        "RGBSplitSimpleHook": RGBSplitSimpleHook.self,

        // Temporal Effects
        "GhostBlurHook": GhostBlurHook.self,
        "HoldFrameHook": HoldFrameHook.self,
        "ColorEchoHook": ColorEchoHook.self,
        "ColorEchoMetalHook": ColorEchoMetalHook.self,
        "FrameDifferenceHook": FrameDifferenceHook.self,
        "FeedbackLoopHook": FeedbackLoopHook.self,
        "TemporalSmearHook": TemporalSmearHook.self,

        // Datamosh
        "DatamoshMetalHook": DatamoshMetalHook.self,

        // Visual Effects
        "EdgeDecayHook": EdgeDecayHook.self,
        "HueWobbleHook": HueWobbleHook.self,
        "PixelSortHook": PixelSortHook.self,
        "PosterizeDecayHook": PosterizeDecayHook.self,

        // Metal Effects
        "PixelateMetalHook": PixelateMetalHook.self,
        "BasicHook": BasicHook.self,
        "GaussianBlurMetalHook": GaussianBlurMetalHook.self,
        "BlockFreezeMetalHook": BlockFreezeMetalHook.self,
        "PixelDriftMetalHook": PixelDriftMetalHook.self,
        "GlitchBlocksMetalHook": GlitchBlocksMetalHook.self,
        "TimeShuffleMetalHook": TimeShuffleMetalHook.self,
        "CompressionMetalHook": CompressionMetalHook.self,
        "IFrameCompressHook": IFrameCompressHook.self,

        // Color Effects
        "LUTHook": LUTHook.self,

        // Overlay Effects
        "TextOverlayHook": TextOverlayHook.self
    ]

    /// Create an Effect from a type name and parameters using init?(params:)
    static func create(type: String, params: [String: AnyCodableValue]?) -> Effect? {
        guard let hookType = hookTypes[type] else {
            print("⚠️ EffectRegistry: Unknown effect type '\(type)'")
            return nil
        }
        return hookType.init(params: params)
    }

    /// Available single effect types for adding to chains
    static var availableEffectTypes: [(type: String, displayName: String)] {
        hookTypes.keys
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

