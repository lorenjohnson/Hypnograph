//
//  StudioSettingsStore.swift
//  Hypnograph
//
//  PersistentStore subclass for studio settings.
//  Provides debounced auto-save, dirty tracking, and reactive updates.
//

import Foundation
import HypnoCore

/// StudioSettings store backed by PersistentStore for automatic persistence.
@MainActor
final class StudioSettingsStore: PersistentStore<StudioSettings> {

    /// Create a settings store with the default studio settings file location.
    convenience init() {
        self.init(fileURL: Environment.defaultStudioSettingsURL)
    }

    /// Create a settings store backed by a specific file URL
    override init(fileURL: URL, default defaultValue: StudioSettings) {
        super.init(fileURL: fileURL, default: defaultValue)
    }

    /// Convenience init that loads from URL or uses defaults
    convenience init(fileURL: URL) {
        self.init(fileURL: fileURL, default: StudioSettings.defaultValue)
    }
}
