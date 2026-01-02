//
//  Settings.swift
//  Hypnograph
//

import Foundation
import AppKit
import CoreGraphics
import CoreMedia

// MARK: - Source Library Info (for menu display)

/// Information about a source library for menu display
struct SourceLibraryInfo: Identifiable {
    enum LibraryType {
        case folders
        case applePhotos
    }

    let id: String           // Unique key for this library
    let name: String         // Display name
    let type: LibraryType    // Folder-based or Apple Photos
    var assetCount: Int      // Number of assets (0 = hidden from menu)

    /// Display name with asset count, e.g. "Archive (587)"
    var displayName: String {
        "\(name) (\(assetCount))"
    }
}

// MARK: - Polymorphic sources

enum SourcesParam: Codable {
    case array([String])
    case dictionary([String: [String]])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if let dictArray = try? c.decode([String: [String]].self) {
            self = .dictionary(dictArray)
            return
        }

        if let dictString = try? c.decode([String: String].self) {
            self = .dictionary(dictString.mapValues { [$0] })
            return
        }

        if let arr = try? c.decode([String].self) {
            self = .array(arr)
            return
        }

        throw DecodingError.typeMismatch(
            SourcesParam.self,
            .init(codingPath: decoder.codingPath,
                  debugDescription: "Expected [String], [String: String], or [String: [String]]")
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .array(let arr):
            try c.encode(arr)
        case .dictionary(let dict):
            try c.encode(dict)
        }
    }

    var libraries: [String: [String]] {
        switch self {
        case .array(let arr):
            return ["default": arr]
        case .dictionary(let dict):
            return dict
        }
    }

    var libraryOrder: [String] {
        switch self {
        case .array:
            return ["default"]
        case .dictionary(let dict):
            return Array(dict.keys)
        }
    }

    var defaultKey: String {
        let libs = libraries
        if libs.keys.contains("default") { return "default" }
        if let k = libs.keys.first(where: { $0.lowercased() == "default" }) { return k }
        return libraryOrder.first ?? "default"
    }
}

// MARK: - Output Resolution

/// Standard video resolutions (720p, 1080p, 4K)
/// The raw value is the vertical resolution for landscape video.
enum OutputResolution: Int, Codable, CaseIterable {
    case p720 = 720
    case p1080 = 1080
    case p4K = 2160

    /// Display name for menus
    var displayName: String {
        switch self {
        case .p720: return "720p"
        case .p1080: return "1080p"
        case .p4K: return "4K"
        }
    }

    /// The constraining dimension for renderSize()
    /// For landscape: this is the height (e.g., 1080 for 1080p → 1920×1080)
    /// For portrait: this is the width
    var maxDimension: Int { rawValue }
}

// MARK: - Settings

struct Settings: Codable {
    // Required in JSON
    var outputFolder: String
    var sources: SourcesParam

    // Optional in JSON (but non-optional in code)
    var watch: Bool
    var maxSourcesForNew: Int
    var outputSeconds: Int
    var snapshotsFolder: String
    var activeLibrariesPerMode: [String: [String]]

    /// Aspect ratio for composition (e.g., 16:9, 4:3, 2.35:1)
    var aspectRatio: AspectRatio

    /// Output resolution for disk rendering
    var outputResolution: OutputResolution

    /// Player resolution for preview (per-player setting, this is the global default)
    var playerResolution: OutputResolution

    /// Which media types to include in sources: "photos", "videos", or both
    var sourceMediaTypes: Set<SourceMediaType>

    /// Whether the effects list column is collapsed in the Effects Editor
    var effectsListCollapsed: Bool

    // MARK: - Audio Settings

    /// Preview audio device UID (nil = None/muted)
    var previewAudioDeviceUID: String?

    /// Preview audio volume (0.0 to 1.0)
    var previewVolume: Float

    /// Live player audio device UID (nil = None/muted)
    var liveAudioDeviceUID: String?

    /// Live player audio volume (0.0 to 1.0)
    var liveVolume: Float

