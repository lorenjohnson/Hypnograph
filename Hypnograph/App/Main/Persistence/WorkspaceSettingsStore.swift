//
//  WorkspaceSettingsStore.swift
//  Hypnograph
//
//  PersistentStore subclass for app settings.
//  Provides debounced auto-save, dirty tracking, and reactive updates.
//

import Foundation
import HypnoCore

/// WorkspaceSettings store backed by PersistentStore for automatic persistence.
@MainActor
final class WorkspaceSettingsStore: PersistentStore<WorkspaceSettings> {

    /// Create a settings store with the default settings file location
    convenience init() {
        self.init(fileURL: Environment.defaultWorkspaceSettingsURL)
    }

    /// Create a settings store backed by a specific file URL
    override init(fileURL: URL, default defaultValue: WorkspaceSettings) {
        super.init(fileURL: fileURL, default: defaultValue)
    }

    /// Convenience init that loads from URL or uses defaults
    convenience init(fileURL: URL) {
        self.init(fileURL: fileURL, default: WorkspaceSettings.defaultValue)
    }
}
