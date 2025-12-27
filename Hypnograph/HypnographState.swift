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

    /// App settings - publicly settable for UI state changes, call saveSettings() to persist
    @Published var settings: Settings

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

    // MARK: - Global UI State

    /// Monitors text field editing - used to disable single-key shortcuts while typing
    let textFieldFocusMonitor = TextFieldFocusMonitor()

    /// Unified window visibility state with clean screen support
    @Published var windowState = WindowState()

    /// Shared effects editor view model for controller/keyboard navigation
    let effectsEditorViewModel = EffectsEditorViewModel()

    /// Current aspect ratio for composition (global default)
    @Published var aspectRatio: AspectRatio

    /// Current output resolution (global default)
    @Published var outputResolution: OutputResolution

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
      sources: settings.folders(forLibraries: activeKeys),
      allowedMediaTypes: settings.sourceMediaTypes
    )

        // Initialize aspect ratio and resolution from settings
        self.aspectRatio = settings.aspectRatio
        self.outputResolution = settings.outputResolution

        // Start watch timer if enabled (modules will set onWatchTimerFired callback)
        if settings.watch {
            scheduleWatchTimer()
        }

        // Load custom photo selection from disk
        loadCustomSelectionFromDisk()
    }

    // MARK: - UI Toggles

    func toggleWatchMode() {
        settings.watch.toggle()
        scheduleWatchTimer()
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
            // Call mode-specific new() - modules set this callback
            self.onWatchTimerFired?()
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
      sources: folderPaths,
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

        // Don't regenerate content immediately when changing sources
        // Just reset the watch timer and let it fire naturally
        watchTimer?.invalidate()
        watchTimer = nil
        if settings.watch {
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
      sources: paths,
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

            // Trigger the module to regenerate content
            watchTimer?.invalidate()
            watchTimer = nil
            onWatchTimerFired?()
            if newSettings.watch {
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
    }

    /// Set the output resolution and save to settings (applies immediately)
    func setOutputResolution(_ resolution: OutputResolution) {
        outputResolution = resolution
        settings.outputResolution = resolution
        saveSettingsToDisk()
    }

    /// Save settings to disk (public - call after modifying state.settings)
    func saveSettings() {
        saveSettingsToDisk()
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
