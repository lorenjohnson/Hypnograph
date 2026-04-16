//
//  StudioSettings.swift
//  Hypnograph
//

import Foundation
import HypnoCore
import AppKit
import CoreGraphics
import CoreMedia

// SourceLibraryInfo and MediaSourcesParam are now provided by HypnoCore

enum PlayerLoopMode: String, Codable, CaseIterable {
    case off
    case composition
    case sequence

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = PlayerLoopMode(rawValue: rawValue) ?? .off
    }
}

enum PlayerDockMode: String, Codable, CaseIterable {
    case sequence
    case composition
}

enum PropertiesPanelScope: String, Codable, CaseIterable {
    case sequence
    case composition
    case layer
}

enum NewCompositionsPanelTab: String, Codable, CaseIterable {
    case sources
    case generationParameters
}

enum RenderVideoSaveDestination: String, Codable, CaseIterable {
    case diskAndPhotosIfAvailable
    case photosIfAvailableOtherwiseDisk
    case diskOnly
}

// MARK: - StudioSettings

struct StudioSettings: Codable, MediaLibrarySettings {
    // Required in JSON
    var outputFolder: String
    var sources: MediaSourcesParam

    // Optional in JSON (but non-optional in code)
    var loopMode: PlayerLoopMode
    var generateAtEnd: Bool
    var snapshotsFolder: String
    var keyboardAccessibilityOverridesEnabled: Bool
    var effectsComposerEnabled: Bool
    var autoHidePanelsEnabled: Bool
    var panelOpacity: Double
    var dockMode: PlayerDockMode
    var propertiesPanelScope: PropertiesPanelScope
    var newCompositionsPanelTab: NewCompositionsPanelTab

    /// Default composition length range (seconds) for newly generated compositions
    var compositionLengthMinSeconds: Double
    var compositionLengthMaxSeconds: Double

    /// Default play-rate range for newly generated compositions (1.0 = 100%)
    var compositionPlayRateMin: Double
    var compositionPlayRateMax: Double

    /// Max number of compositions to retain in history (oldest dropped first)
    var historyLimit: Int

    /// Active source libraries (folder keys or Photos library keys)
    var activeLibraries: [String]

    /// Where rendered video outputs should be persisted after export succeeds.
    var renderVideoSaveDestination: RenderVideoSaveDestination

    /// Max number of simultaneously generated layers in new compositions.
    var maxLayers: Int

    /// Which media types to include in sources: "photos", "videos", or both
    var sourceMediaTypes: Set<MediaType>

    /// Feature flag for live display workflows (live panel, external monitor, live mode)
    var liveModeEnabled: Bool

    // MARK: - Randomization StudioSettings (Generation Rules)

    /// When true, randomly applies a composition effect chain when generating new compositions
    var randomGlobalEffect: Bool

    /// Chance (0.0 - 1.0) of randomizing composition effect chain on generation
    var randomGlobalEffectFrequency: Double

    /// When true, randomly applies per-layer effect chains when generating new compositions
    var randomLayerEffect: Bool

    /// Chance (0.0 - 1.0) of randomizing layer effects on generation
    var randomLayerEffectFrequency: Double

    // MARK: - Audio StudioSettings

    /// Primary in-app audio device UID (nil = None/muted)
    var audioDeviceUID: String?

    /// Primary in-app audio volume (0.0 to 1.0)
    var volume: Float

    /// Live player audio device UID (nil = None/muted)
    var liveAudioDeviceUID: String?

    /// Live player audio volume (0.0 to 1.0)
    var liveVolume: Float

