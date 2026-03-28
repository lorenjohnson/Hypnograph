//
//  SettingsPathActions.swift
//  Hypnograph
//

import Foundation

@MainActor
extension Main {
    func chooseOutputFolder() {
        guard let folderURL = panelHostService.chooseDirectory(
            title: "Choose Render Output Folder",
            initialDirectoryURL: state.settings.outputURL
        ) else { return }

        state.settingsStore.update { settings in
            settings.outputFolder = PathFormatting.storagePath(from: folderURL)
        }
    }

    func chooseSnapshotsFolder() {
        guard let folderURL = panelHostService.chooseDirectory(
            title: "Choose Snapshot Folder",
            initialDirectoryURL: state.settings.snapshotsURL
        ) else { return }

        state.settingsStore.update { settings in
            settings.snapshotsFolder = PathFormatting.storagePath(from: folderURL)
        }
    }
}
