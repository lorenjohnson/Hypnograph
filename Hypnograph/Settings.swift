//
//  Settings.swift
//  Hypnograph
//

import Foundation
import HypnoCore
import AppKit
import CoreGraphics
import CoreMedia

// SourceLibraryInfo and MediaSourcesParam are now provided by HypnoCore

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
    var sources: MediaSourcesParam

    // Optional in JSON (but non-optional in code)
    var watchMode: Bool
    var snapshotsFolder: String

    /// Default clip length range (seconds) for newly generated clips
    var clipLengthMinSeconds: Double
    var clipLengthMaxSeconds: Double

    /// Max number of clips to retain in history (oldest dropped first)
    var historyLimit: Int

    /// Active source libraries (folder keys or Photos library keys)
    var activeLibraries: [String]

    /// Output resolution for disk rendering
    var outputResolution: OutputResolution

    /// Global source framing behavior (Fill vs Fit)
    var sourceFraming: SourceFraming

    /// Player configuration for the preview deck
    var playerConfig: PlayerConfiguration

    /// Which media types to include in sources: "photos", "videos", or both
    var sourceMediaTypes: Set<MediaType>

    /// Whether the effects list column is collapsed in the Effects Editor
    var effectsListCollapsed: Bool

    /// Feature flag for live display workflows (preview panel, external monitor, live mode)
    var liveModeEnabled: Bool

    // MARK: - Transition Settings

    /// Transition style for playback (shared by Preview and Live)
    var transitionStyle: TransitionRenderer.TransitionType

    /// Duration of transitions in seconds
    var transitionDuration: Double

    // MARK: - Randomization Settings (Generation Rules)

    /// When true, randomly applies a global effect chain when generating new clips
    var randomGlobalEffect: Bool

    /// Chance (0.0 - 1.0) of randomizing global effect on generation
    var randomGlobalEffectFrequency: Double

    /// When true, randomly applies per-layer effect chains when generating new clips
    var randomLayerEffect: Bool

    /// Chance (0.0 - 1.0) of randomizing layer effects on generation
    var randomLayerEffectFrequency: Double

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
        static let watchMode: Bool = false
        static let outputFolder = "~/Movies/Hypnograph/renders"
        static let snapshotsFolder = "~/Movies/Hypnograph/snapshots"
        static let clipLengthMinSeconds: Double = 5.0
        static let clipLengthMaxSeconds: Double = 20.0
        static let historyLimit: Int = 200
        static let sources = MediaSourcesParam.dictionary([
            "default": ["~/Movies/Hypnograph/sources"],
            "From Finder Helper": []
        ])
        static let activeLibraries: [String] = []
        static let aspectRatio: AspectRatio = .ratio16x9
        static let outputResolution: OutputResolution = .p1080
        static let playerResolution: OutputResolution = .p1080
        static let maxLayers = 1
        static let sourceFraming: SourceFraming = .fill
        static let sourceMediaTypes: Set<MediaType> = [.images, .videos]
        static let effectsListCollapsed: Bool = false
        static let liveModeEnabled: Bool = false
        // Transition defaults
        static let transitionStyle: TransitionRenderer.TransitionType = .crossfade
        static let transitionDuration: Double = 1.0
        // Randomization defaults
        static let randomGlobalEffect: Bool = true
        static let randomGlobalEffectFrequency: Double = 0.7
        static let randomLayerEffect: Bool = false
        static let randomLayerEffectFrequency: Double = 0.3
        // Audio defaults: nil UID = system default, volume = 1.0
        static let previewAudioDeviceUID: String? = nil
        static let previewVolume: Float = 0.8
        static let liveAudioDeviceUID: String? = nil
        static let liveVolume: Float = 1.0
    }

    /// Single source of truth for defaults (kept in sync with `Defaults`).
    static var defaultValue: Settings {
        Settings(
            outputFolder: Defaults.outputFolder,
            sources: Defaults.sources,
            watchMode: Defaults.watchMode,
            snapshotsFolder: Defaults.snapshotsFolder,
            clipLengthMinSeconds: Defaults.clipLengthMinSeconds,
            clipLengthMaxSeconds: Defaults.clipLengthMaxSeconds,
            historyLimit: Defaults.historyLimit,
            activeLibraries: Defaults.activeLibraries,
            outputResolution: Defaults.outputResolution,
            sourceFraming: Defaults.sourceFraming,
            sourceMediaTypes: Defaults.sourceMediaTypes,
            effectsListCollapsed: Defaults.effectsListCollapsed,
            liveModeEnabled: Defaults.liveModeEnabled,
            transitionStyle: Defaults.transitionStyle,
            transitionDuration: Defaults.transitionDuration,
            randomGlobalEffect: Defaults.randomGlobalEffect,
            randomGlobalEffectFrequency: Defaults.randomGlobalEffectFrequency,
            randomLayerEffect: Defaults.randomLayerEffect,
            randomLayerEffectFrequency: Defaults.randomLayerEffectFrequency,
            previewAudioDeviceUID: Defaults.previewAudioDeviceUID,
            previewVolume: Defaults.previewVolume,
            liveAudioDeviceUID: Defaults.liveAudioDeviceUID,
            liveVolume: Defaults.liveVolume,
            playerConfig: PlayerConfiguration(
                aspectRatio: Defaults.aspectRatio,
                playerResolution: Defaults.playerResolution,
                maxLayers: Defaults.maxLayers
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case outputFolder, sources
        case watchMode, snapshotsFolder
        case clipLengthMinSeconds, clipLengthMaxSeconds
        case historyLimit
        case activeLibraries
        case outputResolution, sourceFraming, sourceMediaTypes
        case effectsListCollapsed
        case liveModeEnabled
        case transitionStyle, transitionDuration
        case randomGlobalEffect, randomGlobalEffectFrequency
        case randomLayerEffect, randomLayerEffectFrequency
        case previewAudioDeviceUID, previewVolume
        case liveAudioDeviceUID, liveVolume
        case playerConfig
        // Legacy (pre-unify): montagePlayerConfig, sequencePlayerConfig
        case montagePlayerConfig, sequencePlayerConfig
        // Legacy: watchMode was previously persisted as `watch`
        case watch
    }

    init(
        outputFolder: String,
        sources: MediaSourcesParam,
        watchMode: Bool = Defaults.watchMode,
        snapshotsFolder: String = Defaults.snapshotsFolder,
        clipLengthMinSeconds: Double = Defaults.clipLengthMinSeconds,
        clipLengthMaxSeconds: Double = Defaults.clipLengthMaxSeconds,
        historyLimit: Int = Defaults.historyLimit,
        activeLibraries: [String] = Defaults.activeLibraries,
        outputResolution: OutputResolution = Defaults.outputResolution,
        sourceFraming: SourceFraming = Defaults.sourceFraming,
        sourceMediaTypes: Set<MediaType> = Defaults.sourceMediaTypes,
        effectsListCollapsed: Bool = Defaults.effectsListCollapsed,
        liveModeEnabled: Bool = Defaults.liveModeEnabled,
        transitionStyle: TransitionRenderer.TransitionType = Defaults.transitionStyle,
        transitionDuration: Double = Defaults.transitionDuration,
        randomGlobalEffect: Bool = Defaults.randomGlobalEffect,
        randomGlobalEffectFrequency: Double = Defaults.randomGlobalEffectFrequency,
        randomLayerEffect: Bool = Defaults.randomLayerEffect,
        randomLayerEffectFrequency: Double = Defaults.randomLayerEffectFrequency,
        previewAudioDeviceUID: String? = Defaults.previewAudioDeviceUID,
        previewVolume: Float = Defaults.previewVolume,
        liveAudioDeviceUID: String? = Defaults.liveAudioDeviceUID,
        liveVolume: Float = Defaults.liveVolume,
        playerConfig: PlayerConfiguration? = nil
    ) {
        self.outputFolder = outputFolder
        self.sources = sources
        self.watchMode = watchMode
        self.snapshotsFolder = snapshotsFolder
        self.clipLengthMinSeconds = clipLengthMinSeconds
        self.clipLengthMaxSeconds = clipLengthMaxSeconds
        self.historyLimit = historyLimit
        self.activeLibraries = activeLibraries
        self.outputResolution = outputResolution
        self.sourceFraming = sourceFraming
        self.sourceMediaTypes = sourceMediaTypes
        self.effectsListCollapsed = effectsListCollapsed
        self.liveModeEnabled = liveModeEnabled
        self.transitionStyle = transitionStyle
        self.transitionDuration = transitionDuration
        self.randomGlobalEffect = randomGlobalEffect
        self.randomGlobalEffectFrequency = randomGlobalEffectFrequency
        self.randomLayerEffect = randomLayerEffect
        self.randomLayerEffectFrequency = randomLayerEffectFrequency
        self.previewAudioDeviceUID = previewAudioDeviceUID
        self.previewVolume = previewVolume
        self.liveAudioDeviceUID = liveAudioDeviceUID
        self.liveVolume = liveVolume

        // Use provided config or create defaults
        self.playerConfig = playerConfig ?? PlayerConfiguration(
            aspectRatio: Defaults.aspectRatio,
            playerResolution: Defaults.playerResolution,
            maxLayers: Defaults.maxLayers
        )
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        outputFolder = try c.decodeIfPresent(String.self, forKey: .outputFolder)
            ?? Defaults.outputFolder
        sources = try c.decodeIfPresent(MediaSourcesParam.self, forKey: .sources)
            ?? Defaults.sources
        watchMode = try c.decodeIfPresent(Bool.self, forKey: .watchMode)
            ?? c.decodeIfPresent(Bool.self, forKey: .watch)
            ?? Defaults.watchMode
        snapshotsFolder = try c.decodeIfPresent(String.self, forKey: .snapshotsFolder)
            ?? Defaults.snapshotsFolder
        clipLengthMinSeconds = try c.decodeIfPresent(Double.self, forKey: .clipLengthMinSeconds)
            ?? Defaults.clipLengthMinSeconds
        clipLengthMaxSeconds = try c.decodeIfPresent(Double.self, forKey: .clipLengthMaxSeconds)
            ?? Defaults.clipLengthMaxSeconds
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit)
            ?? Defaults.historyLimit
        activeLibraries = try c.decodeIfPresent([String].self, forKey: .activeLibraries)
            ?? Defaults.activeLibraries
        outputResolution = try c.decodeIfPresent(OutputResolution.self, forKey: .outputResolution)
            ?? Defaults.outputResolution
        sourceFraming = try c.decodeIfPresent(SourceFraming.self, forKey: .sourceFraming)
            ?? Defaults.sourceFraming
        if let types = try c.decodeIfPresent([MediaType].self, forKey: .sourceMediaTypes) {
            sourceMediaTypes = Set(types)
        } else {
            sourceMediaTypes = Defaults.sourceMediaTypes
        }
        effectsListCollapsed = try c.decodeIfPresent(Bool.self, forKey: .effectsListCollapsed)
            ?? Defaults.effectsListCollapsed
        liveModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .liveModeEnabled)
            ?? Defaults.liveModeEnabled
        transitionStyle = try c.decodeIfPresent(TransitionRenderer.TransitionType.self, forKey: .transitionStyle)
            ?? Defaults.transitionStyle
        transitionDuration = try c.decodeIfPresent(Double.self, forKey: .transitionDuration)
            ?? Defaults.transitionDuration
        randomGlobalEffect = try c.decodeIfPresent(Bool.self, forKey: .randomGlobalEffect)
            ?? Defaults.randomGlobalEffect
        randomGlobalEffectFrequency = try c.decodeIfPresent(Double.self, forKey: .randomGlobalEffectFrequency)
            ?? Defaults.randomGlobalEffectFrequency
        randomLayerEffect = try c.decodeIfPresent(Bool.self, forKey: .randomLayerEffect)
            ?? Defaults.randomLayerEffect
        randomLayerEffectFrequency = try c.decodeIfPresent(Double.self, forKey: .randomLayerEffectFrequency)
            ?? Defaults.randomLayerEffectFrequency
        previewAudioDeviceUID = try c.decodeIfPresent(String.self, forKey: .previewAudioDeviceUID)
            ?? Defaults.previewAudioDeviceUID
        previewVolume = try c.decodeIfPresent(Float.self, forKey: .previewVolume)
            ?? Defaults.previewVolume
        liveAudioDeviceUID = try c.decodeIfPresent(String.self, forKey: .liveAudioDeviceUID)
            ?? Defaults.liveAudioDeviceUID
        liveVolume = try c.decodeIfPresent(Float.self, forKey: .liveVolume)
            ?? Defaults.liveVolume

        // Load player config (or create defaults)
        playerConfig = try c.decodeIfPresent(PlayerConfiguration.self, forKey: .playerConfig)
            ?? c.decodeIfPresent(PlayerConfiguration.self, forKey: .montagePlayerConfig)
            ?? c.decodeIfPresent(PlayerConfiguration.self, forKey: .sequencePlayerConfig)
            ?? PlayerConfiguration(
                aspectRatio: Defaults.aspectRatio,
                playerResolution: Defaults.playerResolution,
                maxLayers: Defaults.maxLayers
            )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(outputFolder, forKey: .outputFolder)
        try c.encode(sources, forKey: .sources)
        try c.encode(watchMode, forKey: .watchMode)
        try c.encode(snapshotsFolder, forKey: .snapshotsFolder)
        try c.encode(clipLengthMinSeconds, forKey: .clipLengthMinSeconds)
        try c.encode(clipLengthMaxSeconds, forKey: .clipLengthMaxSeconds)
        try c.encode(historyLimit, forKey: .historyLimit)
        try c.encode(activeLibraries, forKey: .activeLibraries)
        try c.encode(outputResolution, forKey: .outputResolution)
        try c.encode(sourceFraming, forKey: .sourceFraming)
        try c.encode(Array(sourceMediaTypes), forKey: .sourceMediaTypes)
        try c.encode(effectsListCollapsed, forKey: .effectsListCollapsed)
        try c.encode(liveModeEnabled, forKey: .liveModeEnabled)
        try c.encode(transitionStyle, forKey: .transitionStyle)
        try c.encode(transitionDuration, forKey: .transitionDuration)
        try c.encode(randomGlobalEffect, forKey: .randomGlobalEffect)
        try c.encode(randomGlobalEffectFrequency, forKey: .randomGlobalEffectFrequency)
        try c.encode(randomLayerEffect, forKey: .randomLayerEffect)
        try c.encode(randomLayerEffectFrequency, forKey: .randomLayerEffectFrequency)
        try c.encodeIfPresent(previewAudioDeviceUID, forKey: .previewAudioDeviceUID)
        try c.encode(previewVolume, forKey: .previewVolume)
        try c.encodeIfPresent(liveAudioDeviceUID, forKey: .liveAudioDeviceUID)
        try c.encode(liveVolume, forKey: .liveVolume)
        try c.encode(playerConfig, forKey: .playerConfig)
    }

    // MARK: - Derived values

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
