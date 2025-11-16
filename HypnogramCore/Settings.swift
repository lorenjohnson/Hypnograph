//
//  Settings.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation

// -------------------------------------------------------------
//  First stage: raw decoded JSON (no tilde expansion, no logic)
// -------------------------------------------------------------
struct SettingsParams: Codable {
    var autoPrime: Bool
    var autoPrimeTimeout: Double
    var blendModes: [String]
    var maxLayers: Int
    var sourceFolders: [String]
    var outputFolder: String
    var outputHeight: Int
    var outputSeconds: Double
    var outputWidth: Int
}

// -------------------------------------------------------------
//  Normalized Settings used by the app everywhere
// -------------------------------------------------------------
struct Settings: Codable {

    var autoPrime: Bool
    var autoPrimeTimeout: Double
    var blendModes: [String]
    var maxLayers: Int
    var sourceFolders: [String]
    var outputFolder: String
    var outputHeight: Int
    var outputSeconds: Double
    var outputWidth: Int

    // Main initializer with normalization
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

        // Normalize + expand ~
        self.outputFolder = (outputFolder as NSString).expandingTildeInPath
        self.sourceFolders = sourceFolders.map { ($0 as NSString).expandingTildeInPath }

        self.outputHeight = outputHeight
        self.outputSeconds = outputSeconds
        self.outputWidth = outputWidth
    }

    // Convenience initializer for decoding normalized Settings
    init(_ p: SettingsParams) {
        self.init(
            autoPrime: p.autoPrime,
            autoPrimeTimeout: p.autoPrimeTimeout,
            blendModes: p.blendModes,
            maxLayers: p.maxLayers,
            outputFolder: p.outputFolder,
            outputHeight: p.outputHeight,
            outputSeconds: p.outputSeconds,
            outputWidth: p.outputWidth,
            sourceFolders: p.sourceFolders
        )
    }
}

// -------------------------------------------------------------
//  Loader: JSON → SettingsParams → Settings
// -------------------------------------------------------------
enum SettingsLoader {
    static func load(from url: URL) throws -> Settings {
        let data = try Data(contentsOf: url)
        let params = try JSONDecoder().decode(SettingsParams.self, from: data)
        return Settings(params)   // always normalize
    }
}
