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

    // Per-module library state
    private var perModuleLibraryKeys: [ModuleType: Set<String>] = [:]

    @Published private(set) var currentLibraryKey: String
    @Published private(set) var activeLibraryKeys: Set<String>

    private(set) var library: MediaLibrary

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
    private let textFieldFocusMonitor = TextFieldFocusMonitor()

    /// Whether a text field is currently being edited (convenience for disabling shortcuts)
    @Published private(set) var isTyping: Bool = false

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
        self.library = MediaLibrary(
            sources: settings.folders(forLibraries: activeKeys),
            allowedMediaTypes: settings.sourceMediaTypes,
            exclusionStore: exclusionStore,
            deleteStore: deleteStore
        )

        // Initialize aspect ratio and resolution from settings (use montage player config as default)
        self.aspectRatio = settings.montagePlayerConfig.aspectRatio
        self.outputResolution = settings.outputResolution

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

        // Load custom photo selection from disk
        loadCustomSelectionFromDisk()

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
                let folderKeys = Set(settings.sourceLibraryOrder)
                guard let newKeys = MediaLibraryBuilder.computeToggledKeys(
                    currentKeys: activeLibraryKeys,
                    toggledKey: key,
                    folderLibraryKeys: folderKeys
                ) else { return }

                await applyActiveLibrariesUnified(newKeys, saveToModule: true)
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
        await applyActiveLibrariesUnified(result.keys, saveToModule: true)
    }

    /// Apply a unified set of active library keys (both folder and Photos)
    private func applyActiveLibrariesUnified(_ keys: Set<String>, saveToModule: Bool) async {
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

                settingsStore.update { $0.sourceMediaTypes = types }
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

        settingsStore.update { $0.activeLibrariesPerMode = librariesDict }
    }

    // MARK: - Aspect Ratio & Resolution

    /// Set the aspect ratio and save to settings (applies immediately)
    func setAspectRatio(_ ratio: AspectRatio) {
        aspectRatio = ratio
        settingsStore.update { $0.aspectRatio = ratio }
    }

    /// Set the output resolution and save to settings (applies immediately)
    func setOutputResolution(_ resolution: OutputResolution) {
        outputResolution = resolution
        settingsStore.update { $0.outputResolution = resolution }
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
