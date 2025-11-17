//
//  Settings.swift
//  Hypnograph
//
//  Created by Loren Johnson on 15.11.25.
//  Consolidated Settings
//

import Foundation
import AppKit

// -------------------------------------------------------------
//  First stage: raw decoded JSON (no tilde expansion, no logic)
// -------------------------------------------------------------
public struct SettingsParams: Codable {
    public var autoPrime: Bool
    public var autoPrimeTimeout: Double
    public var blendModes: [String]
    public var maxLayers: Int
    public var sourceFolders: [String]
    public var outputFolder: String
    public var outputHeight: Int
    public var outputSeconds: Double
    public var outputWidth: Int
}

// -------------------------------------------------------------
//  Normalized Settings used by the app everywhere
// -------------------------------------------------------------
public struct Settings: Codable {
    public var autoPrime: Bool
    public var autoPrimeTimeout: Double
    public var blendModes: [String]
    public var maxLayers: Int
    public var sourceFolders: [String]
    public var outputFolder: String
    public var outputHeight: Int
    public var outputSeconds: Double
    public var outputWidth: Int

    // Main initializer with normalization
    public init(
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
    public init(_ p: SettingsParams) {
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
public enum SettingsLoader {
    public static func load(from url: URL) throws -> Settings {
        let data = try Data(contentsOf: url)
        let params = try JSONDecoder().decode(SettingsParams.self, from: data)
        return Settings(params)   // always normalize
    }
}
