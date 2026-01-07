import Foundation
import HypnoCore

/// Divine-specific state management for standalone Divine.app
/// Mirrors the library management functionality from HypnographState
@MainActor
final class DivineState: ObservableObject {

    // MARK: - Settings

    /// App settings backed by PersistentStore for automatic persistence
    let settingsStore: SettingsStore

    /// Convenience accessor for current settings value
    var settings: Settings { settingsStore.value }

    // MARK: - Library Management

    let exclusionStore: ExclusionStore
    let deleteStore: DeleteStore

    @Published private(set) var currentLibraryKey: String
    @Published private(set) var activeLibraryKeys: Set<String>
    private(set) var library: MediaLibrary

    // MARK: - Custom Photo Selection

    @Published var showPhotosPicker = false
    @Published private(set) var customPhotosAssetIds: [String] = []

    // MARK: - Available Libraries Cache

    @Published private(set) var availableLibraries: [SourceLibraryInfo] = []

    // MARK: - Init

    init(settingsStore: SettingsStore, coreConfig: HypnoCoreConfig) {
        self.settingsStore = settingsStore

        // Initialize stores
        let exclusionStore = ExclusionStore(url: coreConfig.exclusionsURL)
        let deleteStore = DeleteStore(url: coreConfig.deletionsURL)
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

        // Load saved library keys or use defaults
        let activeKeys: Set<String>
        if !settings.activeLibraryKeys.isEmpty {
            activeKeys = Set(settings.activeLibraryKeys)
        } else {
            activeKeys = initialKeys
        }

        self.currentLibraryKey = defaultKey
        self.activeLibraryKeys = activeKeys

        // Build initial library
        self.library = MediaLibraryBuilder.buildLibrary(
            keys: activeKeys,
            settings: settings,
            customPhotosAssetIds: [],
            exclusionStore: exclusionStore,
            deleteStore: deleteStore
        )

        // Load custom selection
        loadCustomSelectionFromDisk()
    }

    // MARK: - Library Activation

    func isLibraryActive(key: String) -> Bool {
        activeLibraryKeys.contains(key)
    }

    func toggleLibrary(key: String) {
        DispatchQueue.main.async { [self] in
            Task { @MainActor in
                guard let newKeys = MediaLibraryBuilder.computeToggledKeys(
                    currentKeys: activeLibraryKeys,
                    toggledKey: key,
                    folderLibraryKeys: Set(settings.sourceLibraryOrder)
                ) else { return }

                await applyActiveLibraries(newKeys)
            }
        }
    }

    private func applyActiveLibraries(_ keys: Set<String>) async {
        activeLibraryKeys = keys
        currentLibraryKey = keys.first ?? settings.defaultSourceLibraryKey

        library = MediaLibraryBuilder.buildLibrary(
            keys: keys,
            settings: settings,
            customPhotosAssetIds: customPhotosAssetIds,
            exclusionStore: exclusionStore,
            deleteStore: deleteStore
        )

        // Save to settings
        settingsStore.update { $0.activeLibraryKeys = Array(keys) }
    }

    // MARK: - Source Media Types

    func isMediaTypeActive(_ type: SourceMediaType) -> Bool {
        settings.sourceMediaTypes.contains(type)
    }

    func toggleMediaType(_ type: SourceMediaType) {
        DispatchQueue.main.async { [self] in
            Task { @MainActor in
                var types = settings.sourceMediaTypes

                if types.contains(type) {
                    if types.count > 1 {
                        types.remove(type)
                    }
                } else {
                    types.insert(type)
                }

                settingsStore.update { $0.sourceMediaTypes = types }

                // Rebuild library with new filter
                await applyActiveLibraries(activeLibraryKeys)
            }
        }
    }

    // MARK: - Available Libraries

    func refreshAvailableLibraries() async {
        availableLibraries = MediaLibraryBuilder.buildAvailableLibraries(
            settings: settings,
            customPhotosAssetIds: customPhotosAssetIds,
            exclusionStore: exclusionStore,
            deleteStore: deleteStore
        )
    }

    // MARK: - Custom Photo Selection

    func setCustomPhotosAssets(_ identifiers: [String]) {
        customPhotosAssetIds = identifiers
        saveCustomSelectionToDisk()

        Task {
            await refreshAvailableLibraries()
        }
    }

    func clearCustomPhotosAssets() {
        setCustomPhotosAssets([])
    }

    private var customSelectionFileURL: URL {
        DivineEnvironment.appSupportDirectory
            .appendingPathComponent("custom-photos-selection.json")
    }

    private func loadCustomSelectionFromDisk() {
        guard FileManager.default.fileExists(atPath: customSelectionFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: customSelectionFileURL)
            customPhotosAssetIds = try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("DivineState: Failed to load custom selection: \(error)")
        }
    }

    private func saveCustomSelectionToDisk() {
        do {
            let data = try JSONEncoder().encode(customPhotosAssetIds)
            try data.write(to: customSelectionFileURL)
        } catch {
            print("DivineState: Failed to save custom selection: \(error)")
        }
    }

    // MARK: - Library Rebuild

    /// Rebuild the active library (e.g., after Photos authorization changes)
    func rebuildActiveLibrary() {
        library = MediaLibraryBuilder.buildLibrary(
            keys: activeLibraryKeys,
            settings: settings,
            customPhotosAssetIds: customPhotosAssetIds,
            exclusionStore: exclusionStore,
            deleteStore: deleteStore
        )
    }

    /// Activate Photos "All Items" if authorized and current library is empty
    func activatePhotosAllIfAvailable() {
        let result = ApplePhotosCoordinator.ensurePhotosAllIfAuthorizedAndLibraryEmpty(
            activeKeys: activeLibraryKeys,
            libraryAssetCount: library.assetCount,
            photosCanRead: ApplePhotos.shared.status.canRead,
            photosAllAssetsCount: ApplePhotos.shared.countAllAssets()
        )

        guard result.didChange else { return }
        activeLibraryKeys = result.keys
        currentLibraryKey = result.keys.first ?? settings.defaultSourceLibraryKey
        rebuildActiveLibrary()
    }

    // MARK: - Media Access (for Divine module)

    func randomClip() -> VideoClip? {
        library.randomClip()
    }

    func exclude(file: MediaFile) {
        library.exclude(file: file)
    }

}

// MARK: - Settings

struct Settings: Codable, MediaLibrarySettings {
    var sourceMediaTypes: Set<SourceMediaType> = [.images, .videos]
    var activeLibraryKeys: [String] = []

    // MediaLibrarySettings conformance
    var sourceLibraries: [String: [String]] = [:]
    var sourceLibraryOrder: [String] = []
    var defaultSourceLibraryKey: String = ApplePhotosLibraryKeys.photosAll
}