    // Single source of truth for defaults
    private enum Defaults {
        static let watch: Bool = true
        static let maxSourcesForNew = 5
        static let outputFolder = "~/Movies/Hypnograph/renders"
        static let snapshotsFolder = "~/Movies/Hypnograph/snapshots"
        static let outputSeconds = 60
        static let sources = SourcesParam.array([
            "~/Movies/Hypnograph/sources"
        ])
        static let activeLibrariesPerMode: [String: [String]] = [:]
        static let aspectRatio: AspectRatio = .ratio16x9
        static let outputResolution: OutputResolution = .p1080
        static let playerResolution: OutputResolution = .p1080
        static let sourceMediaTypes: Set<SourceMediaType> = [.images, .videos]
        static let effectsListCollapsed: Bool = false
        // Audio defaults: nil UID = system default, volume = 1.0
        static let previewAudioDeviceUID: String? = nil
        static let previewVolume: Float = 1.0
        static let liveAudioDeviceUID: String? = nil
        static let liveVolume: Float = 1.0
    }

    private enum CodingKeys: String, CodingKey {
        case outputFolder, sources
        case watch, maxSourcesForNew, outputSeconds, snapshotsFolder
        case activeLibrariesPerMode
        case aspectRatio, outputResolution, playerResolution, sourceMediaTypes
        case effectsListCollapsed
        case previewAudioDeviceUID, previewVolume
        case liveAudioDeviceUID, liveVolume
    }

