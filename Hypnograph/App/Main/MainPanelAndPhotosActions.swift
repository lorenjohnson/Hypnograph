//
//  MainPanelAndPhotosActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Main {
    var photosAuthorizationStatus: ApplePhotos.AuthorizationStatus {
        photosIntegrationService.authorizationStatus
    }

    func refreshPhotosStatus() -> ApplePhotos.AuthorizationStatus {
        photosIntegrationService.refreshStatus()
        return photosIntegrationService.authorizationStatus
    }

    func requestPhotosAccess() async -> ApplePhotos.AuthorizationStatus {
        let status = await photosIntegrationService.requestAuthorization()
        photosIntegrationService.refreshStatus()
        if status.canRead {
            await state.refreshPhotosLibrariesAfterAuthorization()
        }
        return photosIntegrationService.authorizationStatus
    }

    func addFolderSourcesFromPanel() {
        let selectedPaths = MainPathFormatting.storagePaths(from: panelHostService.chooseSourceFolders())
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

    func addSourceFromFilesPanel() {
        guard let selectedURL = panelHostService.chooseSingleMediaFile() else { return }
        _ = addSource(fromFileURL: selectedURL)
    }

    func chooseOutputFolder() {
        guard let folderURL = panelHostService.chooseDirectory(
            title: "Choose Render Output Folder",
            initialDirectoryURL: state.settings.outputURL
        ) else { return }

        state.settingsStore.update { settings in
            settings.outputFolder = MainPathFormatting.storagePath(from: folderURL)
        }
    }

    func chooseSnapshotsFolder() {
        guard let folderURL = panelHostService.chooseDirectory(
            title: "Choose Snapshot Folder",
            initialDirectoryURL: state.settings.snapshotsURL
        ) else { return }

        state.settingsStore.update { settings in
            settings.snapshotsFolder = MainPathFormatting.storagePath(from: folderURL)
        }
    }
}
