//
//  Dependencies.swift
//  Hypnograph
//

import Foundation

struct EffectsComposerDependencies {
    var runtimeEffectsService: RuntimeEffectsService
    var metalRenderService: MetalRenderService
    var sourcePlaybackService: SourcePlaybackService
    var makePanelHostService: @MainActor () -> ComposerPanelHostService
    var makeTabKeyMonitorService: @MainActor () -> EffectsComposerTabKeyMonitorService

    @MainActor
    func makeViewModel(_ settingsStore: EffectsComposerSettingsStore) -> EffectsComposerViewModel {
        EffectsComposerViewModel(
            settingsStore: settingsStore,
            runtimeEffectsService: runtimeEffectsService,
            metalRenderService: metalRenderService,
            sourcePlaybackService: sourcePlaybackService
        )
    }

    static let live = EffectsComposerDependencies(
        runtimeEffectsService: .live,
        metalRenderService: .live,
        sourcePlaybackService: .live,
        makePanelHostService: { ComposerPanelHostService() },
        makeTabKeyMonitorService: { EffectsComposerTabKeyMonitorService() }
    )
}
