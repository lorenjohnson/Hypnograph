//
//  EffectsComposerSettingsStore.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
final class EffectsComposerSettingsStore: PersistentStore<EffectsComposerSettings> {

    convenience init() {
        self.init(fileURL: Environment.defaultEffectsComposerSettingsURL)
    }

    override init(fileURL: URL, default defaultValue: EffectsComposerSettings) {
        super.init(fileURL: fileURL, default: defaultValue)
    }

    convenience init(fileURL: URL) {
        self.init(fileURL: fileURL, default: EffectsComposerSettings.defaultValue)
    }
}
