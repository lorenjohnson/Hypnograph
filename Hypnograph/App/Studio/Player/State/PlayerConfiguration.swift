//
//  PlayerConfiguration.swift
//  Hypnograph
//
//  Per-player generation configuration.
//
//  Note: display and document-level player settings now live on the working Hypnogram.
//

import Foundation
import HypnoCore

/// Configuration for generation behavior.
struct PlayerConfiguration: Codable {
    static let defaultMaxLayers: Int = 1

    static func defaultValue(maxLayers: Int = defaultMaxLayers) -> PlayerConfiguration {
        PlayerConfiguration(maxLayers: maxLayers)
    }

    // MARK: - Generation StudioSettings

    /// Max layers when generating new random clips (each layer is one simultaneously-playing source)
    var maxLayers: Int

    // MARK: - Initialization

    /// Initialize with explicit values
    init(
        maxLayers: Int
    ) {
        self.maxLayers = maxLayers
    }

    private enum CodingKeys: String, CodingKey {
        case maxLayers
        // Backward-compatible decode key used by older settings files.
        case maxSourcesForNew
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxLayers = try container.decodeIfPresent(Int.self, forKey: .maxLayers)
            ?? container.decodeIfPresent(Int.self, forKey: .maxSourcesForNew)
            ?? 5
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxLayers, forKey: .maxLayers)
    }
}
