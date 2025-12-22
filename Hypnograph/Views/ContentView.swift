import SwiftUI
import AVFoundation
import Combine
import PhotosUI

struct ContentView: View {
    @ObservedObject var state: HypnographState
    var renderQueue: RenderQueue  // Not @ObservedObject - we don't want to trigger view updates
    @ObservedObject var dream: Dream
    @ObservedObject var divine: Divine

    /// Use shared view model from state for controller/keyboard navigation
    private var effectsEditorViewModel: EffectsEditorViewModel {
        state.effectsEditorViewModel
    }

    private var soloIndicatorText: String? {
        // Only show during flash solo (when navigating sources in montage mode)
        guard state.renderHooks.flashSoloIndex != nil, state.currentModuleType == .dream, !state.sources.isEmpty else {
            return nil
        }
        return "\(state.currentSourceIndex + 1)/\(state.sources.count)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Module-specific display
            switch state.currentModuleType {
            case .dream:
                dream.makeDisplayView()
                    .ignoresSafeArea()
            case .divine:
                divine.makeDisplayView()
                    .ignoresSafeArea()
            }

            // HUDs
            VStack(alignment: .leading, spacing: 8) {
                if state.isHUDVisible {
                    HUDView(
                        state: state,
                        dream: dream,
                        divine: divine
                    )
                }

                if state.isInfoVisible {
                    InfoHUD(state: state)
                }
            }
            .padding(.top, 12)
            .padding(.leading, 12)
        }
        .overlay(alignment: .topTrailing) {
            if let text = soloIndicatorText {
                Text(text)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .overlay(alignment: .trailing) {
            if state.isEffectsEditorVisible {
                EffectsEditorView(viewModel: effectsEditorViewModel, state: state)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing))
                    .animation(.easeInOut(duration: 0.2), value: state.isEffectsEditorVisible)
            }
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
                        // Activate the custom selection library if it has items
                        if !state.isLibraryActive(key: HypnographState.photosCustomKey) {
                            state.toggleLibrary(key: HypnographState.photosCustomKey)
                        }
                        AppNotifications.shared.show("Custom Selection: \(identifiers.count) items", flash: true)
                    }
                }
            )
        }
    }
}

