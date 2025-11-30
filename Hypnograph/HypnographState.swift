//
//  HypnographState.swift
//  Hypnograph
//
//  Clean unified state: no “candidate” concept, no mirrors,
//  one authoritative list of HypnogramSource objects.
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import Combine
import CoreMedia
import CoreGraphics
import Photos

/// Manages the current in-progress hypnogram.
final class HypnographState: ObservableObject {

    // MARK: - Core configuration

    private(set) var settings: Settings

    // Per-module library state
    private var perModuleLibraryKeys: [ModuleType: Set<String>] = [:]
    private var perModuleUsingPhotos: [ModuleType: Bool] = [:]

    @Published private(set) var currentLibraryKey: String
    @Published private(set) var activeLibraryKeys: Set<String>

    /// Whether currently using Apple Photos album as source
    @Published private(set) var isUsingApplePhotosAlbum: Bool = false

    private(set) var library: MediaSourcesLibrary

    // MARK: - Module management

    @Published var currentModuleType: ModuleType = .dream {
        didSet {
            if oldValue != currentModuleType {
                // Save current module's Photos state before switching
                perModuleUsingPhotos[oldValue] = isUsingApplePhotosAlbum
                switchToModuleLibraries(currentModuleType)
            }
        }
    }

    // MARK: - Recipe (single source of truth)

    /// The current hypnogram recipe - single source of truth for sources, effects, etc.
    @Published var recipe: HypnogramRecipe

    /// Current selection index (auto-updated during sequence playback)
    @Published var currentSourceIndex: Int = 0

    /// Optional playhead offset for scrubbing, applies only on explicit user action.
    @Published var currentClipTimeOffset: CMTime?

    @Published var isHUDVisible: Bool = true

    /// Pause/play state for video playback (Dream mode)
    @Published var isPaused: Bool = false

    /// Incremented whenever effects change - used to trigger re-render when paused
    @Published var effectsChangeCounter: Int = 0

    /// Current aspect ratio for composition
    @Published var aspectRatio: AspectRatio

    /// Current output resolution (720p, 1080p, 4K)
    @Published var outputResolution: OutputResolution

    // Render hooks
    let renderHooks = RenderHookManager()
    var baseRenderParams = RenderParams()

    // Watch timer - generates new hypnograms at intervals when watch mode is enabled
    private var watchTimer: Timer?

    // Callback to trigger mode-specific new() when watch timer fires
    var onWatchTimerFired: (() -> Void)?

    // MARK: - Init

    init(settings: Settings) {
        self.settings = settings

        let defaultKey = settings.defaultSourceLibraryKey
        let initialKeys: Set<String> = [defaultKey]

        // Initialize per-module library state from settings or use defaults
        var loadedPerModuleKeys: [ModuleType: Set<String>] = [:]
        for module in [ModuleType.dream, ModuleType.divine] {
            if let savedKeys = settings.activeLibrariesPerMode[module.rawValue] {
                loadedPerModuleKeys[module] = Set(savedKeys)
            } else {
                loadedPerModuleKeys[module] = initialKeys
            }
        }
        self.perModuleLibraryKeys = loadedPerModuleKeys

        // Get active keys for the initial module (dream)
        let activeKeys = loadedPerModuleKeys[.dream] ?? initialKeys

        self.currentLibraryKey = defaultKey
        self.activeLibraryKeys = activeKeys
        self.library = MediaSourcesLibrary(
            sourceFolders: settings.folders(forLibraries: activeKeys),
            allowedMediaTypes: settings.sourceMediaTypes
        )

        self.recipe = HypnogramRecipe(
            sources: [],
            targetDuration: settings.outputDuration
        )
        self.currentSourceIndex = 0
        self.currentClipTimeOffset = nil

        // Initialize aspect ratio and resolution from settings
        self.aspectRatio = settings.aspectRatio
        self.outputResolution = settings.outputResolution

        // Always start with a full random hypnogram
        newRandomHypnogram()

        if settings.watch {
            scheduleWatchTimer()
        }

        // Set up callback to increment counter when effects or blend modes change
        renderHooks.onEffectChanged = { [weak self] in
            self?.effectsChangeCounter += 1
        }

        // Recipe provider - just returns the recipe directly
        renderHooks.recipeProvider = { [weak self] in
            self?.recipe
        }

        // Recipe effects setter
        renderHooks.effectsSetter = { [weak self] effects in
            self?.recipe.effects = effects
        }

        // Per-source effect setter
        renderHooks.sourceEffectSetter = { [weak self] sourceIndex, effects in
            guard let self = self,
                  sourceIndex >= 0,
                  sourceIndex < self.recipe.sources.count else { return }
            self.recipe.sources[sourceIndex].effects = effects
        }

        // Blend mode setter
        renderHooks.blendModeSetter = { [weak self] sourceIndex, mode in
            guard let self = self,
                  sourceIndex >= 0,
                  sourceIndex < self.recipe.sources.count else { return }
            self.recipe.sources[sourceIndex].blendMode = mode
        }
    }

