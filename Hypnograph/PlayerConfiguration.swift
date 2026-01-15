//
//  PlayerConfiguration.swift
//  Hypnograph
//
//  Per-player configuration (preview + live).
//  Groups related display and generation settings into a single, cohesive structure.
//
//  Note: targetDuration and playRate are stored in HypnogramRecipe, not here.
//  The last used recipe persists these values.
//

import Foundation
import HypnoCore

/// Configuration for a player (preview or live).
/// Each player maintains its own independent configuration.
///
/// Note: `targetDuration` and `playRate` live on the recipe, not here.
/// `lastRecipe` persists these values.
struct PlayerConfiguration: Codable {

    // MARK: - Display Settings

    /// Aspect ratio for rendering
    var aspectRatio: AspectRatio

    /// Output resolution
    var playerResolution: OutputResolution

    // MARK: - Generation Settings

    /// Max layers when generating new random clips (each layer is one simultaneously-playing source)
    var maxLayers: Int

    // MARK: - Recipe Persistence

    /// Last recipe for this mode (persists targetDuration, playRate, sources, effects)
    var lastRecipe: HypnogramRecipe?

    // MARK: - Initialization

    /// Initialize with global defaults from Settings (uses montage config)
    init(from settings: Settings) {
        self = settings.playerConfig
    }

    /// Initialize with explicit values
    init(
        aspectRatio: AspectRatio,
        playerResolution: OutputResolution,
        maxLayers: Int,
        lastRecipe: HypnogramRecipe? = nil
    ) {
        self.aspectRatio = aspectRatio
        self.playerResolution = playerResolution
        self.maxLayers = maxLayers
        self.lastRecipe = lastRecipe
    }

    private enum CodingKeys: String, CodingKey {
        case aspectRatio, playerResolution, maxLayers, lastRecipe
        // Legacy (pre-unify): maxSourcesForNew
        case maxSourcesForNew
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aspectRatio = try container.decode(AspectRatio.self, forKey: .aspectRatio)
        playerResolution = try container.decode(OutputResolution.self, forKey: .playerResolution)
        maxLayers = try container.decodeIfPresent(Int.self, forKey: .maxLayers)
            ?? container.decodeIfPresent(Int.self, forKey: .maxSourcesForNew)
            ?? 5
        lastRecipe = try container.decodeIfPresent(HypnogramRecipe.self, forKey: .lastRecipe)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(playerResolution, forKey: .playerResolution)
        try container.encode(maxLayers, forKey: .maxLayers)
        try container.encodeIfPresent(lastRecipe, forKey: .lastRecipe)
    }

    // MARK: - View Identity

    /// Stable identity string for SwiftUI .id() - includes all config properties
    /// so view rebuilds when any config changes
    var viewID: String {
        "\(aspectRatio.displayString)-\(playerResolution.rawValue)-\(maxLayers)"
    }
}
