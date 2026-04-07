//
//  HypnographState.swift
//  Hypnograph
//
//  Clean unified state: no “candidate” concept, no mirrors,
//  one authoritative list of Layer objects.
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import CoreMedia
import CoreGraphics
import HypnoCore
import HypnoUI

/// Manages the current in-progress hypnogram.
@MainActor
final class HypnographState: ObservableObject {

    // MARK: - Core configuration

    /// App settings backed by PersistentStore for automatic persistence
    let settingsStore: StudioSettingsStore

    /// App-global settings backed by PersistentStore.
    let appSettingsStore: AppSettingsStore

    /// Convenience accessor for current settings value
    var settings: StudioSettings { settingsStore.value }
    var appSettings: AppSettings { appSettingsStore.value }

    let exclusionStore: ExclusionStore
    let sourceFavoritesStore: SourceFavoritesStore

    @Published private(set) var photosAuthorizationStatus: ApplePhotos.AuthorizationStatus
    @Published private(set) var currentLibraryKey: String
    @Published private(set) var activeLibraryKeys: Set<String>

    private(set) var library: MediaLibrary

    // MARK: - Init

    init(settingsStore: StudioSettingsStore, appSettingsStore: AppSettingsStore, coreConfig: HypnoCoreConfig) {
        let exclusionStore = ExclusionStore(url: coreConfig.exclusionsURL)
        let sourceFavoritesStore = SourceFavoritesStore(url: coreConfig.sourceFavoritesURL)

        self.settingsStore = settingsStore
        self.appSettingsStore = appSettingsStore
        self.exclusionStore = exclusionStore
        self.sourceFavoritesStore = sourceFavoritesStore

        ApplePhotos.shared.refreshStatus()
        let initialPhotosAuthorizationStatus = ApplePhotos.shared.status
        self.photosAuthorizationStatus = initialPhotosAuthorizationStatus

        // Local alias for init (self.settings is a computed property that can't be used yet)
        let settings = settingsStore.value
        let shouldClearPhotosSelections = Self.shouldClearPhotosSelections(for: initialPhotosAuthorizationStatus)

        let defaultKey = settings.defaultSourceLibraryKey

        // Load saved library keys from settings, or use defaults
        let activeKeys: Set<String>
        if !settings.activeLibraries.isEmpty {
            activeKeys = shouldClearPhotosSelections
                ? Set(settings.activeLibraries).filter { !$0.hasPrefix(ApplePhotosLibraryKeys.photosPrefix) }
                : Set(settings.activeLibraries)
        } else {
            activeKeys = shouldClearPhotosSelections ? [] : [defaultKey]
        }

        self.currentLibraryKey = activeKeys.first ?? settings.defaultSourceLibraryKey
        self.activeLibraryKeys = activeKeys

        // Load custom photo selection BEFORE building library so it's included
        let loadedCustomIds = shouldClearPhotosSelections ? [] : Self.loadCustomSelectionFromDisk()
        self.customPhotosAssetIds = loadedCustomIds

        if shouldClearPhotosSelections {
            Self.saveCustomSelectionToDisk([])
            settingsStore.update { settings in
                settings.activeLibraries = Array(activeKeys)
            }
        }

        // Build initial library with custom selection
        self.library = MediaLibraryBuilder.buildLibrary(
            keys: activeKeys,
            settings: settings,
            customPhotosAssetIds: loadedCustomIds,
            exclusionStore: exclusionStore
        )
    }

    // MARK: - UI Toggles

    func setPlaybackLoopMode(_ mode: PlaybackLoopMode) {
        settingsStore.update { settings in
            settings.playbackLoopMode = mode
        }
    }

    func setGenerateAtEnd(_ enabled: Bool) {
        settingsStore.update { settings in
            settings.generateAtEnd = enabled
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

    func setLibraryActive(key: String, active: Bool) async {
        let isCurrentlyActive = activeLibraryKeys.contains(key)
        guard isCurrentlyActive != active else { return }

        guard let newKeys = MediaLibraryBuilder.computeToggledKeys(
            currentKeys: activeLibraryKeys,
            toggledKey: key,
            folderLibraryKeys: Set(settings.sourceLibraryOrder)
        ) else { return }

        await applyActiveLibrariesUnified(newKeys, save: true)
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
            exclusionStore: exclusionStore
        )

        // Save to settings if requested
        if save {
            settingsStore.update { $0.activeLibraries = Array(keys) }
        }
    }

    /// Rebuilds the current library using the existing `activeLibraryKeys` and latest settings.
    /// Useful after settings changes that affect library contents (e.g. updating source folders).
    func rebuildLibrary() async {
        await applyActiveLibrariesUnified(activeLibraryKeys, save: false)
    }

    /// Re-sync active library selection from persisted settings before rebuilding.
    /// This is needed when settings mutations happen outside the usual toggle path.
    func reloadActiveLibrariesFromSettings() async {
        let persistedKeys = Set(settings.activeLibraries).filter {
            photosAuthorizationStatus.canRead || !$0.hasPrefix(ApplePhotosLibraryKeys.photosPrefix)
        }
        let keysToApply = persistedKeys.isEmpty ? [settings.defaultSourceLibraryKey] : persistedKeys
        await applyActiveLibrariesUnified(keysToApply, save: false)
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
                // Rebuild the active library and refresh the source inventory counts
                // shown in the Sources panel so this change reflects immediately.
                await applyActiveLibrariesUnified(activeLibraryKeys, save: false)
                await refreshAvailableLibraries()
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
            exclusionStore: exclusionStore
        )
    }

