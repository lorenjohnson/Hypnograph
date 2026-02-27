//
//  Dependencies.swift
//  Hypnograph
//

import Foundation

struct EffectsStudioDependencies {
    var runtimeEffectsService: RuntimeEffectsService
    var metalRenderService: MetalRenderService
    var sourcePlaybackService: SourcePlaybackService

    @MainActor
    func makeViewModel(_ settingsStore: EffectsStudioSettingsStore) -> EffectsStudioViewModel {
        EffectsStudioViewModel(
            settingsStore: settingsStore,
            runtimeEffectsService: runtimeEffectsService,
            metalRenderService: metalRenderService,
            sourcePlaybackService: sourcePlaybackService
        )
    }

    static let live = EffectsStudioDependencies(
        runtimeEffectsService: .live,
        metalRenderService: .live,
        sourcePlaybackService: .live
    )
}
