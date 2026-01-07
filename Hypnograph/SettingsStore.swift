//
//  SettingsStore.swift
//  Hypnograph
//
//  PersistentStore subclass for app settings.
//  Provides debounced auto-save, dirty tracking, and reactive updates.
//

import Foundation
import HypnoCore

/// Settings store backed by PersistentStore for automatic persistence.
@MainActor
final class SettingsStore: PersistentStore<Settings> {

    /// Create a settings store with the default settings file location
    convenience init() {
        self.init(fileURL: Environment.defaultSettingsURL)
    }

    /// Create a settings store backed by a specific file URL
    override init(fileURL: URL, default defaultValue: Settings) {
        super.init(fileURL: fileURL, default: defaultValue)
    }

    /// Convenience init that loads from URL or uses defaults
    convenience init(fileURL: URL) {
        // Try to load existing settings, fall back to defaults
        let defaultSettings = Settings(
            outputFolder: "~/Movies/Hypnograph/renders",
            sources: .array(["~/Movies/Hypnograph/sources"])
        )
        self.init(fileURL: fileURL, default: defaultSettings)
    }
}
