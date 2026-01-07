//
//  DivineSettingsStore.swift
//  Divine
//
//  PersistentStore subclass for Divine app settings.
//

import Foundation
import HypnoCore

/// Settings store backed by PersistentStore for automatic persistence.
@MainActor
final class DivineSettingsStore: PersistentStore<DivineSettings> {

    /// Create a settings store with the default settings file location
    convenience init() {
        self.init(fileURL: DivineEnvironment.settingsURL)
    }

    /// Create a settings store backed by a specific file URL
    convenience init(fileURL: URL) {
        self.init(fileURL: fileURL, default: DivineSettings())
    }
}
