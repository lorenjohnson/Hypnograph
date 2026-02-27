//
//  EffectsStudio.swift
//  Hypnograph
//

import SwiftUI

struct EffectsStudio: View {
    @ObservedObject private var state: HypnographState
    @ObservedObject private var settingsStore: EffectsStudioSettingsStore

    private let dependencies: EffectsStudioDependencies

    init(
        state: HypnographState,
        settingsStore: EffectsStudioSettingsStore,
        dependencies: EffectsStudioDependencies = .live
    ) {
        self.state = state
        self.settingsStore = settingsStore
        self.dependencies = dependencies
    }

    var body: some View {
        EffectsStudioView(
            state: state,
            settingsStore: settingsStore,
            dependencies: dependencies
        )
    }
}
