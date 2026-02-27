//
//  Dependencies.swift
//  Hypnograph
//

import Foundation

struct EffectsStudioDependencies {
    var runtimeEffectsService: RuntimeEffectsService

    @MainActor
    func makeViewModel(_ settingsStore: EffectsStudioSettingsStore) -> EffectsStudioViewModel {
        EffectsStudioViewModel(
            settingsStore: settingsStore,
            runtimeEffectsService: runtimeEffectsService
        )
    }

    static let live = EffectsStudioDependencies(
        runtimeEffectsService: .live
    )
}
