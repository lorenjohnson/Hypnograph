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
import HypnoCore
import HypnoUI

/// Manages the current in-progress hypnogram.
@MainActor
final class HypnographState: ObservableObject {

    // MARK: - Core configuration

    /// App settings backed by PersistentStore for automatic persistence
    let settingsStore: SettingsStore

    /// Convenience accessor for current settings value
    var settings: Settings { settingsStore.value }

    let exclusionStore: ExclusionStore
    let deleteStore: DeleteStore

    @Published private(set) var currentLibraryKey: String
    @Published private(set) var activeLibraryKeys: Set<String>

    private(set) var library: MediaLibrary

    // MARK: - Global UI State

    /// Monitors text field editing - used to disable single-key shortcuts while typing
    private let textFieldFocusMonitor = TextFieldFocusMonitor()

    /// Whether a text field is currently being edited (convenience for disabling shortcuts)
    @Published private(set) var isTyping: Bool = false

    /// Unified window visibility state with clean screen support
    @Published var windowState = WindowState()

    /// Shared effects editor view model for controller/keyboard navigation
    let effectsEditorViewModel = EffectsEditorViewModel()

    // Watch timer - generates new hypnograms at intervals when watch mode is enabled
    private var watchTimer: Timer?

    private var cancellables: Set<AnyCancellable> = []

    // Callback to trigger mode-specific new() when watch timer fires
    var onWatchTimerFired: (() -> Void)?

    // MARK: - Init

    init(settingsStore: SettingsStore, coreConfig: HypnoCoreConfig) {
        let exclusionStore = ExclusionStore(url: coreConfig.exclusionsURL)
        let deleteStore = DeleteStore(url: coreConfig.deletionsURL)

        self.settingsStore = settingsStore
        self.exclusionStore = exclusionStore
        self.deleteStore = deleteStore

        // Local alias for init (self.settings is a computed property that can't be used yet)
        let settings = settingsStore.value

        // Default to "Apple Photos: All Items" if available, otherwise folder sources
        let defaultKey: String
        if ApplePhotos.shared.status.canRead && ApplePhotos.shared.countAllAssets() > 0 {
            defaultKey = ApplePhotosLibraryKeys.photosAll
        } else {
            defaultKey = settings.defaultSourceLibraryKey
        }

        // Load saved library keys from settings, or use defaults
        let activeKeys: Set<String>
        if !settings.activeLibraries.isEmpty {
            activeKeys = Set(settings.activeLibraries)
        } else {
            activeKeys = [defaultKey]
        }

        self.currentLibraryKey = defaultKey
        self.activeLibraryKeys = activeKeys

        // Load custom photo selection BEFORE building library so it's included
        let loadedCustomIds = Self.loadCustomSelectionFromDisk()
        self.customPhotosAssetIds = loadedCustomIds

        // Build initial library with custom selection
        self.library = MediaLibraryBuilder.buildLibrary(
            keys: activeKeys,
            settings: settings,
            customPhotosAssetIds: loadedCustomIds,
            exclusionStore: exclusionStore,
            deleteStore: deleteStore
        )

        self.isTyping = textFieldFocusMonitor.isEditing
        textFieldFocusMonitor.$isEditing
            .removeDuplicates()
            .sink { [weak self] isEditing in
                self?.isTyping = isEditing
            }
            .store(in: &cancellables)

        // Start watch timer if enabled (modules will set onWatchTimerFired callback)
        if settings.watch {
            scheduleWatchTimer()
        }

        // Load window state from disk
        loadWindowStateFromDisk()
    }

    // MARK: - UI Toggles

    func toggleWatchMode() {
        settingsStore.update { $0.watch.toggle() }
        scheduleWatchTimer()
    }

    /// Reset the watch timer when user interacts with the app
    func noteUserInteraction() {
        scheduleWatchTimer()
    }

