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
struct HypnogramRecipe: Codable {
    var sources: [HypnogramSource]
    var targetDuration: CMTime

    /// Playback rate (1.0 = normal speed, 0.5 = half speed, 2.0 = double speed)
    var playRate: Float

    /// The global effect chain - contains effect definitions and handles instantiation/application.
    /// This is the single source of truth for effects. Use effectChain.apply() to apply effects.
    var effectChain: EffectChain

    /// Base64-encoded JPEG snapshot of the hypnogram (1080p resolution)
    var snapshot: String?

    private enum CodingKeys: String, CodingKey {
        case sources, targetDuration, playRate, effectChain, snapshot
    }

    init(
        sources: [HypnogramSource],
        targetDuration: CMTime,
        playRate: Float = 1.0,
        effectChain: EffectChain? = nil,
        snapshot: String? = nil
    ) {
        self.sources = sources
        self.targetDuration = targetDuration
        self.playRate = playRate
        self.effectChain = effectChain ?? EffectChain()
        self.snapshot = snapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decode([HypnogramSource].self, forKey: .sources)
        targetDuration = try container.decode(CodableCMTime.self, forKey: .targetDuration).cmTime
        playRate = try container.decodeIfPresent(Float.self, forKey: .playRate) ?? 1.0
        effectChain = try container.decodeIfPresent(EffectChain.self, forKey: .effectChain) ?? EffectChain()
        snapshot = try container.decodeIfPresent(String.self, forKey: .snapshot)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sources, forKey: .sources)
        try container.encode(CodableCMTime(targetDuration), forKey: .targetDuration)
        try container.encode(playRate, forKey: .playRate)
        try container.encode(effectChain, forKey: .effectChain)
        try container.encodeIfPresent(snapshot, forKey: .snapshot)
    }

    /// Create a deep copy with fresh effect instances for export.
    /// This prevents export from sharing mutable state with preview.
    func copyForExport() -> HypnogramRecipe {
        // Copy per-source effect chains
        let copiedSources = sources.map { source in
            var copy = source
            copy.effectChain = source.effectChain.copy()
            return copy
        }

        return HypnogramRecipe(
            sources: copiedSources,
            targetDuration: targetDuration,
            playRate: playRate,
            effectChain: effectChain.copy()
        )
    }
}
