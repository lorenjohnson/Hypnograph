//
//  Dependencies.swift
//  Hypnograph
//

import Foundation

struct EffectsStudioDependencies {
    var makeViewModel: @MainActor (_ settingsStore: EffectsStudioSettingsStore) -> EffectsStudioViewModel

    static let live = EffectsStudioDependencies(
        makeViewModel: { settingsStore in
            EffectsStudioViewModel(settingsStore: settingsStore)
        }
    )
}
