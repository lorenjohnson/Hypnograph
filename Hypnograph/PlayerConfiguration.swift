//
//  PlayerConfiguration.swift
//  Hypnograph
//
//  Per-player configuration that can differ between montage/sequence/live players.
//  Groups related display and generation settings into a single, cohesive structure.
//

import Foundation
import CoreMedia

/// Configuration for a player (montage, sequence, or live).
/// Each player maintains its own independent configuration.
struct PlayerConfiguration: Codable {

    // MARK: - Display Settings

    /// Aspect ratio for rendering
    var aspectRatio: AspectRatio

    /// Output resolution
    var playerResolution: OutputResolution

    // MARK: - Generation Settings

    /// Max sources when generating new random hypnograms
    var maxSourcesForNew: Int

    /// Target duration for new hypnograms
    var targetDuration: CMTime

    /// Default playback rate for this player
    var playRate: Float

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
        targetDuration: CMTime,
        playRate: Float = 1.0
    ) {
        self.aspectRatio = aspectRatio
        self.playerResolution = playerResolution
        self.maxSourcesForNew = maxSourcesForNew
        self.targetDuration = targetDuration
        self.playRate = playRate
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case aspectRatio, playerResolution, maxSourcesForNew
        case targetDurationSeconds, playRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aspectRatio = try container.decode(AspectRatio.self, forKey: .aspectRatio)
        playerResolution = try container.decode(OutputResolution.self, forKey: .playerResolution)
        maxSourcesForNew = try container.decode(Int.self, forKey: .maxSourcesForNew)
        let seconds = try container.decode(Double.self, forKey: .targetDurationSeconds)
        targetDuration = CMTime(seconds: seconds, preferredTimescale: 600)
        playRate = try container.decodeIfPresent(Float.self, forKey: .playRate) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(playerResolution, forKey: .playerResolution)
        try container.encode(maxSourcesForNew, forKey: .maxSourcesForNew)
        try container.encode(targetDuration.seconds, forKey: .targetDurationSeconds)
        try container.encode(playRate, forKey: .playRate)
    }

    // MARK: - View Identity

    /// Stable identity string for SwiftUI .id() - includes all config properties
    /// so view rebuilds when any config changes
    var viewID: String {
        "\(aspectRatio.displayString)-\(playerResolution.rawValue)-\(maxSourcesForNew)-\(targetDuration.seconds)-\(playRate)"
    }
}
