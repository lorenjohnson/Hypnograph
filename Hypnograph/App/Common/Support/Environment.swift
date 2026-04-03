//
//  Environment.swift
//  Hypnograph
//
//  Created by Loren Johnson on 17.11.25.
//

import AppKit
import Foundation

enum Environment {
    static var appFolderName: String {
        #if DEBUG
        "Hypnograph-Debug"
        #else
        "Hypnograph"
        #endif
    }

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

    /// ~/Library/Services
    static var userServicesDirectory: URL {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("Library/Services", isDirectory: true)

        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }

        return dir
    }

    /// ~/Library/Application Support/Hypnograph/main-settings.json
    static var defaultStudioSettingsURL: URL {
        appSupportDirectory.appendingPathComponent("main-settings.json")
    }

    /// ~/Library/Application Support/Hypnograph/hypnograph-settings.json
    static var defaultAppSettingsURL: URL {
        appSupportDirectory.appendingPathComponent("hypnograph-settings.json")
    }

    /// ~/Library/Application Support/Hypnograph/effects-studio-settings.json
    static var defaultEffectsComposerSettingsURL: URL {
        appSupportDirectory.appendingPathComponent("effects-studio-settings.json")
    }

    /// ~/Library/Application Support/Hypnograph/history.json
    static var historyURL: URL {
        appSupportDirectory.appendingPathComponent("history.json")
    }

    /// Legacy history filename kept for one-way migration reads.
    static var legacyClipHistoryURL: URL {
        appSupportDirectory.appendingPathComponent("clip-history.json")
    }

    /// ~/Library/Application Support/Hypnograph/exclusions.json
    static var exclusionsURL: URL {
        appSupportDirectory.appendingPathComponent("exclusions.json")
    }

    /// ~/Library/Application Support/Hypnograph/luts/
    static var lutsDirectory: URL {
        let url = appSupportDirectory.appendingPathComponent("luts", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }

    /// If no studio settings exists in Application Support, copy the bundled default JSON there.
    static func ensureDefaultStudioSettingsFileExists() {
        let bundledURL = Bundle.main.url(
            forResource: "default-settings",
            withExtension: "json"
        )
        ensureSettingsFileExists(
            at: defaultStudioSettingsURL,
            bundledURL: bundledURL,
            defaultSettings: StudioSettings.defaultValue
        )
    }

    static func ensureDefaultAppSettingsFileExists() {
        let fm = FileManager.default
        let url = defaultAppSettingsURL
        guard !fm.fileExists(atPath: url.path) else { return }

        let migratedKeyboardOverride = keyboardAccessibilityOverrideFromStudioSettings()
            ?? AppSettings.defaultValue.keyboardAccessibilityOverridesEnabled
        let appSettings = AppSettings(
            keyboardAccessibilityOverridesEnabled: migratedKeyboardOverride
        )

        writeCodableSettings(appSettings, to: url, label: "app settings")
    }

    static func ensureDefaultEffectsComposerSettingsFileExists() {
        let fm = FileManager.default
        let url = defaultEffectsComposerSettingsURL
        guard !fm.fileExists(atPath: url.path) else { return }
        writeCodableSettings(EffectsComposerSettings.defaultValue, to: url, label: "effects composer settings")
    }

    static func ensureDefaultSettingsFilesExist() {
        ensureDefaultStudioSettingsFileExists()
        ensureDefaultAppSettingsFileExists()
        ensureDefaultEffectsComposerSettingsFileExists()
    }

    /// Ensures a valid, decodable settings file exists at the provided URL.
    /// - If missing: copies `bundledURL` if available, otherwise writes `defaultSettings`.
    /// - If present but invalid: attempts a targeted repair for common schema issues, otherwise backs up and rewrites.
    static func ensureSettingsFileExists(
        at url: URL,
        bundledURL: URL?,
        defaultSettings: StudioSettings
    ) {
        let fm = FileManager.default

        // Ensure parent directory exists
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }

        // Create file if missing
        if !fm.fileExists(atPath: url.path) {
            if let bundledURL {
                do {
                    try fm.copyItem(at: bundledURL, to: url)
                    print("Copied bundled default settings to \(url.path)")
                } catch {
                    print("Failed to copy default settings to \(url.path): \(error)")
                }
            }

            if !fm.fileExists(atPath: url.path) {
                writeSettings(defaultSettings, to: url)
                return
            }
        }

        // Validate + normalize
        do {
            let data = try Data(contentsOf: url)
            _ = try JSONDecoder().decode(StudioSettings.self, from: data)
            return
        } catch {
            // Try repairing common issues (notably mixed-type `sources` dictionaries).
            if let repaired = repairSettingsFile(at: url),
               let repairedData = try? stableJSONEncoder().encode(repaired) {
                do {
                    try repairedData.write(to: url, options: .atomic)
                    print("Repaired settings JSON at \(url.path)")
                    return
                } catch {
                    // Fall through to backup + rewrite.
                }
            }

            backupInvalidSettingsFile(at: url)
            writeSettings(defaultSettings, to: url)
        }
    }

    private static func writeSettings(_ settings: StudioSettings, to url: URL) {
        do {
            let data = try stableJSONEncoder().encode(settings)
            try data.write(to: url, options: .atomic)
            print("Wrote default settings to \(url.path)")
        } catch {
            print("Failed to write default settings to \(url.path): \(error)")
        }
    }

    private static func writeCodableSettings<T: Codable>(_ settings: T, to url: URL, label: String) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }

        do {
            let data = try stableJSONEncoder().encode(settings)
            try data.write(to: url, options: .atomic)
            print("Wrote default \(label) to \(url.path)")
        } catch {
            print("Failed to write default \(label) to \(url.path): \(error)")
        }
    }

    private static func keyboardAccessibilityOverrideFromStudioSettings() -> Bool? {
        guard let data = try? Data(contentsOf: defaultStudioSettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any],
              let value = dict["keyboardAccessibilityOverridesEnabled"] as? Bool else {
            return nil
        }
        return value
    }

    private static func stableJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Attempts to repair a settings file that can't decode under the current schema.
    /// Returns a decoded `StudioSettings` if repair succeeds; otherwise nil.
    private static func repairSettingsFile(at url: URL) -> StudioSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        // If it decodes, no repair needed.
        if let decoded = try? JSONDecoder().decode(StudioSettings.self, from: data) {
            return decoded
        }

        // Attempt JSON-level normalization of the `sources` field when it is a dictionary
        // with mixed string/array values (legacy/bundled formats).
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              var dict = obj as? [String: Any] else {
            return nil
        }

        if let sourcesAny = dict["sources"] as? [String: Any] {
            var normalized: [String: [String]] = [:]
            var didConvertAny = false

            for (key, value) in sourcesAny {
                if let s = value as? String {
                    normalized[key] = [s]
                    didConvertAny = true
                } else if let arr = value as? [String] {
                    normalized[key] = arr
                    didConvertAny = true
                }
            }

            if didConvertAny {
                dict["sources"] = normalized
            }
        }

        guard let normalizedData = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let repaired = try? JSONDecoder().decode(StudioSettings.self, from: normalizedData) else {
            return nil
        }

        return repaired
    }

    private static func backupInvalidSettingsFile(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let ts = formatter.string(from: Date())
        let stem = url.deletingPathExtension().lastPathComponent
        let backupName = "\(stem).invalid-\(ts).json"
        let backupURL = url.deletingLastPathComponent().appendingPathComponent(backupName)

        do {
            if fm.fileExists(atPath: backupURL.path) {
                try fm.removeItem(at: backupURL)
            }
            try fm.moveItem(at: url, to: backupURL)
            print("Backed up invalid settings to \(backupURL.path)")
        } catch {
            print("Failed to back up invalid settings at \(url.path): \(error)")
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

    static func installAutomatorQuickAction() {
        let fm = FileManager.default

        // Name must match the resource in your bundle (without extension).
        // From your screenshot: AddToHypnographSourcesAction.workflow
        let workflowName = "Add To Hypnograph Sources"

        guard let bundledWorkflowURL = Bundle.main.url(
            forResource: workflowName,
            withExtension: "workflow"
        ) else {
            print("⚠️ Could not find bundled Automator workflow '\(workflowName).workflow'")
            return
        }

        let destination = userServicesDirectory.appendingPathComponent("\(workflowName).workflow")

        do {
            if fm.fileExists(atPath: destination.path) {
                // Overwrite existing so updates propagate
                try fm.removeItem(at: destination)
            }

            try fm.copyItem(at: bundledWorkflowURL, to: destination)
            print("Installed Automator Quick Action at \(destination.path)")

            // Optional: reveal it
            // NSWorkspace.shared.activateFileViewerSelecting([destination])

        } catch {
            print("Failed to install Automator Quick Action: \(error)")
        }
    }
}