    init(
        outputFolder: String,
        sources: SourcesParam,
        watch: Bool = Defaults.watch,
        maxSourcesForNew: Int = Defaults.maxSourcesForNew,
        outputSeconds: Int = Defaults.outputSeconds,
        snapshotsFolder: String = Defaults.snapshotsFolder,
        activeLibrariesPerMode: [String: [String]] = Defaults.activeLibrariesPerMode,
        aspectRatio: AspectRatio = Defaults.aspectRatio,
        outputResolution: OutputResolution = Defaults.outputResolution,
        playerResolution: OutputResolution = Defaults.playerResolution,
        sourceMediaTypes: Set<SourceMediaType> = Defaults.sourceMediaTypes,
        effectsListCollapsed: Bool = Defaults.effectsListCollapsed,
        previewAudioDeviceUID: String? = Defaults.previewAudioDeviceUID,
        previewVolume: Float = Defaults.previewVolume,
        liveAudioDeviceUID: String? = Defaults.liveAudioDeviceUID,
        liveVolume: Float = Defaults.liveVolume
    ) {
        self.outputFolder = outputFolder
        self.sources = sources
        self.watch = watch
        self.maxSourcesForNew = maxSourcesForNew
        self.outputSeconds = outputSeconds
        self.snapshotsFolder = snapshotsFolder
        self.activeLibrariesPerMode = activeLibrariesPerMode
        self.aspectRatio = aspectRatio
        self.outputResolution = outputResolution
        self.playerResolution = playerResolution
        self.sourceMediaTypes = sourceMediaTypes
        self.effectsListCollapsed = effectsListCollapsed
        self.previewAudioDeviceUID = previewAudioDeviceUID
        self.previewVolume = previewVolume
        self.liveAudioDeviceUID = liveAudioDeviceUID
        self.liveVolume = liveVolume
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        outputFolder   = try c.decodeIfPresent(String.self, forKey: .outputFolder)
            ?? Defaults.outputFolder
        sources  = try c.decodeIfPresent(SourcesParam.self, forKey: .sources)
            ?? Defaults.sources
        watch = try c.decodeIfPresent(Bool.self, forKey: .watch)
            ?? Defaults.watch
        maxSourcesForNew = try c.decodeIfPresent(Int.self, forKey: .maxSourcesForNew)
            ?? Defaults.maxSourcesForNew
        outputSeconds = try c.decodeIfPresent(Int.self, forKey: .outputSeconds)
            ?? Defaults.outputSeconds
        snapshotsFolder = try c.decodeIfPresent(String.self, forKey: .snapshotsFolder)
            ?? Defaults.snapshotsFolder
        activeLibrariesPerMode = try c.decodeIfPresent([String: [String]].self, forKey: .activeLibrariesPerMode)
            ?? Defaults.activeLibrariesPerMode
        aspectRatio = try c.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio)
            ?? Defaults.aspectRatio
        outputResolution = try c.decodeIfPresent(OutputResolution.self, forKey: .outputResolution)
            ?? Defaults.outputResolution
        playerResolution = try c.decodeIfPresent(OutputResolution.self, forKey: .playerResolution)
            ?? Defaults.playerResolution
        if let types = try c.decodeIfPresent([SourceMediaType].self, forKey: .sourceMediaTypes) {
            sourceMediaTypes = Set(types)
        } else {
            sourceMediaTypes = Defaults.sourceMediaTypes
        }
        effectsListCollapsed = try c.decodeIfPresent(Bool.self, forKey: .effectsListCollapsed)
            ?? Defaults.effectsListCollapsed
        previewAudioDeviceUID = try c.decodeIfPresent(String.self, forKey: .previewAudioDeviceUID)
            ?? Defaults.previewAudioDeviceUID
        previewVolume = try c.decodeIfPresent(Float.self, forKey: .previewVolume)
            ?? Defaults.previewVolume
        liveAudioDeviceUID = try c.decodeIfPresent(String.self, forKey: .liveAudioDeviceUID)
            ?? Defaults.liveAudioDeviceUID
        liveVolume = try c.decodeIfPresent(Float.self, forKey: .liveVolume)
            ?? Defaults.liveVolume
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(outputFolder, forKey: .outputFolder)
        try c.encode(sources, forKey: .sources)
        try c.encode(watch, forKey: .watch)
        try c.encode(maxSourcesForNew, forKey: .maxSourcesForNew)
        try c.encode(outputSeconds, forKey: .outputSeconds)
        try c.encode(snapshotsFolder, forKey: .snapshotsFolder)
        try c.encode(activeLibrariesPerMode, forKey: .activeLibrariesPerMode)
        try c.encode(aspectRatio, forKey: .aspectRatio)
        try c.encode(outputResolution, forKey: .outputResolution)
        try c.encode(playerResolution, forKey: .playerResolution)
        try c.encode(Array(sourceMediaTypes), forKey: .sourceMediaTypes)
        try c.encode(effectsListCollapsed, forKey: .effectsListCollapsed)
        try c.encodeIfPresent(previewAudioDeviceUID, forKey: .previewAudioDeviceUID)
        try c.encode(previewVolume, forKey: .previewVolume)
        try c.encodeIfPresent(liveAudioDeviceUID, forKey: .liveAudioDeviceUID)
        try c.encode(liveVolume, forKey: .liveVolume)
    }

    // MARK: - Derived values

    var outputDuration: CMTime {
        CMTime(seconds: Double(outputSeconds), preferredTimescale: 600)
    }

    var outputURL: URL {
        URL(
            fileURLWithPath: (outputFolder as NSString).expandingTildeInPath,
            isDirectory: true
        )
    }

    var snapshotsURL: URL {
        URL(
            fileURLWithPath: (snapshotsFolder as NSString).expandingTildeInPath,
            isDirectory: true
        )
    }

    var sourceLibraries: [String: [String]] {
        sources.libraries.mapValues { folders in
            folders.map { ($0 as NSString).expandingTildeInPath }
        }
    }

    var sourceLibraryOrder: [String] {
        let order = sources.libraryOrder
        return order.isEmpty ? [defaultSourceLibraryKey] : order
    }

    var defaultSourceLibraryKey: String {
        sources.defaultKey
    }

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

// MARK: - Loader

enum SettingsLoader {
    static func load(from url: URL) throws -> Settings {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Settings.self, from: data)
    }
}


