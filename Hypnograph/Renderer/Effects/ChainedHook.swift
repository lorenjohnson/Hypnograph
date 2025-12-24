//
//  ChainedHook.swift
//  Hypnograph
//
//  Chains multiple RenderHooks together into a single effect pipeline.
//  Each hook's output becomes the next hook's input.
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Chains multiple RenderHooks together - output of each becomes input of next
/// Use this to create compound effects like "Hold Frame + Color Echo"
final class ChainedHook: Effect {
    /// Display name for the chain
    let name: String

    /// Maximum lookback of any hook in the chain
    var requiredLookback: Int {
        hooks.map { $0.requiredLookback }.max() ?? 0
    }

    /// The hooks to apply in order
    private let hooks: [RenderHook]

    /// Create a chained effect from multiple hooks
    /// - Parameters:
    ///   - name: Display name for the combined effect
    ///   - hooks: Array of hooks to apply in sequence
    init(name: String, hooks: [RenderHook]) {
        self.name = name
        self.hooks = hooks
    }

    /// Convenience initializer that auto-generates a name from hook names
    convenience init(hooks: [RenderHook]) {
        let name = hooks.map { $0.name }.joined(separator: " + ")
        self.init(name: name, hooks: hooks)
    }

    /// ChainedHook cannot be created from params directly - it's created via EffectConfigLoader
    convenience init?(params: [String: AnyCodableValue]?) {
        return nil
    }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        var result = image
        for hook in hooks {
            result = hook.willRenderFrame(&context, image: result)
        }
        return result
    }

    func reset() {
        for hook in hooks {
            hook.reset()
        }
    }

    func copy() -> Effect {
        // Copy all child hooks to create fresh instances
        let copiedHooks = hooks.map { $0.copy() }
        return ChainedHook(name: name, hooks: copiedHooks)
    }
}