    /// After a fresh Photos authorization grant, PhotoKit can briefly return empty results
    /// before the library menu becomes queryable. Retry a few short passes so first-run
    /// users do not have to relaunch to see Apple Photos sources.
    func refreshPhotosLibrariesAfterAuthorization() async {
        let status = refreshPhotosAuthorizationStatus()
        guard status.canRead else { return }

        for _ in 0..<6 {
            await refreshAvailableLibraries()

            if availableLibraries.contains(where: { $0.type == .applePhotos }) {
                if activeLibraryKeys.contains(ApplePhotosLibraryKeys.photosAll)
                    || activeLibraryKeys.contains(ApplePhotosLibraryKeys.photosCustom)
                    || activeLibraryKeys.contains(where: { $0.hasPrefix(ApplePhotosLibraryKeys.photosPrefix) }) {
                    await applyActiveLibrariesUnified(activeLibraryKeys, save: false)
                }
                return
            }

            try? await Task.sleep(nanoseconds: 350_000_000)
            ApplePhotos.shared.refreshStatus()
            photosAuthorizationStatus = ApplePhotos.shared.status
            guard photosAuthorizationStatus.canRead else { return }
        }
    }

    @discardableResult
    func refreshPhotosAuthorizationStatus() -> ApplePhotos.AuthorizationStatus {
        ApplePhotos.shared.refreshStatus()
        let status = ApplePhotos.shared.status
        photosAuthorizationStatus = status
        if Self.shouldClearPhotosSelections(for: status) {
            Task { @MainActor in
                await clearPhotosSelectionsIfNeeded()
            }
        }
        return status
    }

    @discardableResult
    func requestPhotosAuthorizationIfNeeded() async -> ApplePhotos.AuthorizationStatus {
        let currentStatus = refreshPhotosAuthorizationStatus()
        if currentStatus.canRead {
            await refreshPhotosLibrariesAfterAuthorization()
            return currentStatus
        }

        let status = await ApplePhotos.shared.requestAuthorization()
        photosAuthorizationStatus = status
        let refreshedStatus = refreshPhotosAuthorizationStatus()

        if refreshedStatus.canRead {
            await refreshPhotosLibrariesAfterAuthorization()
        } else if Self.shouldClearPhotosSelections(for: refreshedStatus) {
            await clearPhotosSelectionsIfNeeded()
        }

        return refreshedStatus
    }

    // MARK: - Custom Photo Selection

    /// Flag to trigger the custom Photos source picker presentation
    @Published var showPhotosPickerForSource = false

    /// Flag to trigger the add-layer Photos picker presentation
    @Published var showPhotosPickerForAddLayer = false

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

    private static func saveCustomSelectionToDisk(_ identifiers: [String]) {
        do {
            let data = try JSONEncoder().encode(identifiers)
            try data.write(to: customSelectionFileURL)
        } catch {
            print("HypnographState: Failed to save custom selection: \(error)")
        }
    }

    /// Save custom selection to disk
    private func saveCustomSelectionToDisk() {
        Self.saveCustomSelectionToDisk(customPhotosAssetIds)
    }

    /// Save settings to disk (public - call after modifying state.settings via settingsStore.update)
    func saveSettings() {
        settingsStore.save()
    }

    var isKeyboardTextInputActive: Bool {
        KeyboardTextInputContext.isTypingInKeyOrMainWindow()
    }

    private static func shouldClearPhotosSelections(for status: ApplePhotos.AuthorizationStatus) -> Bool {
        status == .denied || status == .restricted
    }

    private func clearPhotosSelectionsIfNeeded() async {
        let retainedKeys = activeLibraryKeys.filter { !$0.hasPrefix(ApplePhotosLibraryKeys.photosPrefix) }
        let didChangeLibraries = retainedKeys != activeLibraryKeys
        let hadCustomSelection = !customPhotosAssetIds.isEmpty

        guard didChangeLibraries || hadCustomSelection else { return }

        if hadCustomSelection {
            customPhotosAssetIds = []
            saveCustomSelectionToDisk()
        }

        if didChangeLibraries {
            await applyActiveLibrariesUnified(retainedKeys, save: true)
        } else {
            settingsStore.update { settings in
                settings.activeLibraries = settings.activeLibraries.filter {
                    !$0.hasPrefix(ApplePhotosLibraryKeys.photosPrefix)
                }
            }
        }

        await refreshAvailableLibraries()
    }
}
