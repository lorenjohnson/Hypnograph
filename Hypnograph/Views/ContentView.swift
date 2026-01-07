import SwiftUI
import AVFoundation
import Combine
import PhotosUI
import HypnoCore
import HypnoUI

struct ContentView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream

    /// Use shared view model from state for controller/keyboard navigation
    private var effectsEditorViewModel: EffectsEditorViewModel {
        state.effectsEditorViewModel
    }

    private var soloIndicatorText: String? {
        // Only show during flash solo (when navigating sources in montage mode)
        guard dream.activePlayer.effectManager.flashSoloIndex != nil,
              !dream.activePlayer.sources.isEmpty else {
            return nil
        }
        return "\(dream.activePlayer.currentSourceIndex + 1)/\(dream.activePlayer.sources.count)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Dream display
            dream.makeDisplayView()
                .ignoresSafeArea()

            // LIVE indicator - top left, only in Live mode
            if dream.isLiveMode {
                Text("LIVE")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6).cornerRadius(6))
                    .padding(.top, 12)
                    .padding(.leading, 12)
            }

            // HUD and Hypnogram List - top left (below LIVE if visible)
            VStack(alignment: .leading, spacing: 8) {
                if state.windowState.isVisible("hud") {
                    HUDView(
                        state: state,
                        dream: dream
                    )
                }

                if state.windowState.isVisible("hypnogramList") {
                    HypnogramListView(
                        store: HypnogramStore.shared,
                        onLoad: { entry in
                            guard let recipe = HypnogramStore.shared.loadRecipe(from: entry) else {
                                AppNotifications.show("Failed to load recipe", flash: true)
                                return
                            }
                            dream.loadRecipe(recipe)
                            AppNotifications.show("Loaded: \(entry.name)", flash: true)
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.top, dream.isLiveMode ? 56 : 12)
            .padding(.leading, 12)
            .animation(.easeInOut(duration: 0.2), value: state.windowState.isVisible("hypnogramList"))
        }
        .overlay(alignment: .bottomLeading) {
            // Player Settings - bottom left
            if state.windowState.isVisible("playerSettings") {
                PlayerSettingsView(
                    player: dream.activePlayer,
                    dream: dream,
                    onClose: {
                        state.windowState.set("playerSettings", visible: false)
                    }
                )
                .padding(.leading, 12)
                .padding(.bottom, 12)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: state.windowState.isVisible("playerSettings"))
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
        .overlay(alignment: .topTrailing) {
            // Right-side panels: Effects editor (top-aligned) and Live preview (bottom)
            VStack(spacing: 0) {
                if state.windowState.isVisible("effectsEditor") {
                    EffectsEditorView(viewModel: effectsEditorViewModel, state: state, dream: dream)
                        .padding(.bottom, state.windowState.isVisible("livePreview") ? 12 : 0)
                        .transition(.move(edge: .trailing))
                }

                Spacer(minLength: 0)

                if state.windowState.isVisible("livePreview") {
                    LivePreviewPanel(
                        livePlayer: dream.livePlayer,
                        onClose: {
                            state.windowState.set("livePreview", visible: false)
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
            .animation(.easeInOut(duration: 0.2), value: state.windowState.isVisible("effectsEditor"))
            .animation(.easeInOut(duration: 0.2), value: state.windowState.isVisible("livePreview"))
        }
        .appNotifications()
        .background(Color.black)
        .sheet(isPresented: $state.showPhotosPicker) {
            PhotosPickerSheet(
                isPresented: $state.showPhotosPicker,
                preselectedIdentifiers: state.customPhotosAssetIds,
                onSelection: { identifiers in
                    state.setCustomPhotosAssets(identifiers)
                    if identifiers.isEmpty {
                        AppNotifications.shared.show("Custom Selection cleared", flash: true)
                    } else {
                        if !state.isLibraryActive(key: ApplePhotosLibraryKeys.photosCustom) {
                            state.toggleLibrary(key: ApplePhotosLibraryKeys.photosCustom)
                        }
                        AppNotifications.shared.show("Custom Selection: \(identifiers.count) items", flash: true)
                    }
                }
            )
        }
    }
}
