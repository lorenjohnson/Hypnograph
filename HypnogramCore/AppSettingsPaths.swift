//
//  AppSettingsPaths.swift
//  Hypnogram
//
//  Created by Loren Johnson on 16.11.25.
//


// AppSettingsPaths.swift

import AppKit
import Foundation

enum AppSettingsPaths {
    static let appFolderName = "Hypnogram"

    /// ~/Library/Application Support/Hypnogram
    static var appSupportDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = base.appendingPathComponent(appFolderName, isDirectory: true)

        if !fm.fileExists(atPath: appDir.path) {
            try? fm.createDirectory(
                at: appDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        return appDir
    }

    /// ~/Library/Application Support/Hypnogram/hypnogram-settings.json
    static var defaultConfigURL: URL {
        appSupportDirectory.appendingPathComponent("hypnogram-settings.json")
    }

    /// If no config exists in Application Support, copy the bundled default JSON there.
    static func ensureDefaultConfigFileExists() {
        let fm = FileManager.default
        let url = defaultConfigURL

        guard !fm.fileExists(atPath: url.path) else { return }

        guard let bundledURL = Bundle.main.url(
            forResource: "hypnogram-default-settings",
            withExtension: "json"
        ) else {
            print("⚠️ No bundled default config found; skipping creation.")
            return
        }

        do {
            try fm.copyItem(at: bundledURL, to: url)
            print("Copied bundled default config to \(url.path)")
        } catch {
            print("Failed to copy default config to \(url.path): \(error)")
        }
    }

    static func showSettingsFolderInFinder() {
        let url = appSupportDirectory
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
