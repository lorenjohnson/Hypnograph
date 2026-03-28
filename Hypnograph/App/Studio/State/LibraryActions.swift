//
//  LibraryActions.swift
//  Hypnograph
//

import Foundation

@MainActor
extension Studio {
    func addFolderSourcesFromPanel() {
        let selectedPaths = PathFormatting.storagePaths(from: panelHostService.chooseSourceFolders())
        guard !selectedPaths.isEmpty else { return }

        state.settingsStore.update { settings in
            var libraries = settings.sources.libraries
            var paths = libraries["default"] ?? []
            for path in selectedPaths where !paths.contains(path) {
                paths.append(path)
            }
            libraries["default"] = paths
            settings.sources = .dictionary(libraries)

            if settings.activeLibraries.isEmpty {
                settings.activeLibraries = ["default"]
            }
        }

        Task { @MainActor in
            await state.rebuildLibrary()
            await state.refreshAvailableLibraries()
        }
    }
}
