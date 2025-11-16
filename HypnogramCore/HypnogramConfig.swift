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
    /// If true, each new hypnogram starts with all layers pre-filled
    /// with random clips + random blend modes.
    var autoPrime: Bool

    /// Seconds of inactivity before auto-priming a new set (only when autoPrime == true).
    var autoPrimeTimeout: Double

    /// Blend mode names (e.g. "multiply", "screen", ...).
    var blendModes: [String]

    /// Maximum number of layers in a hypnogram.
    var maxLayers: Int

    /// Where to scan for source video files.
    var sourceFolders: [String]

    /// Folder where rendered hypnograms are written.
    var outputFolder: String

    /// Optional explicit output height in pixels (0 = use default logic).
    var outputHeight: Int

    /// Target clip length (seconds) per layer.
    var outputSeconds: Double

    /// Optional explicit output width in pixels (0 = use default logic).
    var outputWidth: Int

    /// Explicit init so call sites don't depend on property order.
    init(
        autoPrime: Bool,
        autoPrimeTimeout: Double = 120,
        blendModes: [String],
        maxLayers: Int,
        outputFolder: String,
        outputHeight: Int = 0,
        outputSeconds: Double,
        outputWidth: Int = 0,
        sourceFolders: [String]
    ) {
        self.autoPrime = autoPrime
        self.autoPrimeTimeout = autoPrimeTimeout
        self.blendModes = blendModes
        self.maxLayers = maxLayers
        self.outputFolder = outputFolder
        self.outputHeight = outputHeight
        self.outputSeconds = outputSeconds
        self.outputWidth = outputWidth
        self.sourceFolders = sourceFolders
    }
}

/// Simple helper for loading configuration from disk.
/// Later you can add a `save(_:)` here if you build an in-app editor.
enum ConfigLoader {
    static func load(from url: URL) throws -> HypnogramConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(HypnogramConfig.self, from: data)
    }
}