    // MARK: - Convenience accessors (delegate to recipe)

    var sources: [HypnogramSource] {
        get { recipe.sources }
        set { recipe.sources = newValue }
    }

    var effects: [RenderHook] {
        get { recipe.effects }
        set { recipe.effects = newValue }
    }

    var activeSourceCount: Int { sources.count }

    var currentSource: HypnogramSource? {
        guard currentSourceIndex >= 0, currentSourceIndex < sources.count else { return nil }
        return sources[currentSourceIndex]
    }

    var currentClip: VideoClip? {
        currentSource?.clip
    }

    // MARK: - High-level API (for modes)

    /// Add a new source with a random clip.
    @discardableResult
    func addSource(length: Double? = nil, blendMode: String? = nil) -> HypnogramSource? {
        noteUserInteraction()
        guard let clip = library.randomClip(clipLength: length ?? settings.outputDuration.seconds)
        else { return nil }

        let newSource = HypnogramSource(clip: clip, blendMode: blendMode)

        sources.append(newSource)
        currentSourceIndex = sources.count - 1
        return newSource
    }

    /// Replace the clip for an existing source.
    @discardableResult
    func replaceClip(at index: Int, length: Double? = nil) -> VideoClip? {
        noteUserInteraction()
        guard index >= 0, index < sources.count else { return nil }
        let duration = length ?? settings.outputDuration.seconds

        guard let newClip = library.randomClip(clipLength: duration) else { return nil }

        var src = sources[index]
        src.clip = newClip
        sources[index] = src
        return newClip
    }

    func replaceClipForCurrentSource() {
        replaceClip(at: currentSourceIndex)
    }

    /// Adjust only the start time of the clip for a source.
    func adjustStartTime(at index: Int, to newStart: CMTime) {
        guard index >= 0, index < sources.count else { return }
        var src = sources[index]
        let clip = src.clip

        let fileDuration = clip.file.duration
        let start = min(newStart.seconds, fileDuration.seconds)
        let remaining = max(0.0, fileDuration.seconds - start)
        guard remaining > 0 else { return }

        let newDuration = min(clip.duration.seconds, remaining)

        src.clip = VideoClip(
            file: clip.file,
            startTime: CMTime(seconds: start, preferredTimescale: clip.startTime.timescale),
            duration: CMTime(seconds: newDuration, preferredTimescale: clip.duration.timescale)
        )
        sources[index] = src
    }

    func selectSource(_ index: Int) {
        noteUserInteraction()
        guard !sources.isEmpty else { return }
        let clamped = max(0, min(index, sources.count - 1))
        currentSourceIndex = clamped
    }

    func nextSource() {
        noteUserInteraction()
        guard !sources.isEmpty else { return }
        let next = min(sources.count - 1, currentSourceIndex + 1)
        currentSourceIndex = next
    }

    func previousSource() {
        noteUserInteraction()
        guard !sources.isEmpty else { return }
        let prev = max(0, currentSourceIndex - 1)
        currentSourceIndex = prev
    }

    func deleteSource(at index: Int) {
        noteUserInteraction()
        guard index >= 0, index < sources.count else { return }
        sources.remove(at: index)
        currentSourceIndex = min(currentSourceIndex, max(0, sources.count - 1))

        if sources.isEmpty {
            _ = addSource()
        }
    }

    func deleteCurrentSource() {
        deleteSource(at: currentSourceIndex)
    }

    // MARK: - Priming

    func toggleHUD() {
        isHUDVisible.toggle()
    }

    func togglePause() {
        isPaused.toggle()
    }

