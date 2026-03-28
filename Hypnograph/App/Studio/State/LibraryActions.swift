//
//  LibraryActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Studio {
    func addFolderSourcesFromPanel() {
        addFolderLibrariesFromPanel()
    }

    func addFolderLibrariesFromPanel() {
        let selectedPaths = PathFormatting.storagePaths(from: panelHostService.chooseSourceFolders())
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

            for path in selectedPaths {
                let expandedPath = (path as NSString).expandingTildeInPath
                guard !existingPaths.contains(expandedPath) else { continue }

                let key = uniqueFolderLibraryKey(for: expandedPath, existingKeys: existingKeys)
                libraries[key] = [path]
                existingPaths.insert(expandedPath)
                existingKeys.insert(key)
                activeLibraries.insert(key)
            }

            settings.sources = .dictionary(libraries)
            settings.activeLibraries = Array(activeLibraries)
        }

        Task { @MainActor in
            await state.rebuildLibrary()
            await state.refreshAvailableLibraries()
        }
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
            await state.rebuildLibrary()
            await state.refreshAvailableLibraries()
        }
    }

    private func uniqueFolderLibraryKey(for expandedPath: String, existingKeys: Set<String>) -> String {
        let url = URL(fileURLWithPath: expandedPath)
        let baseName = url.deletingPathExtension().lastPathComponent.isEmpty
            ? url.lastPathComponent
            : url.deletingPathExtension().lastPathComponent
        let preferred = baseName.isEmpty ? "Source Folder" : baseName

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
