//
//  AppSettingsStore.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
final class AppSettingsStore: PersistentStore<AppSettings> {

    convenience init() {
        self.init(fileURL: Environment.defaultAppSettingsURL)
    }

    override init(fileURL: URL, default defaultValue: AppSettings) {
        super.init(fileURL: fileURL, default: defaultValue)
    }

    convenience init(fileURL: URL) {
        self.init(fileURL: fileURL, default: AppSettings.defaultValue)
    }
}