    func toggleWatchMode() {
        settings.watch.toggle()
        scheduleWatchTimer()
    }

    func excludeCurrentSource() {
        noteUserInteraction()
        guard let clip = currentClip else { return }
        library.exclude(file: clip.file)
        replaceClipForCurrentSource()
    }

    func markCurrentSourceForDeletion() {
        noteUserInteraction()
        guard let clip = currentClip else { return }
        library.markForDeletion(file: clip.file)
        replaceClipForCurrentSource()
        AppNotifications.shared.show("Marked for deletion", flash: true)
    }

    func toggleCurrentSourceFavorite() {
        noteUserInteraction()
        guard let clip = currentClip else { return }
        let isFavorited = FavoriteStore.shared.toggle(clip.file.source)
        let message = isFavorited ? "Added to favorites" : "Removed from favorites"
        AppNotifications.shared.show(message, flash: true)
    }

    /// Simple reset used by modes that want a clean slate.
    func resetForNextHypnogram() {
        sources.removeAll()
        effects.removeAll()
        currentSourceIndex = 0
        currentClipTimeOffset = nil
    }

    func newRandomHypnogram() {
        resetForNextHypnogram()
        let total = max(1, settings.maxSourcesForNew)
        let minCount = min(2, total)
        let count = Int.random(in: minCount...total)
        for i in 0..<max(1, count) {
            // First source uses SourceOver, rest get random blend modes
            let blendMode = (i == 0) ? kBlendModeSourceOver : randomBlendMode()
            addSource(blendMode: blendMode)
        }
    }

    /// Randomize blend modes and effects for all sources in current hypnogram
    func randomizeBlendModes() {
        noteUserInteraction()
        let allEffects = EffectRegistry.shared.allEffects()

        for i in 0..<sources.count {
            // First source stays SourceOver, rest get random blend modes
            let blendMode = (i == 0) ? kBlendModeSourceOver : randomBlendMode()
            sources[i].blendMode = blendMode

            // ~20% chance of getting a random effect
            if Double.random(in: 0..<1) < 0.2, let effect = allEffects.randomElement() {
                sources[i].effects = [effect]
            } else {
                sources[i].effects = []
            }
        }
        renderHooks.invalidateBlendAnalysis()
        renderHooks.onEffectChanged?()
    }

    /// Reset the watch timer when user interacts with the app
    func noteUserInteraction() {
        scheduleWatchTimer()
    }

    func scheduleWatchTimer() {
        guard settings.watch, settings.outputDuration.seconds > 0 else {
            watchTimer?.invalidate()
            watchTimer = nil
            return
        }

        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(
            withTimeInterval: settings.outputDuration.seconds,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            // Call mode-specific new() if available, otherwise fall back to newRandomHypnogram()
            if let callback = self.onWatchTimerFired {
                callback()
            } else {
                self.newRandomHypnogram()
            }
            self.scheduleWatchTimer()
        }
    }

    // MARK: - Library switching (unified: folders + Photos)

    func isLibraryActive(key: String) -> Bool {
        activeLibraryKeys.contains(key)
    }

    /// Toggle a library (folder or Photos) on/off
    func toggleLibrary(key: String) {
        Task { @MainActor in
            var keys = activeLibraryKeys

            if keys.contains(key) {
                // Removing - ensure at least one library remains
                if keys.count > 1 {
                    keys.remove(key)
                } else {
                    // Can't remove the last one - could switch to default, but for now just ignore
                    return
                }
            } else {
                keys.insert(key)
            }

            await applyActiveLibrariesUnified(keys, saveToModule: true)
        }
    }