    // Single source of truth for defaults
    private enum Defaults {
        static let loopMode: PlayerLoopMode = .off
        static let generateAtEnd: Bool = true
        static let outputFolder = "~/Movies/Hypnograph/renders"
        static let snapshotsFolder = "~/Movies/Hypnograph/snapshots"
        static let keyboardAccessibilityOverridesEnabled: Bool = true
        static let effectsComposerEnabled: Bool = true
        static let autoHidePanelsEnabled: Bool = false
        static let panelOpacity: Double = 0.72
        static let dockMode: PlayerDockMode = .composition
        static let propertiesPanelScope: PropertiesPanelScope = .composition
        static let newCompositionsPanelTab: NewCompositionsPanelTab = .sources
        static let compositionLengthMinSeconds: Double = 5.0
        static let compositionLengthMaxSeconds: Double = 20.0
        static let compositionPlayRateMin: Double = 1.0
        static let compositionPlayRateMax: Double = 1.0
        static let historyLimit: Int = 200
        static let sources = MediaSourcesParam.dictionary([
            "default": ["~/Movies/Hypnograph/sources"],
            "From Finder Helper": []
        ])
        static let activeLibraries: [String] = []
        static let renderVideoSaveDestination: RenderVideoSaveDestination = .diskAndPhotosIfAvailable
        static let maxLayers = PlayerConfiguration.defaultMaxLayers
        static let sourceMediaTypes: Set<MediaType> = [.videos]
        static let liveModeEnabled: Bool = false
        // Randomization defaults
        static let randomGlobalEffect: Bool = true
        static let randomGlobalEffectFrequency: Double = 0.7
        static let randomLayerEffect: Bool = false
        static let randomLayerEffectFrequency: Double = 0.3
        // Audio defaults: nil UID = system default, volume = 1.0
        static let audioDeviceUID: String? = nil
        static let volume: Float = 0.8
        static let liveAudioDeviceUID: String? = nil
        static let liveVolume: Float = 1.0
    }

    /// Single source of truth for defaults (kept in sync with `Defaults`).
    static var defaultValue: StudioSettings {
        StudioSettings(
            outputFolder: Defaults.outputFolder,
            sources: Defaults.sources,
            loopMode: Defaults.loopMode,
            generateAtEnd: Defaults.generateAtEnd,
            snapshotsFolder: Defaults.snapshotsFolder,
            keyboardAccessibilityOverridesEnabled: Defaults.keyboardAccessibilityOverridesEnabled,
            effectsComposerEnabled: Defaults.effectsComposerEnabled,
            autoHidePanelsEnabled: Defaults.autoHidePanelsEnabled,
            panelOpacity: Defaults.panelOpacity,
            dockMode: Defaults.dockMode,
            propertiesPanelScope: Defaults.propertiesPanelScope,
            newCompositionsPanelTab: Defaults.newCompositionsPanelTab,
            compositionLengthMinSeconds: Defaults.compositionLengthMinSeconds,
            compositionLengthMaxSeconds: Defaults.compositionLengthMaxSeconds,
            compositionPlayRateMin: Defaults.compositionPlayRateMin,
            compositionPlayRateMax: Defaults.compositionPlayRateMax,
            historyLimit: Defaults.historyLimit,
            activeLibraries: Defaults.activeLibraries,
            renderVideoSaveDestination: Defaults.renderVideoSaveDestination,
            maxLayers: Defaults.maxLayers,
            sourceMediaTypes: Defaults.sourceMediaTypes,
            liveModeEnabled: Defaults.liveModeEnabled,
            randomGlobalEffect: Defaults.randomGlobalEffect,
            randomGlobalEffectFrequency: Defaults.randomGlobalEffectFrequency,
            randomLayerEffect: Defaults.randomLayerEffect,
            randomLayerEffectFrequency: Defaults.randomLayerEffectFrequency,
            audioDeviceUID: Defaults.audioDeviceUID,
            volume: Defaults.volume,
            liveAudioDeviceUID: Defaults.liveAudioDeviceUID,
            liveVolume: Defaults.liveVolume
        )
    }

    private enum CodingKeys: String, CodingKey {
        case outputFolder, sources
        case playbackLoopMode
        case loopMode
        case generateAtEnd, snapshotsFolder
        case keyboardAccessibilityOverridesEnabled, effectsComposerEnabled, autoHidePanelsEnabled, panelOpacity
        case playbackDockMode
        case dockMode
        case propertiesPanelScope, newCompositionsPanelTab
        case compositionLengthMinSeconds, compositionLengthMaxSeconds
        case compositionPlayRateMin, compositionPlayRateMax
        case historyLimit
        case activeLibraries
        case renderVideoSaveDestination, sourceMediaTypes
        case maxLayers
        case liveModeEnabled
        case randomGlobalEffect, randomGlobalEffectFrequency
        case randomLayerEffect, randomLayerEffectFrequency
        case audioDeviceUID, volume
        case liveAudioDeviceUID, liveVolume
        // Backward-compatible decode keys from pre-composition terminology.
        case clipLengthMinSeconds, clipLengthMaxSeconds
        case clipPlayRateMin, clipPlayRateMax
    }

