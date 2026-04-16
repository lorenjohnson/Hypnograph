import SwiftUI

struct PlayerView: View {
    @ObservedObject var main: Studio

    var body: some View {
        Group {
            if main.isLiveMode {
                LivePlayerScreen(livePlayer: main.livePlayer)
            } else if main.needsPlayerPreparation {
                if main.state.library.assetCount == 0 {
                    NoSourcesView(state: main.state, main: main)
                } else {
                    Color.black
                        .task(id: playerPreparationTaskID) {
                            main.preparePlayerIfNeeded()
                        }
                }
            } else {
                currentPlayerSurface
            }
        }
    }

    @ViewBuilder
    private var currentPlayerSurface: some View {
        let composition = main.currentComposition

        if main.compositionRequiresPhotosAccess(composition) && !main.state.photosAuthorizationStatus.canRead {
            PhotosAccessRequiredView(state: main.state, main: main)
        } else if !main.compositionHasReachableSources(composition) {
            CompositionSourcesUnavailableView(main: main)
        } else if main.activePlayer.currentCompositionLoadFailure?.compositionID == composition.id {
            CompositionSourcesUnavailableView(main: main)
        } else {
            PlayerRendererView(main: main)
        }
    }

    private var playerPreparationTaskID: String {
        "\(main.hypnogram.compositions.count)-\(main.currentCompositionIndex)-\(main.currentLayers.count)"
    }
}
