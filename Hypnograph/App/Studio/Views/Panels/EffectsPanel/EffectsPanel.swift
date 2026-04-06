import SwiftUI
import HypnoCore

struct EffectsPanel: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    var body: some View {
        EffectChainLibraryView(
            state: state,
            main: main,
            session: main.effectsLibrarySession
        )
        .padding(12)
        .background(Color.black.opacity(0.96).ignoresSafeArea())
    }
}
