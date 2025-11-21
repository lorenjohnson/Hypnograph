//
//  Environment.swift
//  Hypnograph
//
//  Created by Loren Johnson on 17.11.25.
//


import AppKit
import Foundation

enum Environment {
    static let appFolderName = "Hypnograph"

    /// ~/Library/Application Support/Hypnograph
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

    /// ~/Library/Application Support/Hypnograph/Tools
    static var toolsDirectory: URL {
        let url = appSupportDirectory.appendingPathComponent("Tools", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }

    /// ~/Library/Application Support/Hypnograph/hypnograph-settings.json
    static var defaultSettingsURL: URL {
        appSupportDirectory.appendingPathComponent("hypnograph-settings.json")
    }

    /// ~/Library/Application Support/Hypnograph/exclusions.json
    static var exclusionsURL: URL {
        appSupportDirectory.appendingPathComponent("exclusions.json")
    }

    /// If no settings exists in Application Support, copy the bundled default JSON there.
    static func ensureDefaultSettingsFileExists() {
        let fm = FileManager.default
        let url = defaultSettingsURL

        guard !fm.fileExists(atPath: url.path) else { return }

        guard let bundledURL = Bundle.main.url(
            forResource: "default-settings",
            withExtension: "json"
        ) else {
            print("⚠️ No bundled default settings found; skipping creation.")
            return
        }

        do {
            try fm.copyItem(at: bundledURL, to: url)
            print("Copied bundled default settings to \(url.path)")
        } catch {
            print("Failed to copy default settings to \(url.path): \(error)")
        }
    }

    static func showSettingsFolderInFinder() {
        let url = appSupportDirectory
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    static func installCLI() {
        let fm = FileManager.default

        // 1) Locate bundled script in the app bundle
        guard let bundledURL = Bundle.main.url(
            forResource: "hypnograph",
            withExtension: nil
        ) else {
            print("⚠️ Could not find bundled hypnograph script in app bundle")
            return
        }

        // 2) Copy into ~/Library/Application Support/Hypnograph/Tools/hypnograph
        let destination = Environment.toolsDirectory.appendingPathComponent("hypnograph")

        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: bundledURL, to: destination)

            // Make it executable
            let attrs = try fm.attributesOfItem(atPath: destination.path)
            if let perms = attrs[.posixPermissions] as? NSNumber {
                let newPerms = perms.intValue | 0o111 // add execute bits
                try fm.setAttributes([.posixPermissions: newPerms], ofItemAtPath: destination.path)
            } else {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            }

            print("Installed hypnograph at \(destination.path)")
        } catch {
            print("Failed to install hypnograph: \(error)")
            return
        }

        // 3) Ensure ~/bin exists
        let homeDir = fm.homeDirectoryForCurrentUser
        let binDir = homeDir.appendingPathComponent("bin", isDirectory: true)
        if !fm.fileExists(atPath: binDir.path) {
            do {
                try fm.createDirectory(at: binDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create ~/bin: \(error)")
            }
        }

        // 4) Create symlink: ~/bin/hypnograph → .../Tools/hypnograph
        let symlinkURL = binDir.appendingPathComponent("hypnograph")
        do {
            if fm.fileExists(atPath: symlinkURL.path) {
                try fm.removeItem(at: symlinkURL)
            }
            try fm.createSymbolicLink(at: symlinkURL, withDestinationURL: destination)
            print("Created symlink \(symlinkURL.path) → \(destination.path)")
        } catch {
            print("Failed to create symlink in ~/bin: \(error)")
        }

        // 5) Reveal the installed script
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
}
