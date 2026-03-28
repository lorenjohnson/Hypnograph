//
//  FilePanelService.swift
//  Hypnograph
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class FilePanelService {
    func chooseSingleMediaFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .movie]

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func chooseSourceFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folder(s) to add as Hypnograph sources."

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    func chooseDirectory(
        title: String,
        initialDirectoryURL: URL?
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.title = title
        panel.directoryURL = initialDirectoryURL

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
