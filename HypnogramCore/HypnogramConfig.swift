//
//  HypnogramConfig.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//


import Foundation

/// Represents the configurable settings for Hypnogram.
/// Loaded from a JSON file at app startup.
struct HypnogramConfig: Codable {
    var sourceFolders: [String]
    var clipLengthSeconds: Double
    var maxLayers: Int
    var blendModes: [String]
    var outputFolder: String
}

/// Simple helper for loading configuration from disk.
/// Later you can add a `save(_:)` here if you build an in-app editor.
enum ConfigLoader {
    static func load(from url: URL) throws -> HypnogramConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(HypnogramConfig.self, from: data)
    }
}
