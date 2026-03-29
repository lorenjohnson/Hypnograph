//
//  LibraryActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Studio {
    func addFolderSourcesFromPanel() {
        addSourceLibrariesFromPanel()
    }

    func addFolderLibrariesFromPanel() {
        addSourceLibrariesFromPanel()
    }

    func addSourceLibrariesFromPanel() {
        let selectedPaths = PathFormatting.storagePaths(from: panelHostService.chooseSourceFilesAndFolders())
        guard !selectedPaths.isEmpty else { return }

        state.settingsStore.update { settings in
            var libraries = settings.sources.libraries
            var activeLibraries = Set(settings.activeLibraries)
            var existingPaths = Set(
                libraries.values
                    .flatMap { $0 }
                    .map { ($0 as NSString).expandingTildeInPath }
            )
            var existingKeys = Set(libraries.keys)
            let newPaths = selectedPaths.filter { path in
                let expandedPath = (path as NSString).expandingTildeInPath
                return !existingPaths.contains(expandedPath)
            }

            guard !newPaths.isEmpty else { return }

            let expandedNewPaths = newPaths.map { ($0 as NSString).expandingTildeInPath }
            let key = uniqueSourceLibraryKey(forExpandedPaths: expandedNewPaths, existingKeys: existingKeys)
            libraries[key] = newPaths

            for expandedPath in expandedNewPaths {
                existingPaths.insert(expandedPath)
            }
            existingKeys.insert(key)
            activeLibraries.insert(key)

            settings.sources = .dictionary(libraries)
            settings.activeLibraries = Array(activeLibraries)
        }

        Task { @MainActor in
            await state.reloadActiveLibrariesFromSettings()
            await state.refreshAvailableLibraries()
        }
    }

    func addApplePhotosAllSource() async {
        await state.setLibraryActive(key: ApplePhotosLibraryKeys.photosAll, active: true)
        await state.refreshAvailableLibraries()
    }

    func addApplePhotosAlbumSources(_ keys: [String]) async {
        for key in keys {
            await state.setLibraryActive(key: key, active: true)
        }
        await state.refreshAvailableLibraries()
    }

    func removePhotosSource(_ key: String) async {
        guard key == ApplePhotosLibraryKeys.photosAll
            || key == ApplePhotosLibraryKeys.photosCustom
            || key.hasPrefix(ApplePhotosLibraryKeys.photosPrefix)
        else { return }

        if key == ApplePhotosLibraryKeys.photosCustom {
            state.clearCustomPhotosAssets()
        }

        await state.setLibraryActive(key: key, active: false)
        await state.refreshAvailableLibraries()
    }

    func removeFolderLibrary(_ key: String) {
        state.settingsStore.update { settings in
            var libraries = settings.sources.libraries
            libraries.removeValue(forKey: key)
            settings.sources = .dictionary(libraries)

            var activeLibraries = Set(settings.activeLibraries)
            activeLibraries.remove(key)

            if activeLibraries.isEmpty, !libraries.isEmpty {
                let fallbackDefault = libraries.keys.sorted().first ?? "default"
                activeLibraries.insert(fallbackDefault)
            }

            settings.activeLibraries = Array(activeLibraries)
        }

        Task { @MainActor in
            await state.reloadActiveLibrariesFromSettings()
            await state.refreshAvailableLibraries()
        }
    }

    private func uniqueSourceLibraryKey(forExpandedPaths expandedPaths: [String], existingKeys: Set<String>) -> String {
        let preferred: String
        if expandedPaths.count == 1 {
            let url = URL(fileURLWithPath: expandedPaths[0])
            let baseName = url.deletingPathExtension().lastPathComponent.isEmpty
                ? url.lastPathComponent
                : url.deletingPathExtension().lastPathComponent
            preferred = baseName.isEmpty ? "Sources" : baseName
        } else {
            let firstURL = URL(fileURLWithPath: expandedPaths[0])
            let firstName = firstURL.deletingPathExtension().lastPathComponent.isEmpty
                ? firstURL.lastPathComponent
                : firstURL.deletingPathExtension().lastPathComponent
            let seed = firstName.isEmpty ? "Selection" : firstName
            preferred = "\(seed) + \(expandedPaths.count - 1)"
        }

        guard !existingKeys.contains(preferred) else {
            var suffix = 2
            while existingKeys.contains("\(preferred) \(suffix)") {
                suffix += 1
            }
            return "\(preferred) \(suffix)"
        }

        return preferred
    }
}
