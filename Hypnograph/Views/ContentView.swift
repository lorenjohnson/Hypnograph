import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    @ObservedObject var state: HypnographState
    var renderQueue: RenderQueue  // Not @ObservedObject - we don't want to trigger view updates
    @ObservedObject var dream: Dream
    @ObservedObject var divine: Divine

    private var soloIndicatorText: String? {
        // Only Dream shows solo indicator
        if state.currentModuleType == .dream, !state.sources.isEmpty {
            return "\(state.currentSourceIndex + 1)/\(state.sources.count)"
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Module-specific display
            switch state.currentModuleType {
            case .dream:
                dream.makeDisplayView(state: state, renderQueue: renderQueue)
                    .ignoresSafeArea()
            case .divine:
                divine.makeDisplayView()
                    .ignoresSafeArea()
            }

            // HUD
            if state.isHUDVisible {
                HUDView(
                    state: state,
                    renderQueue: renderQueue,
                    dream: dream,
                    divine: divine
                )
                .padding(.top, 12)
                .padding(.leading, 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let text = soloIndicatorText {
                Text(text)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .background(Color.black)
    }
}

