//
//  EffectsStudioSettingsStore.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
final class EffectsStudioSettingsStore: PersistentStore<EffectsStudioSettings> {

    convenience init() {
        self.init(fileURL: Environment.defaultEffectsStudioSettingsURL)
    }

    override init(fileURL: URL, default defaultValue: EffectsStudioSettings) {
        super.init(fileURL: fileURL, default: defaultValue)
    }

    convenience init(fileURL: URL) {
        self.init(fileURL: fileURL, default: EffectsStudioSettings.defaultValue)
    }
}
