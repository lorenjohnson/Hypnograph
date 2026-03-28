//
//  EffectsComposer.swift
//  Hypnograph
//

import SwiftUI

struct EffectsComposer: View {
    @ObservedObject private var state: HypnographState
    @ObservedObject private var settingsStore: EffectsComposerSettingsStore

    private let dependencies: EffectsComposerDependencies

    init(
        state: HypnographState,
        settingsStore: EffectsComposerSettingsStore,
        dependencies: EffectsComposerDependencies = .live
    ) {
        self.state = state
        self.settingsStore = settingsStore
        self.dependencies = dependencies
    }

    var body: some View {
        EffectsComposerView(
            state: state,
            settingsStore: settingsStore,
            dependencies: dependencies
        )
    }
}
