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
@MainActor
final class HypnographState: ObservableObject {

    // MARK: - Core configuration

    private(set) var settings: Settings

    // Per-module library state
    private var perModuleLibraryKeys: [ModuleType: Set<String>] = [:]

    @Published private(set) var currentLibraryKey: String
    @Published private(set) var activeLibraryKeys: Set<String>

    private(set) var library: MediaSourcesLibrary

    // MARK: - Module management

    @Published var currentModuleType: ModuleType = .dream {
        didSet {
            if oldValue != currentModuleType {
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
    @Published var isInfoVisible: Bool = false
    @Published var isEffectsEditorVisible: Bool = false

    /// Shared effects editor view model for controller/keyboard navigation
    let effectsEditorViewModel = EffectsEditorViewModel()

    /// Whether the global layer is selected (currentSourceIndex == -1)
    var isOnGlobalLayer: Bool {
        currentSourceIndex == -1
    }

    /// Display string for the current editing layer
    /// Layer 0 = Global, Layer 1-N = Source 1-N
    var editingLayerDisplay: String {
        if currentSourceIndex == -1 {
            return "Global"
        }
        return "Source \(currentSourceIndex + 1) of \(sources.count)"
    }

    /// Select the global layer (for effects editing)
    func selectGlobalLayer() {
        noteUserInteraction()
        currentSourceIndex = -1
    }

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

    // Watch timer - generates new hypnograms at intervals when watch mode is enabled
    private var watchTimer: Timer?

    // Callback to trigger mode-specific new() when watch timer fires
    var onWatchTimerFired: (() -> Void)?

    // MARK: - Init

    init(settings: Settings) {
        self.settings = settings

        // Default to "Apple Photos: All Items" if available, otherwise folder sources
        let defaultKey: String
        if ApplePhotos.shared.status.canRead && ApplePhotos.shared.countAllAssets() > 0 {
            defaultKey = Self.photosAllItemsKey
        } else {
            defaultKey = settings.defaultSourceLibraryKey
        }
        let initialKeys: Set<String> = [defaultKey]

        // Initialize per-module library state from settings or use defaults
        var loadedPerModuleKeys: [ModuleType: Set<String>] = [:]
        for module in [ModuleType.dream, ModuleType.divine] {
            if let savedKeys = settings.activeLibrariesPerMode[module.rawValue], !savedKeys.isEmpty {
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

        // Subscribe to effect config reloads - reapply active effects with fresh instances
        Effect.onReload = { [weak self] in
            self?.renderHooks.reapplyActiveEffects()
        }

        // Subscribe to live effect parameter updates - apply directly without reload
        EffectConfigLoader.onEffectUpdated = { [weak self] effectIndex, updatedHook in
            self?.applyLiveEffectUpdate(effectIndex: effectIndex, hook: updatedHook)
        }

        // Load custom photo selection from disk (must be after all properties initialized)
        loadCustomSelectionFromDisk()
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

    // MARK: - Live Effect Updates

    /// Apply a live effect update directly without file reload
    func applyLiveEffectUpdate(effectIndex: Int, hook: RenderHook) {
        // Update the Effect.all cache so the library stays in sync
        Effect.updateCachedEffect(at: effectIndex, with: hook)

        // Get the effect name from the library
        let allEffects = Effect.all
        guard effectIndex >= 0 && effectIndex < allEffects.count else { return }
        let effectName = allEffects[effectIndex].name

        // Check if this effect is the current global effect
        if let currentEffect = recipe.effects.first, currentEffect.name == effectName {
            // Replace the global effect with the updated one
            recipe.effects = [hook]
            effectsChangeCounter += 1
        }

        // Check if this effect is applied to any sources
        for i in 0..<recipe.sources.count {
            if let sourceEffect = recipe.sources[i].effects.first, sourceEffect.name == effectName {
                recipe.sources[i].effects = [hook]
                effectsChangeCounter += 1
            }
        }
    }

    // MARK: - Priming

    func toggleHUD() {
        isHUDVisible.toggle()
    }

    func toggleEffectsEditor() {
        isEffectsEditorVisible.toggle()
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
    /// Preserves the current global effect by default.
    func resetForNextHypnogram(preserveGlobalEffect: Bool = true) {
        // Clear frame buffer to prevent ghost frames from previous montage
        renderHooks.clearFrameBuffer()

        // Preserve global effect before clearing
        let savedEffects = preserveGlobalEffect ? effects : []

        sources.removeAll()
        effects.removeAll()
        currentSourceIndex = 0
        currentClipTimeOffset = nil

        // Restore global effect if preserving
        if preserveGlobalEffect {
            effects = savedEffects
        }
    }

    func newRandomHypnogram() {
        resetForNextHypnogram(preserveGlobalEffect: true)
        let total = max(1, settings.maxSourcesForNew)
        let minCount = min(2, total)
        let count = Int.random(in: minCount...total)
        for i in 0..<max(1, count) {
            // First source uses SourceOver, rest get random blend modes
            let blendMode = (i == 0) ? BlendMode.sourceOver : BlendMode.random()
            addSource(blendMode: blendMode)
        }
    }

    /// Randomize blend modes and effects for all sources in current hypnogram
    func randomizeBlendModes() {
        noteUserInteraction()

        for i in 0..<sources.count {
            // First source stays SourceOver, rest get random blend modes
            let blendMode = (i == 0) ? BlendMode.sourceOver : BlendMode.random()
            sources[i].blendMode = blendMode

            // ~20% chance of getting a random effect
            if Double.random(in: 0..<1) < 0.2, let effect = Effect.random() {
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
        // Defer state changes to next run loop to avoid modifying @Published during view update
        DispatchQueue.main.async { [self] in
            Task { @MainActor in
                var keys = activeLibraryKeys

                if keys.contains(key) {
                    // Removing - ensure at least one library remains
                    if keys.count > 1 {
                        keys.remove(key)
                    } else {
                        // Can't remove the last one
                        return
                    }
                } else {
                    // Adding - handle "All" keys that should deselect others of same type
                    if key == Self.photosAllItemsKey {
                        // Deselect all other Photos albums
                        keys = keys.filter { !$0.hasPrefix("photos:") }
                    } else if key == Self.foldersAllKey {
                        // Deselect all individual folder libraries
                        let folderKeys = Set(settings.sourceLibraryOrder)
                        keys = keys.subtracting(folderKeys)
                    } else if key.hasPrefix("photos:") {
                        // Selecting a specific album deselects "All Items"
                        keys.remove(Self.photosAllItemsKey)
                    } else if settings.sourceLibraries[key] != nil {
                        // Selecting a specific folder deselects "All Folders"
                        keys.remove(Self.foldersAllKey)
                    }
                    keys.insert(key)
                }

                await applyActiveLibrariesUnified(keys, saveToModule: true)
            }
        }
    }

    /// Apply a unified set of active library keys (both folder and Photos)
    private func applyActiveLibrariesUnified(_ keys: Set<String>, saveToModule: Bool) async {
        activeLibraryKeys = keys

        // Separate folder keys from Photos keys
        var folderPaths: [String] = []
        var photosAlbums: [PHAssetCollection] = []
        var includeAllPhotos = false
        var includeCustomSelection = false

        for key in keys {
            if key == Self.photosAllItemsKey {
                // Special case: include all items from Photos
                includeAllPhotos = true
            } else if key == Self.photosCustomKey {
                // Special case: include custom-selected Photos assets
                includeCustomSelection = true
            } else if key.hasPrefix("photos:") {
                // It's a Photos album
                let identifier = String(key.dropFirst("photos:".count))
                if let album = await fetchPhotosAlbum(identifier: identifier) {
                    photosAlbums.append(album)
                }
            } else if key == Self.foldersAllKey {
                // Special case: include all folder libraries
                for libraryKey in settings.sourceLibraryOrder {
                    if let paths = settings.sourceLibraries[libraryKey] {
                        folderPaths.append(contentsOf: paths)
                    }
                }
            } else {
                // It's a specific folder library
                if let paths = settings.sourceLibraries[key] {
                    folderPaths.append(contentsOf: paths)
                }
            }
        }

        currentLibraryKey = keys.first ?? settings.defaultSourceLibraryKey

        // Create combined library
        library = MediaSourcesLibrary(
            sourceFolders: folderPaths,
            photosAlbums: photosAlbums,
            includeAllPhotos: includeAllPhotos,
            customPhotosAssetIds: includeCustomSelection ? customPhotosAssetIds : [],
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

    /// Fetch a Photos album by identifier
    private func fetchPhotosAlbum(identifier: String) async -> PHAssetCollection? {
        let albums = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        return albums.firstObject
    }

    // MARK: - Source Media Types

    func isMediaTypeActive(_ type: SourceMediaType) -> Bool {
        settings.sourceMediaTypes.contains(type)
    }

    func toggleMediaType(_ type: SourceMediaType) {
        // Defer state changes to next run loop to avoid modifying @Published during view update
        DispatchQueue.main.async { [self] in
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
    }

    /// Switch to the library configuration for a specific module
    private func switchToModuleLibraries(_ module: ModuleType) {
        // Get the module's saved library keys (which now include both folder and Photos keys)
        let keys = perModuleLibraryKeys[module] ?? [settings.defaultSourceLibraryKey]

        // Defer to avoid modifying @Published during view update
        DispatchQueue.main.async { [self] in
            Task { @MainActor in
                await applyActiveLibrariesUnified(keys, saveToModule: false)
            }
        }
    }

    // MARK: - Library Info for Menu Display

    /// Cached library info for menu display (includes asset counts)
    @Published private(set) var availableLibraries: [SourceLibraryInfo] = []

    /// Refresh the available libraries list with asset counts
    /// Call this when settings change or at app startup
    func refreshAvailableLibraries() async {
        var infos: [SourceLibraryInfo] = []

        // Folder-based libraries
        var folderInfos: [SourceLibraryInfo] = []
        var totalFolderCount = 0

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
                folderInfos.append(SourceLibraryInfo(
                    id: key,
                    name: key,
                    type: .folders,
                    assetCount: count
                ))
                totalFolderCount += count
            }
        }

        // Add "All Folders" option if there are multiple folder libraries
        if folderInfos.count > 1 {
            infos.append(SourceLibraryInfo(
                id: Self.foldersAllKey,
                name: "All Folders",
                type: .folders,
                assetCount: totalFolderCount
            ))
        }

        // Add individual folder libraries
        infos.append(contentsOf: folderInfos)

        // Apple Photos: All Items (always first)
        if ApplePhotos.shared.status.canRead {
            let allCount = ApplePhotos.shared.countAllAssets()
            if allCount > 0 {
                infos.append(SourceLibraryInfo(
                    id: Self.photosAllItemsKey,
                    name: "All Items",
                    type: .applePhotos,
                    assetCount: allCount
                ))
            }

            // Custom Selection (only show if there are selected assets)
            if !customPhotosAssetIds.isEmpty {
                infos.append(SourceLibraryInfo(
                    id: Self.photosCustomKey,
                    name: "Custom Selection",
                    type: .applePhotos,
                    assetCount: customPhotosAssetIds.count
                ))
            }

            // Dynamically list all user albums from Photos
            let userAlbums = ApplePhotos.shared.fetchUserAlbums()
            for album in userAlbums {
                infos.append(SourceLibraryInfo(
                    id: album.libraryKey,
                    name: album.title,
                    type: .applePhotos,
                    assetCount: album.assetCount
                ))
            }
        }

        availableLibraries = infos
    }

    /// Special key for "All Items" from Photos library
    static let photosAllItemsKey = "photos:all"

    /// Special key for "All Folders" (all folder libraries combined)
    static let foldersAllKey = "folders:all"

    /// Special key for custom-selected Photos assets
    static let photosCustomKey = "photos:custom"

    // MARK: - Custom Photo Selection

    /// Flag to trigger PhotosPicker presentation
    @Published var showPhotosPicker = false

    /// Storage for custom-selected Photos asset identifiers (per-module)
    @Published private(set) var customPhotosAssetIds: [String] = []

    /// Set the custom selection (replaces existing)
    func setCustomPhotosAssets(_ identifiers: [String]) {
        customPhotosAssetIds = identifiers

        // Save to disk
        saveCustomSelectionToDisk()

        // Refresh available libraries to update count
        Task {
            await refreshAvailableLibraries()
        }

        print("HypnographState: Set custom selection to \(customPhotosAssetIds.count) assets")
    }

    /// Clear the custom selection
    func clearCustomPhotosAssets() {
        setCustomPhotosAssets([])
    }

    /// File URL for custom selection storage
    private var customSelectionFileURL: URL {
        Environment.appSupportDirectory
            .appendingPathComponent("custom-photos-selection.json")
    }

    /// Load custom selection from disk
    private func loadCustomSelectionFromDisk() {
        guard FileManager.default.fileExists(atPath: customSelectionFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: customSelectionFileURL)
            customPhotosAssetIds = try JSONDecoder().decode([String].self, from: data)
            print("HypnographState: Loaded \(customPhotosAssetIds.count) custom-selected assets")
        } catch {
            print("HypnographState: Failed to load custom selection: \(error)")
        }
    }

    /// Save custom selection to disk
    private func saveCustomSelectionToDisk() {
        do {
            let data = try JSONEncoder().encode(customPhotosAssetIds)
            try data.write(to: customSelectionFileURL)
        } catch {
            print("HypnographState: Failed to save custom selection: \(error)")
        }
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

            Task {
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
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
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
