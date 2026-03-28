//
//  PlayerConfiguration.swift
//  Hypnograph
//
//  Per-player configuration (in-app + live).
//  Groups related display and generation settings into a single, cohesive structure.
//
//  Note: targetDuration and playRate are stored on Hypnogram (within Hypnogram), not here.
//

import Foundation
import HypnoCore

/// Configuration for a player (in-app or live).
/// Each player maintains its own independent configuration.
///
/// Note: `targetDuration` and `playRate` live on the recipe, not here.
struct PlayerConfiguration: Codable {

    // MARK: - Display StudioSettings

    /// Aspect ratio for rendering
    var aspectRatio: AspectRatio

    /// Output resolution
    var playerResolution: OutputResolution

    // MARK: - Generation StudioSettings

    /// Max layers when generating new random clips (each layer is one simultaneously-playing source)
    var maxLayers: Int

    // MARK: - Initialization

    /// Initialize with global defaults from StudioSettings
    init(from settings: StudioSettings) {
        self = settings.playerConfig
    }

    /// Initialize with explicit values
    init(
        aspectRatio: AspectRatio,
        playerResolution: OutputResolution,
        maxLayers: Int
    ) {
        self.aspectRatio = aspectRatio
        self.playerResolution = playerResolution
        self.maxLayers = maxLayers
    }

    private enum CodingKeys: String, CodingKey {
        case aspectRatio, playerResolution, maxLayers
        // Backward-compatible decode key used by older settings files.
        case maxSourcesForNew
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aspectRatio = try container.decode(AspectRatio.self, forKey: .aspectRatio)
        playerResolution = try container.decode(OutputResolution.self, forKey: .playerResolution)
        maxLayers = try container.decodeIfPresent(Int.self, forKey: .maxLayers)
            ?? container.decodeIfPresent(Int.self, forKey: .maxSourcesForNew)
            ?? 5
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(playerResolution, forKey: .playerResolution)
        try container.encode(maxLayers, forKey: .maxLayers)
    }

    // MARK: - View Identity

    /// Stable identity string for SwiftUI .id() - includes all config properties
    /// so view rebuilds when any config changes
    var viewID: String {
        "\(aspectRatio.displayString)-\(playerResolution.rawValue)-\(maxLayers)"
    }
}
