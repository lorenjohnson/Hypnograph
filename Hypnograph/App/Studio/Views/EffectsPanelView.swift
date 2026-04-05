import SwiftUI
import HypnoCore

struct EffectsPanelView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio
    @ObservedObject var effectsSession: EffectsSession

    var body: some View {
        EffectChainLibraryView(
            state: state,
            main: main,
            session: effectsSession
        )
        .padding(12)
        .background(Color.black.opacity(0.96).ignoresSafeArea())
    }
}
