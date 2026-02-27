//
//  Dependencies.swift
//  Hypnograph
//

import Foundation

struct EffectsStudioDependencies {
    var runtimeEffectsService: RuntimeEffectsService
    var metalRenderService: MetalRenderService

    @MainActor
    func makeViewModel(_ settingsStore: EffectsStudioSettingsStore) -> EffectsStudioViewModel {
        EffectsStudioViewModel(
            settingsStore: settingsStore,
            runtimeEffectsService: runtimeEffectsService,
            metalRenderService: metalRenderService
        )
    }

    static let live = EffectsStudioDependencies(
        runtimeEffectsService: .live,
        metalRenderService: .live
    )
}
