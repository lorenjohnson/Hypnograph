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
//  Polymorphic sourceFolders param: [String] OR { libraryName: [String] }
// -------------------------------------------------------------

// -------------------------------------------------------------
//  Polymorphic sourceFolders param:
//  - [String]                       (single unnamed library)
//  - [String: String]              (named libraries → single path)
//  - [String: [String]]            (named libraries → many paths)
// -------------------------------------------------------------
enum SourceFoldersParam: Codable {
    case array([String])
    case dictionary([String: [String]])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // 1) Full form: { "name": [ "path1", "path2" ] }
        if let dictArray = try? container.decode([String: [String]].self) {
            self = .dictionary(dictArray)
            return
        }

        // 2) Shorthand: { "name": "single/path" }
        if let dictString = try? container.decode([String: String].self) {
            let converted = dictString.mapValues { [$0] }
            self = .dictionary(converted)
            return
        }

        // 3) Legacy/simple form: [ "path1", "path2" ]
        if let arr = try? container.decode([String].self) {
            self = .array(arr)
            return
        }

        throw DecodingError.typeMismatch(
            SourceFoldersParam.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected sourceFolders to be [String], [String: String], or [String: [String]]"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let arr):
            try container.encode(arr)
        case .dictionary(let dict):
            try container.encode(dict)
        }
    }

    /// All libraries as configured (no tilde expansion).
    /// - array form becomes ["default": array]
    var libraries: [String: [String]] {
        switch self {
        case .array(let arr):
            return ["default": arr]
        case .dictionary(let dict):
            return dict
        }
    }

    /// Best-effort order of libraries (useful for "first" semantics).
    /// For the array form, it's just ["default"].
    var libraryOrder: [String] {
        switch self {
        case .array:
            return ["default"]
        case .dictionary(let dict):
            return Array(dict.keys)
        }
    }

    /// Default key logic:
    /// - if "default" (any case) exists → use that
    /// - else use the first key
    var defaultKey: String {
        let libs = libraries

        if libs.keys.contains("default") {
            return "default"
        }
        if let key = libs.keys.first(where: { $0.lowercased() == "default" }) {
            return key
        }

        return libraryOrder.first ?? "default"
    }
}

// -------------------------------------------------------------
//  First stage: raw decoded JSON (no tilde expansion, no logic)
// -------------------------------------------------------------
struct SettingsParams: Codable {
    var autoPrime: Bool
    var autoPrimeTimeout: Double
    var maxSources: Int
    var sourceFolders: SourceFoldersParam
    var outputFolder: String
    var outputHeight: Int
    var outputSeconds: Double
    var outputWidth: Int
}

// -------------------------------------------------------------
//  Normalized Settings used by the app everywhere
// -------------------------------------------------------------
struct Settings {
    var autoPrime: Bool
    var autoPrimeTimeout: Double
    var maxSources: Int

    /// The *currently active* set of folders (default on startup).
    /// For multi-library configs this will be the default library’s folders.
    var sourceFolders: [String]

    /// All named libraries, fully expanded.
    /// - Key: library name (e.g. "renders", "photos", "default")
    /// - Value: tilde-expanded folder paths
    var sourceLibraries: [String: [String]]

    /// Raw order of library keys as they appear in the JSON (best effort).
    var sourceLibraryOrder: [String]

    /// Which library key should be treated as the default on startup.
    /// - If a "default" key exists, that wins.
    /// - Else the first key from the JSON object.
    var defaultSourceLibraryKey: String

    var outputSize: CGSize
    var outputDuration: CMTime
    var outputURL: URL

    // Main initializer with normalization for the "simple" case (single library).
    init(
        autoPrime: Bool,
        autoPrimeTimeout: Double = 120,
        maxSources: Int,
        outputFolder: String,
        outputHeight: Int = 0,
        outputSeconds: Double,
        outputWidth: Int = 0,
        sourceFolders: [String]
    ) {
        self.autoPrime = autoPrime
        self.autoPrimeTimeout = autoPrimeTimeout
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

        let expandedFolders = sourceFolders.map { ($0 as NSString).expandingTildeInPath }
        self.sourceFolders = expandedFolders

        // Single-library default normalization.
        self.sourceLibraries = ["default": expandedFolders]
        self.sourceLibraryOrder = ["default"]
        self.defaultSourceLibraryKey = "default"
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
    init(_ p: SettingsParams) {
        // First, interpret the polymorphic sourceFolders param.
        let sf = p.sourceFolders
        let rawLibraries = sf.libraries
        let rawOrder = sf.libraryOrder
        let defaultKey = sf.defaultKey

        // Expand tildes in *all* folders in *all* libraries.
        let expandedLibraries: [String: [String]] = rawLibraries.mapValues { folders in
            folders.map { ($0 as NSString).expandingTildeInPath }
        }

        // Determine which folders to treat as the default/active set.
        let defaultFolders = expandedLibraries[defaultKey]
            ?? (rawOrder.first.flatMap { expandedLibraries[$0] })
            ?? expandedLibraries.values.first
            ?? []

        // Call through to the simple initializer to reuse width/height/etc. logic.
        self.init(
            autoPrime: p.autoPrime,
            autoPrimeTimeout: p.autoPrimeTimeout,
            maxSources: p.maxSources,
            outputFolder: p.outputFolder,
            outputHeight: p.outputHeight,
            outputSeconds: p.outputSeconds,
            outputWidth: p.outputWidth,
            sourceFolders: defaultFolders
        )

        // Override with the full multi-library normalization.
        self.sourceLibraries = expandedLibraries
        self.sourceLibraryOrder = rawOrder.isEmpty ? [defaultKey] : rawOrder
        self.defaultSourceLibraryKey = defaultKey

        // Ensure sourceFolders matches the expanded default library.
        self.sourceFolders = expandedLibraries[defaultKey] ?? defaultFolders
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

extension Settings {
    /// Flatten all folders for the given set of library keys, respecting sourceLibraryOrder.
    func folders(forLibraries keys: Set<String>) -> [String] {
        var result: [String] = []
        for key in sourceLibraryOrder where keys.contains(key) {
            if let paths = sourceLibraries[key] {
                result.append(contentsOf: paths)
            }
        }
        return result
    }
}