    init(
        outputFolder: String,
        sources: MediaSourcesParam,
        loopMode: PlayerLoopMode = Defaults.loopMode,
        generateAtEnd: Bool = Defaults.generateAtEnd,
        snapshotsFolder: String = Defaults.snapshotsFolder,
        keyboardAccessibilityOverridesEnabled: Bool = Defaults.keyboardAccessibilityOverridesEnabled,
        effectsComposerEnabled: Bool = Defaults.effectsComposerEnabled,
        autoHidePanelsEnabled: Bool = Defaults.autoHidePanelsEnabled,
        panelOpacity: Double = Defaults.panelOpacity,
        dockMode: PlayerDockMode = Defaults.dockMode,
        propertiesPanelScope: PropertiesPanelScope = Defaults.propertiesPanelScope,
        newCompositionsPanelTab: NewCompositionsPanelTab = Defaults.newCompositionsPanelTab,
        compositionLengthMinSeconds: Double = Defaults.compositionLengthMinSeconds,
        compositionLengthMaxSeconds: Double = Defaults.compositionLengthMaxSeconds,
        compositionPlayRateMin: Double = Defaults.compositionPlayRateMin,
        compositionPlayRateMax: Double = Defaults.compositionPlayRateMax,
        historyLimit: Int = Defaults.historyLimit,
        activeLibraries: [String] = Defaults.activeLibraries,
        renderVideoSaveDestination: RenderVideoSaveDestination = Defaults.renderVideoSaveDestination,
        maxLayers: Int = Defaults.maxLayers,
        sourceMediaTypes: Set<MediaType> = Defaults.sourceMediaTypes,
        liveModeEnabled: Bool = Defaults.liveModeEnabled,
        randomGlobalEffect: Bool = Defaults.randomGlobalEffect,
        randomGlobalEffectFrequency: Double = Defaults.randomGlobalEffectFrequency,
        randomLayerEffect: Bool = Defaults.randomLayerEffect,
        randomLayerEffectFrequency: Double = Defaults.randomLayerEffectFrequency,
        audioDeviceUID: String? = Defaults.audioDeviceUID,
        volume: Float = Defaults.volume,
        liveAudioDeviceUID: String? = Defaults.liveAudioDeviceUID,
        liveVolume: Float = Defaults.liveVolume
    ) {
        self.outputFolder = outputFolder
        self.sources = sources
        self.loopMode = loopMode
        self.generateAtEnd = generateAtEnd
        self.snapshotsFolder = snapshotsFolder
        self.keyboardAccessibilityOverridesEnabled = keyboardAccessibilityOverridesEnabled
        self.effectsComposerEnabled = effectsComposerEnabled
        self.autoHidePanelsEnabled = autoHidePanelsEnabled
        self.panelOpacity = panelOpacity
        self.dockMode = dockMode
        self.propertiesPanelScope = propertiesPanelScope
        self.newCompositionsPanelTab = newCompositionsPanelTab
        self.compositionLengthMinSeconds = compositionLengthMinSeconds
        self.compositionLengthMaxSeconds = compositionLengthMaxSeconds
        self.compositionPlayRateMin = compositionPlayRateMin
        self.compositionPlayRateMax = compositionPlayRateMax
        self.historyLimit = historyLimit
        self.activeLibraries = activeLibraries
        self.renderVideoSaveDestination = renderVideoSaveDestination
        self.maxLayers = max(1, maxLayers)
        self.sourceMediaTypes = sourceMediaTypes
        self.liveModeEnabled = liveModeEnabled
        self.randomGlobalEffect = randomGlobalEffect
        self.randomGlobalEffectFrequency = randomGlobalEffectFrequency
        self.randomLayerEffect = randomLayerEffect
        self.randomLayerEffectFrequency = randomLayerEffectFrequency
        self.audioDeviceUID = audioDeviceUID
        self.volume = volume
        self.liveAudioDeviceUID = liveAudioDeviceUID
        self.liveVolume = liveVolume
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        outputFolder = try c.decodeIfPresent(String.self, forKey: .outputFolder)
            ?? Defaults.outputFolder
        sources = try c.decodeIfPresent(MediaSourcesParam.self, forKey: .sources)
            ?? Defaults.sources
        loopMode = try c.decodeIfPresent(PlayerLoopMode.self, forKey: .loopMode)
            ?? c.decodeIfPresent(PlayerLoopMode.self, forKey: .playbackLoopMode)
            ?? Defaults.loopMode
        generateAtEnd = try c.decodeIfPresent(Bool.self, forKey: .generateAtEnd)
            ?? Defaults.generateAtEnd
        snapshotsFolder = try c.decodeIfPresent(String.self, forKey: .snapshotsFolder)
            ?? Defaults.snapshotsFolder
        keyboardAccessibilityOverridesEnabled = try c.decodeIfPresent(Bool.self, forKey: .keyboardAccessibilityOverridesEnabled)
            ?? Defaults.keyboardAccessibilityOverridesEnabled
        effectsComposerEnabled = try c.decodeIfPresent(Bool.self, forKey: .effectsComposerEnabled)
            ?? Defaults.effectsComposerEnabled
        autoHidePanelsEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoHidePanelsEnabled)
            ?? Defaults.autoHidePanelsEnabled
        panelOpacity = (try c.decodeIfPresent(Double.self, forKey: .panelOpacity)
            ?? Defaults.panelOpacity).clamped(to: 0.32...0.92)
        dockMode = try c.decodeIfPresent(PlayerDockMode.self, forKey: .dockMode)
            ?? c.decodeIfPresent(PlayerDockMode.self, forKey: .playbackDockMode)
            ?? Defaults.dockMode
        propertiesPanelScope = try c.decodeIfPresent(PropertiesPanelScope.self, forKey: .propertiesPanelScope)
            ?? Defaults.propertiesPanelScope
        newCompositionsPanelTab = try c.decodeIfPresent(NewCompositionsPanelTab.self, forKey: .newCompositionsPanelTab)
            ?? Defaults.newCompositionsPanelTab
        compositionLengthMinSeconds =
            try c.decodeIfPresent(Double.self, forKey: .compositionLengthMinSeconds)
            ?? c.decodeIfPresent(Double.self, forKey: .clipLengthMinSeconds)
            ?? Defaults.compositionLengthMinSeconds
        compositionLengthMaxSeconds =
            try c.decodeIfPresent(Double.self, forKey: .compositionLengthMaxSeconds)
            ?? c.decodeIfPresent(Double.self, forKey: .clipLengthMaxSeconds)
            ?? Defaults.compositionLengthMaxSeconds
        compositionPlayRateMin =
            try c.decodeIfPresent(Double.self, forKey: .compositionPlayRateMin)
            ?? c.decodeIfPresent(Double.self, forKey: .clipPlayRateMin)
            ?? Defaults.compositionPlayRateMin
        compositionPlayRateMax =
            try c.decodeIfPresent(Double.self, forKey: .compositionPlayRateMax)
            ?? c.decodeIfPresent(Double.self, forKey: .clipPlayRateMax)
            ?? Defaults.compositionPlayRateMax
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit)
            ?? Defaults.historyLimit
        activeLibraries = try c.decodeIfPresent([String].self, forKey: .activeLibraries)
            ?? Defaults.activeLibraries
        renderVideoSaveDestination = try c.decodeIfPresent(RenderVideoSaveDestination.self, forKey: .renderVideoSaveDestination)
            ?? Defaults.renderVideoSaveDestination
        maxLayers = max(1, try c.decodeIfPresent(Int.self, forKey: .maxLayers) ?? Defaults.maxLayers)
        if let types = try c.decodeIfPresent([MediaType].self, forKey: .sourceMediaTypes) {
            sourceMediaTypes = Set(types)
        } else {
            sourceMediaTypes = Defaults.sourceMediaTypes
        }
        liveModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .liveModeEnabled)
            ?? Defaults.liveModeEnabled
        randomGlobalEffect = try c.decodeIfPresent(Bool.self, forKey: .randomGlobalEffect)
            ?? Defaults.randomGlobalEffect
        randomGlobalEffectFrequency = try c.decodeIfPresent(Double.self, forKey: .randomGlobalEffectFrequency)
            ?? Defaults.randomGlobalEffectFrequency
        randomLayerEffect = try c.decodeIfPresent(Bool.self, forKey: .randomLayerEffect)
            ?? Defaults.randomLayerEffect
        randomLayerEffectFrequency = try c.decodeIfPresent(Double.self, forKey: .randomLayerEffectFrequency)
            ?? Defaults.randomLayerEffectFrequency
        audioDeviceUID = try c.decodeIfPresent(String.self, forKey: .audioDeviceUID)
            ?? Defaults.audioDeviceUID
        volume = try c.decodeIfPresent(Float.self, forKey: .volume)
            ?? Defaults.volume
        liveAudioDeviceUID = try c.decodeIfPresent(String.self, forKey: .liveAudioDeviceUID)
            ?? Defaults.liveAudioDeviceUID
        liveVolume = try c.decodeIfPresent(Float.self, forKey: .liveVolume)
            ?? Defaults.liveVolume
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(outputFolder, forKey: .outputFolder)
        try c.encode(sources, forKey: .sources)
        try c.encode(loopMode, forKey: .loopMode)
        try c.encode(generateAtEnd, forKey: .generateAtEnd)
        try c.encode(snapshotsFolder, forKey: .snapshotsFolder)
        try c.encode(keyboardAccessibilityOverridesEnabled, forKey: .keyboardAccessibilityOverridesEnabled)
        try c.encode(effectsComposerEnabled, forKey: .effectsComposerEnabled)
        try c.encode(autoHidePanelsEnabled, forKey: .autoHidePanelsEnabled)
        try c.encode(panelOpacity.clamped(to: 0.32...0.92), forKey: .panelOpacity)
        try c.encode(dockMode, forKey: .dockMode)
        try c.encode(propertiesPanelScope, forKey: .propertiesPanelScope)
        try c.encode(newCompositionsPanelTab, forKey: .newCompositionsPanelTab)
        try c.encode(compositionLengthMinSeconds, forKey: .compositionLengthMinSeconds)
        try c.encode(compositionLengthMaxSeconds, forKey: .compositionLengthMaxSeconds)
        try c.encode(compositionPlayRateMin, forKey: .compositionPlayRateMin)
        try c.encode(compositionPlayRateMax, forKey: .compositionPlayRateMax)
        try c.encode(historyLimit, forKey: .historyLimit)
        try c.encode(activeLibraries, forKey: .activeLibraries)
        try c.encode(renderVideoSaveDestination, forKey: .renderVideoSaveDestination)
        try c.encode(maxLayers, forKey: .maxLayers)
        try c.encode(Array(sourceMediaTypes), forKey: .sourceMediaTypes)
        try c.encode(liveModeEnabled, forKey: .liveModeEnabled)
        try c.encode(randomGlobalEffect, forKey: .randomGlobalEffect)
        try c.encode(randomGlobalEffectFrequency, forKey: .randomGlobalEffectFrequency)
        try c.encode(randomLayerEffect, forKey: .randomLayerEffect)
        try c.encode(randomLayerEffectFrequency, forKey: .randomLayerEffectFrequency)
        try c.encodeIfPresent(audioDeviceUID, forKey: .audioDeviceUID)
        try c.encode(volume, forKey: .volume)
        try c.encodeIfPresent(liveAudioDeviceUID, forKey: .liveAudioDeviceUID)
        try c.encode(liveVolume, forKey: .liveVolume)
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
        var filtered: [String: [String]] = [:]
        for (key, folders) in sources.libraries {
            let expanded = folders
                .map { ($0 as NSString).expandingTildeInPath }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !expanded.isEmpty else { continue }
            filtered[key] = expanded
        }
        return filtered
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
    static func load(from url: URL) throws -> StudioSettings {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StudioSettings.self, from: data)
    }
}