    /// Apply a unified set of active library keys (both folder and Photos)
    @MainActor
    private func applyActiveLibrariesUnified(_ keys: Set<String>, saveToModule: Bool) async {
        activeLibraryKeys = keys

        // Separate folder keys from Photos keys
        var folderPaths: [String] = []
        var photosAlbums: [PHAssetCollection] = []

        for key in keys {
            if key.hasPrefix("photos:") {
                // It's a Photos album
                let identifier = String(key.dropFirst("photos:".count))
                if let album = await fetchPhotosAlbum(identifier: identifier) {
                    photosAlbums.append(album)
                }
            } else {
                // It's a folder library
                if let paths = settings.sourceLibraries[key] {
                    folderPaths.append(contentsOf: paths)
                }
            }
        }

        // Update tracking flags
        isUsingApplePhotosAlbum = !photosAlbums.isEmpty
        perModuleUsingPhotos[currentModuleType] = !photosAlbums.isEmpty
        currentLibraryKey = keys.first ?? settings.defaultSourceLibraryKey

        // Create combined library
        library = MediaSourcesLibrary(
            sourceFolders: folderPaths,
            photosAlbums: photosAlbums,
            allowedMediaTypes: settings.sourceMediaTypes
        )

        // Save to current module's library state if requested
        if saveToModule {
            perModuleLibraryKeys[currentModuleType] = keys
            savePerModuleLibrariesToSettings()
        }

        sources.removeAll()
        currentSourceIndex = 0
        currentClipTimeOffset = nil

        _ = addSource()

        watchTimer?.invalidate()
        watchTimer = nil
        if settings.watch {
            newRandomHypnogram()
            scheduleWatchTimer()
        }
    }

    /// Fetch a Photos album by identifier, with fallback for the default Sources album
    private func fetchPhotosAlbum(identifier: String) async -> PHAssetCollection? {
        let albums = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        if let found = albums.firstObject {
            return found
        }
        // Fallback for the default Sources album
        return await ApplePhotos.shared.getOrCreateSourcesAlbum()
    }

    // MARK: - Legacy Apple Photos methods (for backward compatibility)

    /// Switch to using Apple Photos album as the source (legacy - adds to active libraries)
    func useApplePhotosAlbum() {
        Task { @MainActor in
            guard ApplePhotos.shared.status.canRead else {
                AppNotifications.show("Photos access not granted", flash: true)
                return
            }

            guard let album = await ApplePhotos.shared.getOrCreateSourcesAlbum() else {
                AppNotifications.show("Failed to access Photos album", flash: true)
                return
            }

            let photosKey = "photos:\(album.localIdentifier)"
            var keys = activeLibraryKeys
            keys.insert(photosKey)
            await applyActiveLibrariesUnified(keys, saveToModule: true)

            AppNotifications.show("Added Apple Photos album", flash: true, duration: 1.5)
        }
    }

    /// Switch back to file-based sources only (removes all Photos libraries)
    func useFileSources() {
        Task { @MainActor in
            let folderKeys = activeLibraryKeys.filter { !$0.hasPrefix("photos:") }
            if folderKeys.isEmpty {
                // If no folder libraries, use the default
                await applyActiveLibrariesUnified([settings.defaultSourceLibraryKey], saveToModule: true)
            } else {
                await applyActiveLibrariesUnified(folderKeys, saveToModule: true)
            }
        }
    }

    // MARK: - Source Media Types

    func isMediaTypeActive(_ type: SourceMediaType) -> Bool {
        settings.sourceMediaTypes.contains(type)
    }

    func toggleMediaType(_ type: SourceMediaType) {
        Task { @MainActor in
            var types = settings.sourceMediaTypes

            if types.contains(type) {
                // Don't allow removing the last type
                if types.count > 1 {
                    types.remove(type)
                }
            } else {
                types.insert(type)
            }

            settings.sourceMediaTypes = types
            saveSettingsToDisk()
            // Rebuild library with new filter - reapply current libraries
            await applyActiveLibrariesUnified(activeLibraryKeys, saveToModule: false)
            AppNotifications.show("Takes effect on next Hypnogram", flash: true, duration: 1.5)
        }
    }

    /// Switch to the library configuration for a specific module
    private func switchToModuleLibraries(_ module: ModuleType) {
        // Get the module's saved library keys (which now include both folder and Photos keys)
        let keys = perModuleLibraryKeys[module] ?? [settings.defaultSourceLibraryKey]

        Task { @MainActor in
            await applyActiveLibrariesUnified(keys, saveToModule: false)
        }
    }

    // MARK: - Library Info for Menu Display

    /// Cached library info for menu display (includes asset counts)
    @Published private(set) var availableLibraries: [SourceLibraryInfo] = []

