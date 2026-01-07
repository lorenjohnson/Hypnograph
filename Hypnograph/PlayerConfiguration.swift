//
//  PlayerConfiguration.swift
//  Hypnograph
//
//  Per-player configuration that can differ between montage/sequence/live players.
//  Groups related display and generation settings into a single, cohesive structure.
//
//  Note: targetDuration and playRate are stored in HypnogramRecipe, not here.
//  Each mode (montage/sequence) has its own lastRecipe that persists these values.
//

import Foundation
import HypnoCore

/// Configuration for a player (montage, sequence, or live).
/// Each player maintains its own independent configuration.
///
/// Note: `targetDuration` and `playRate` live on the recipe, not here.
/// Each mode stores its own `lastRecipe` which persists these values.
struct PlayerConfiguration: Codable {

    // MARK: - Display Settings

    /// Aspect ratio for rendering
    var aspectRatio: AspectRatio

    /// Output resolution
    var playerResolution: OutputResolution

    // MARK: - Generation Settings

    /// Max sources when generating new random hypnograms
    var maxSourcesForNew: Int

    // MARK: - Recipe Persistence

    /// Last recipe for this mode (persists targetDuration, playRate, sources, effects)
    var lastRecipe: HypnogramRecipe?

    // MARK: - Initialization

    /// Initialize with global defaults from Settings (uses montage config)
    init(from settings: Settings) {
        self = settings.montagePlayerConfig
    }

    /// Initialize with explicit values
    init(
        aspectRatio: AspectRatio,
        playerResolution: OutputResolution,
        maxSourcesForNew: Int,
        lastRecipe: HypnogramRecipe? = nil
    ) {
        self.aspectRatio = aspectRatio
        self.playerResolution = playerResolution
        self.maxSourcesForNew = maxSourcesForNew
        self.lastRecipe = lastRecipe
    }

    // MARK: - View Identity

    /// Stable identity string for SwiftUI .id() - includes all config properties
    /// so view rebuilds when any config changes
    var viewID: String {
        "\(aspectRatio.displayString)-\(playerResolution.rawValue)-\(maxSourcesForNew)"
    }
}
