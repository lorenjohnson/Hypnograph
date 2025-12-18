//
//  HypnogramRecipe.swift
//  Hypnograph
//
//  "Blueprint" for a render: pure data, no renderer knowledge.
//  This is the single source of truth for a hypnogram composition.
//

import Foundation
import CoreMedia

// MARK: - Hypnogram recipe

/// A complete "hypnogram" recipe: ordered sources, effects, and target render duration.
/// This is the single source of truth for everything about a hypnogram composition.
struct HypnogramRecipe {
    var sources: [HypnogramSource]
    var targetDuration: CMTime

    /// Effects applied to the final composed image (after all sources are blended).
    /// Currently the UI only supports one effect, but the model supports a chain.
    var effects: [RenderHook]

    init(
        sources: [HypnogramSource],
        targetDuration: CMTime,
        effects: [RenderHook] = []
    ) {
        self.sources = sources
        self.targetDuration = targetDuration
        self.effects = effects
    }

    /// Create a deep copy with fresh effect instances for export.
    /// This prevents export from sharing mutable state with preview.
    func copyForExport() -> HypnogramRecipe {
        // Copy global effects
        let copiedEffects = effects.map { $0.copy() }

        // Copy per-source effects
        let copiedSources = sources.map { source in
            var copy = source
            copy.effects = source.effects.map { $0.copy() }
            return copy
        }

        return HypnogramRecipe(
            sources: copiedSources,
            targetDuration: targetDuration,
            effects: copiedEffects
        )
    }
}
