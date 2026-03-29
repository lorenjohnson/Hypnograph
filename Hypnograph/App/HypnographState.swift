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
        self.photosAuthorizationStatus = ApplePhotos.shared.status

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
            exclusionStore: exclusionStore
        )
    }

    // MARK: - UI Toggles

    func setLoopCurrentCompositionMode(_ enabled: Bool) {
        settingsStore.update { settings in
            settings.playbackEndBehavior = enabled ? .loopCurrentComposition : .autoAdvance
        }
    }

    func toggleLoopCurrentCompositionMode() {
        let shouldEnableLoop = settings.playbackEndBehavior != .loopCurrentComposition
        setLoopCurrentCompositionMode(shouldEnableLoop)
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
        let persistedKeys = Set(settings.activeLibraries)
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
            await activatePhotosAllIfAvailable()
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
        }

        return refreshedStatus
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

    var isKeyboardTextInputActive: Bool {
        KeyboardTextInputContext.isTypingInKeyOrMainWindow()
    }
}