    func scheduleWatchTimer() {
        guard settings.watch, settings.watchInterval > 0 else {
            watchTimer?.invalidate()
            watchTimer = nil
            return
        }

        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(
            withTimeInterval: settings.watchInterval,
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
                let folderKeys = Set(settings.sourceLibraryOrder)
                guard let newKeys = MediaLibraryBuilder.computeToggledKeys(
                    currentKeys: activeLibraryKeys,
                    toggledKey: key,
                    folderLibraryKeys: folderKeys
                ) else { return }

                await applyActiveLibrariesUnified(newKeys, save: true)
            }
        }
    }

    func activatePhotosAllIfAvailable() async {
        // Shared post-auth fallback: if Photos is authorized but the active library is empty,
        // ensure Photos "All Items" is selected. This is centralized in HypnoCore so both
        // Hypnograph + Divine behave identically.
        let result = ApplePhotosCoordinator.ensurePhotosAllIfAuthorizedAndLibraryEmpty(
            activeKeys: activeLibraryKeys,
            libraryAssetCount: library.assetCount,
            photosCanRead: ApplePhotos.shared.status.canRead,
            photosAllAssetsCount: ApplePhotos.shared.countAllAssets()
        )

        guard result.didChange else { return }
        await applyActiveLibrariesUnified(result.keys, save: true)
    }

    /// Apply a unified set of active library keys (both folder and Photos)
    private func applyActiveLibrariesUnified(_ keys: Set<String>, save: Bool) async {
        activeLibraryKeys = keys
        currentLibraryKey = keys.first ?? settings.defaultSourceLibraryKey

        // Create combined library using shared builder
        library = MediaLibraryBuilder.buildLibrary(
            keys: keys,
            settings: settings,
            customPhotosAssetIds: customPhotosAssetIds,
            exclusionStore: exclusionStore,
            deleteStore: deleteStore
        )

        // Save to settings if requested
        if save {
            settingsStore.update { $0.activeLibraries = Array(keys) }
        }

        // Don't regenerate content immediately when changing sources
        // Just reset the watch timer and let it fire naturally
        watchTimer?.invalidate()
        watchTimer = nil
        if settings.watch {
            scheduleWatchTimer()
        }
    }

    // MARK: - Source Media Types

    func isMediaTypeActive(_ type: MediaType) -> Bool {
        settings.sourceMediaTypes.contains(type)
    }

    func toggleMediaType(_ type: MediaType) {
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

                settingsStore.update { $0.sourceMediaTypes = types }
                // Rebuild library with new filter - reapply current libraries
                await applyActiveLibrariesUnified(activeLibraryKeys, save: false)
                AppNotifications.show("Takes effect on next Hypnogram", flash: true, duration: 1.5)
            }
        }
    }

    // MARK: - Library Info for Menu Display

    /// Cached library info for menu display (includes asset counts)
    @Published private(set) var availableLibraries: [SourceLibraryInfo] = []

    /// Refresh the available libraries list with asset counts
    /// Call this when settings change or at app startup
    func refreshAvailableLibraries() async {
        availableLibraries = MediaLibraryBuilder.buildAvailableLibraries(
            settings: settings,
            customPhotosAssetIds: customPhotosAssetIds,
            exclusionStore: exclusionStore,
            deleteStore: deleteStore
        )
    }

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

        // Refresh available libraries to update count and rebuild library if custom is active
        Task { @MainActor in
            await refreshAvailableLibraries()

            // If custom selection is currently active, rebuild the library with new assets
            if activeLibraryKeys.contains(ApplePhotosLibraryKeys.photosCustom) {
                await applyActiveLibrariesUnified(activeLibraryKeys, save: false)
            }
        }

        print("HypnographState: Set custom selection to \(customPhotosAssetIds.count) assets")
    }

    /// Clear the custom selection
    func clearCustomPhotosAssets() {
        setCustomPhotosAssets([])
    }

    /// File URL for custom selection storage
    private static var customSelectionFileURL: URL {
        Environment.appSupportDirectory
            .appendingPathComponent("custom-photos-selection.json")
    }

    /// Load custom selection from disk (static for use in init)
    private static func loadCustomSelectionFromDisk() -> [String] {
        let url = customSelectionFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let ids = try JSONDecoder().decode([String].self, from: data)
            print("HypnographState: Loaded \(ids.count) custom-selected assets")
            return ids
        } catch {
            print("HypnographState: Failed to load custom selection: \(error)")
            return []
        }
    }

    /// Save custom selection to disk
    private func saveCustomSelectionToDisk() {
        do {
            let data = try JSONEncoder().encode(customPhotosAssetIds)
            try data.write(to: Self.customSelectionFileURL)
        } catch {
            print("HypnographState: Failed to save custom selection: \(error)")
        }
    }

    /// Save settings to disk (public - call after modifying state.settings via settingsStore.update)
    func saveSettings() {
        settingsStore.save()
    }

    // MARK: - Window State Persistence

    /// File URL for window state storage
    private var windowStateFileURL: URL {
        Environment.appSupportDirectory
            .appendingPathComponent("window-state.json")
    }

    /// Load window state from disk
    private func loadWindowStateFromDisk() {
        guard FileManager.default.fileExists(atPath: windowStateFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: windowStateFileURL)
            windowState = try JSONDecoder().decode(WindowState.self, from: data)
            print("HypnographState: Loaded window state from disk")
        } catch {
            print("HypnographState: Failed to load window state: \(error)")
        }
    }

    /// Save window state to disk
    func saveWindowStateToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(windowState)
            try data.write(to: windowStateFileURL)
            print("HypnographState: Saved window state to disk")
        } catch {
            print("HypnographState: Failed to save window state: \(error)")
        }
    }
}

// MARK: - Small helper

private extension Int {
    func positiveMod(_ n: Int) -> Int {
        let r = self % n
        return r >= 0 ? 0 + r : r + n
    }
}
