//
//  Settings.swift
//  Hypnograph
//
//  Created by Loren Johnson on 15.11.25.
//  Consolidated Settings
//

import Foundation
import AppKit
import CoreGraphics
import CoreMedia

// -------------------------------------------------------------
//  First stage: raw decoded JSON (no tilde expansion, no logic)
// -------------------------------------------------------------
public struct SettingsParams: Codable {
    public var autoPrime: Bool
    public var autoPrimeTimeout: Double
    public var blendModes: [String]
    public var maxSources: Int
    public var sourceFolders: [String]
    public var outputFolder: String
    public var outputHeight: Int
    public var outputSeconds: Double
    public var outputWidth: Int
}

// -------------------------------------------------------------
//  Normalized Settings used by the app everywhere
// -------------------------------------------------------------
public struct Settings {
    public var autoPrime: Bool
    public var autoPrimeTimeout: Double
    public var blendModes: [String]
    public var maxSources: Int
    public var sourceFolders: [String]
    public var outputSize: CGSize
    public var outputDuration: CMTime
    public var outputURL: URL

    // Main initializer with normalization
    public init(
        autoPrime: Bool,
        autoPrimeTimeout: Double = 120,
        blendModes: [String],
        maxSources: Int,
        outputFolder: String,
        outputHeight: Int = 0,
        outputSeconds: Double,
        outputWidth: Int = 0,
        sourceFolders: [String]
    ) {
        self.autoPrime = autoPrime
        self.autoPrimeTimeout = autoPrimeTimeout
        self.blendModes = blendModes
        self.maxSources = maxSources
        self.outputDuration = CMTime(
            seconds: outputSeconds,
            preferredTimescale: 600
        )
        self.outputSize = Self._computeOutputSize(
            outputHeight: outputHeight,
            outputWidth: outputWidth
        )
        self.outputURL  = URL(
            fileURLWithPath: (outputFolder as NSString).expandingTildeInPath,
            isDirectory: true
        )
        self.sourceFolders = sourceFolders.map { ($0 as NSString).expandingTildeInPath }
    }
    
    /// - if both outputWidth & outputHeight > 0 → use them exactly
    /// - if only width > 0 → derive height with 16:9 (height = width * 9/16)
    /// - if only height > 0 → derive width with 16:9 (width = height * 16/9)
    /// - if both are 0 → default 1920x1080
    private static func _computeOutputSize(outputHeight: Int, outputWidth: Int) -> CGSize {
        let defaultW: CGFloat = 1920
        let defaultH: CGFloat = 1080
        let aspect: CGFloat   = 9.0 / 16.0   // height / width (16:9)

        let w = CGFloat(outputWidth)
        let h = CGFloat(outputHeight)

        switch (w > 0, h > 0) {
        case (true, true):
            return CGSize(width: w, height: h)

        case (true, false):
            // width set, derive height (16:9)
            return CGSize(width: w, height: round(w * aspect))

        case (false, true):
            // height set, derive width (16:9)
            return CGSize(width: round(h / aspect), height: h)

        default:
            // neither set → default 1920x1080
            return CGSize(width: defaultW, height: defaultH)
        }
    }

    // Convenience initializer for decoding normalized Settings
    public init(_ p: SettingsParams) {
        self.init(
            autoPrime: p.autoPrime,
            autoPrimeTimeout: p.autoPrimeTimeout,
            blendModes: p.blendModes,
            maxSources: p.maxSources,
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
