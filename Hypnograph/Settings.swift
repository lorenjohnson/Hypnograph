//
//  Settings.swift
//  Hypnograph
//

import Foundation
import HypnoCore
import AppKit
import CoreGraphics
import CoreMedia

// SourceLibraryInfo and SourcesParam are now provided by HypnoCore

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

struct Settings: Codable, MediaLibrarySettings {
    // Required in JSON
    var outputFolder: String
    var sources: SourcesParam

    // Optional in JSON (but non-optional in code)
    var watch: Bool
    var snapshotsFolder: String
    var activeLibrariesPerMode: [String: [String]]

    /// Output resolution for disk rendering
    var outputResolution: OutputResolution

    /// Per-player configurations (montage and sequence)
    var montagePlayerConfig: PlayerConfiguration
    var sequencePlayerConfig: PlayerConfiguration

    /// Legacy global defaults (deprecated - use montagePlayerConfig/sequencePlayerConfig instead)
    /// These are kept for backward compatibility with old settings files
    var maxSourcesForNew: Int?
    var outputSeconds: Int?
    var aspectRatio: AspectRatio?
    var playerResolution: OutputResolution?

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
        case watch, snapshotsFolder
        case activeLibrariesPerMode
        case outputResolution, sourceMediaTypes
        case effectsListCollapsed
        case previewAudioDeviceUID, previewVolume
        case liveAudioDeviceUID, liveVolume
        case montagePlayerConfig, sequencePlayerConfig
        // Legacy keys for backward compatibility
        case maxSourcesForNew, outputSeconds, aspectRatio, playerResolution
    }

    init(
        outputFolder: String,
        sources: SourcesParam,
        watch: Bool = Defaults.watch,
        snapshotsFolder: String = Defaults.snapshotsFolder,
        activeLibrariesPerMode: [String: [String]] = Defaults.activeLibrariesPerMode,
        outputResolution: OutputResolution = Defaults.outputResolution,
        sourceMediaTypes: Set<SourceMediaType> = Defaults.sourceMediaTypes,
        effectsListCollapsed: Bool = Defaults.effectsListCollapsed,
        previewAudioDeviceUID: String? = Defaults.previewAudioDeviceUID,
        previewVolume: Float = Defaults.previewVolume,
        liveAudioDeviceUID: String? = Defaults.liveAudioDeviceUID,
        liveVolume: Float = Defaults.liveVolume,
        montagePlayerConfig: PlayerConfiguration? = nil,
        sequencePlayerConfig: PlayerConfiguration? = nil
    ) {
        self.outputFolder = outputFolder
        self.sources = sources
        self.watch = watch
        self.snapshotsFolder = snapshotsFolder
        self.activeLibrariesPerMode = activeLibrariesPerMode
        self.outputResolution = outputResolution
        self.sourceMediaTypes = sourceMediaTypes
        self.effectsListCollapsed = effectsListCollapsed
        self.previewAudioDeviceUID = previewAudioDeviceUID
        self.previewVolume = previewVolume
        self.liveAudioDeviceUID = liveAudioDeviceUID
        self.liveVolume = liveVolume

        // Use provided configs or create defaults
        self.montagePlayerConfig = montagePlayerConfig ?? PlayerConfiguration(
            aspectRatio: Defaults.aspectRatio,
            playerResolution: Defaults.playerResolution,
            maxSourcesForNew: Defaults.maxSourcesForNew,
            targetDuration: CMTime(seconds: Double(Defaults.outputSeconds), preferredTimescale: 600)
        )
        self.sequencePlayerConfig = sequencePlayerConfig ?? PlayerConfiguration(
            aspectRatio: Defaults.aspectRatio,
            playerResolution: Defaults.playerResolution,
            maxSourcesForNew: Defaults.maxSourcesForNew,
            targetDuration: CMTime(seconds: Double(Defaults.outputSeconds), preferredTimescale: 600)
        )

        // Legacy properties (for backward compatibility)
        self.maxSourcesForNew = nil
        self.outputSeconds = nil
        self.aspectRatio = nil
        self.playerResolution = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        outputFolder = try c.decodeIfPresent(String.self, forKey: .outputFolder)
            ?? Defaults.outputFolder
        sources = try c.decodeIfPresent(SourcesParam.self, forKey: .sources)
            ?? Defaults.sources
        watch = try c.decodeIfPresent(Bool.self, forKey: .watch)
            ?? Defaults.watch
        snapshotsFolder = try c.decodeIfPresent(String.self, forKey: .snapshotsFolder)
            ?? Defaults.snapshotsFolder
        activeLibrariesPerMode = try c.decodeIfPresent([String: [String]].self, forKey: .activeLibrariesPerMode)
            ?? Defaults.activeLibrariesPerMode
        outputResolution = try c.decodeIfPresent(OutputResolution.self, forKey: .outputResolution)
            ?? Defaults.outputResolution
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

        // Try to load new format (montagePlayerConfig/sequencePlayerConfig)
        if let montage = try c.decodeIfPresent(PlayerConfiguration.self, forKey: .montagePlayerConfig),
           let sequence = try c.decodeIfPresent(PlayerConfiguration.self, forKey: .sequencePlayerConfig) {
            montagePlayerConfig = montage
            sequencePlayerConfig = sequence
            // Legacy fields stay nil
            maxSourcesForNew = nil
            outputSeconds = nil
            aspectRatio = nil
            playerResolution = nil
        } else {
            // Load legacy format and migrate to new format
            let legacyMaxSources = try c.decodeIfPresent(Int.self, forKey: .maxSourcesForNew)
                ?? Defaults.maxSourcesForNew
            let legacyOutputSeconds = try c.decodeIfPresent(Int.self, forKey: .outputSeconds)
                ?? Defaults.outputSeconds
            let legacyAspectRatio = try c.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio)
                ?? Defaults.aspectRatio
            let legacyPlayerResolution = try c.decodeIfPresent(OutputResolution.self, forKey: .playerResolution)
                ?? Defaults.playerResolution

            // Create player configs from legacy values
            let defaultConfig = PlayerConfiguration(
                aspectRatio: legacyAspectRatio,
                playerResolution: legacyPlayerResolution,
                maxSourcesForNew: legacyMaxSources,
                targetDuration: CMTime(seconds: Double(legacyOutputSeconds), preferredTimescale: 600)
            )
            montagePlayerConfig = defaultConfig
            sequencePlayerConfig = defaultConfig

            // Store legacy values for potential re-encoding
            maxSourcesForNew = legacyMaxSources
            outputSeconds = legacyOutputSeconds
            aspectRatio = legacyAspectRatio
            playerResolution = legacyPlayerResolution
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(outputFolder, forKey: .outputFolder)
        try c.encode(sources, forKey: .sources)
        try c.encode(watch, forKey: .watch)
        try c.encode(snapshotsFolder, forKey: .snapshotsFolder)
        try c.encode(activeLibrariesPerMode, forKey: .activeLibrariesPerMode)
        try c.encode(outputResolution, forKey: .outputResolution)
        try c.encode(Array(sourceMediaTypes), forKey: .sourceMediaTypes)
        try c.encode(effectsListCollapsed, forKey: .effectsListCollapsed)
        try c.encodeIfPresent(previewAudioDeviceUID, forKey: .previewAudioDeviceUID)
        try c.encode(previewVolume, forKey: .previewVolume)
        try c.encodeIfPresent(liveAudioDeviceUID, forKey: .liveAudioDeviceUID)
        try c.encode(liveVolume, forKey: .liveVolume)

        // Encode new format
        try c.encode(montagePlayerConfig, forKey: .montagePlayerConfig)
        try c.encode(sequencePlayerConfig, forKey: .sequencePlayerConfig)
    }

    // MARK: - Derived values

    var outputDuration: CMTime {
        CMTime(seconds: Double(outputSeconds ?? Defaults.outputSeconds), preferredTimescale: 600)
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