    /// Refresh the available libraries list with asset counts
    /// Call this when settings change or at app startup
    @MainActor
    func refreshAvailableLibraries() async {
        var infos: [SourceLibraryInfo] = []

        // Folder-based libraries
        for key in settings.sourceLibraryOrder {
            guard let paths = settings.sourceLibraries[key] else { continue }

            // Count assets by creating a temporary library
            let tempLibrary = MediaSourcesLibrary(
                sourceFolders: paths,
                allowedMediaTypes: settings.sourceMediaTypes
            )
            let count = tempLibrary.assetCount

            // Only include non-empty libraries
            if count > 0 {
                infos.append(SourceLibraryInfo(
                    id: key,
                    name: key,
                    type: .folders,
                    assetCount: count
                ))
            }
        }

        // Apple Photos albums
        if ApplePhotos.shared.status.canRead {
            var hasConfiguredAlbums = false

            for (name, identifier) in settings.applePhotosAlbums {
                hasConfiguredAlbums = true
                // Try to find album and count assets
                let count = await countPhotosAlbumAssets(identifier: identifier, name: name)
                if count > 0 {
                    infos.append(SourceLibraryInfo(
                        id: "photos:\(identifier)",
                        name: name,
                        type: .applePhotos,
                        assetCount: count
                    ))
                }
            }

            // If no albums configured, add the default Hypnograph/Sources album
            if !hasConfiguredAlbums {
                if let album = await ApplePhotos.shared.getOrCreateSourcesAlbum() {
                    let count = PHAsset.fetchAssets(in: album, options: nil).count
                    if count > 0 {
                        infos.append(SourceLibraryInfo(
                            id: "photos:\(album.localIdentifier)",
                            name: "Hypnograph Sources",
                            type: .applePhotos,
                            assetCount: count
                        ))
                    }
                }
            }
        }

        availableLibraries = infos
    }

    /// Count assets in a Photos album by identifier or name
    private func countPhotosAlbumAssets(identifier: String, name: String) async -> Int {
        // First try by local identifier
        let byId = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        if let album = byId.firstObject {
            return PHAsset.fetchAssets(in: album, options: nil).count
        }

        // Fall back to finding by name (for the hardcoded "Hypnograph/Sources" case)
        if name == "Hypnograph Sources" || name == "Sources" {
            if let album = await ApplePhotos.shared.getOrCreateSourcesAlbum() {
                return PHAsset.fetchAssets(in: album, options: nil).count
            }
        }

        return 0
    }

    /// Save per-module library selections to settings file
    private func savePerModuleLibrariesToSettings() {
        // Convert perModuleLibraryKeys to [String: [String]] for settings
        var librariesDict: [String: [String]] = [:]
        for (module, keys) in perModuleLibraryKeys {
            librariesDict[module.rawValue] = Array(keys)
        }

        settings.activeLibrariesPerMode = librariesDict
        saveSettingsToDisk()
    }

    /// Reload settings from disk and reapply basic configuration.
    func reloadSettings(from url: URL) {
        do {
            let newSettings = try SettingsLoader.load(from: url)
            self.settings = newSettings

            // Sync aspect ratio and resolution
            self.aspectRatio = newSettings.aspectRatio
            self.outputResolution = newSettings.outputResolution

            Task { @MainActor in
                await applyActiveLibrariesUnified(activeLibraryKeys, saveToModule: false)
            }

            watchTimer?.invalidate()
            watchTimer = nil
            if newSettings.watch {
                newRandomHypnogram()
                scheduleWatchTimer()
            }
        } catch {
            print("⚠️ Failed to reload settings from \(url.path): \(error)")
        }
    }

    // MARK: - Aspect Ratio & Resolution

    /// Set the aspect ratio and save to settings (applies immediately)
    func setAspectRatio(_ ratio: AspectRatio) {
        aspectRatio = ratio
        settings.aspectRatio = ratio
        saveSettingsToDisk()
        renderHooks.onEffectChanged?()
    }

    /// Set the output resolution and save to settings (applies immediately)
    func setOutputResolution(_ resolution: OutputResolution) {
        outputResolution = resolution
        settings.outputResolution = resolution
        saveSettingsToDisk()
        renderHooks.onEffectChanged?()
    }

    /// Save settings to disk
    private func saveSettingsToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: Environment.defaultSettingsURL)
            print("✅ Saved settings to \(Environment.defaultSettingsURL.path)")
        } catch {
            print("⚠️ Failed to save settings: \(error)")
        }
    }
}

// MARK: - Small helper

private extension Int {
    func positiveMod(_ n: Int) -> Int {
        let r = self % n
        return r >= 0 ? r : r + n
    }
}
