import SwiftUI
import AVFoundation
import Combine
import PhotosUI
import HypnoCore
import HypnoUI

struct ContentView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream
    @State private var isRecordDeckVisible: Bool = true

    private var topRightIndicator: (text: String, color: Color)? {
        // LIVE indicator (same placement/size as the layer indicator)
        if dream.isLiveMode {
            return ("LIVE", .red)
        }

        if let clipText = dream.clipHistoryIndicatorText {
            return (clipText, .blue)
        }

        // Layer indicators: show during flash solo (1-9 hold) or global hold (`) while global effects are suspended.
        guard !dream.activePlayer.layers.isEmpty else { return nil }

        if dream.activePlayer.effectManager.flashSoloIndex != nil {
            return ("\(dream.activePlayer.currentSourceIndex + 1)/\(dream.activePlayer.layers.count)", .red)
        }

        if dream.activePlayer.isGlobalEffectSuspended {
            return ("GLOBAL/\(dream.activePlayer.layers.count)", .red)
        }

        return nil
    }

    private var shouldAutoHideCursor: Bool {
        if dream.isLiveMode {
            guard let player = dream.livePlayer.activeAVPlayer else { return false }
            return player.rate != 0
        }

        let clip = dream.activePlayer.currentHypnogram
        let hasVideo = clip.layers.contains { $0.mediaClip.file.mediaKind == .video }
        return hasVideo && (dream.activePlayer.isPaused == false)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Dream display
            dream.makeDisplayView()
                .ignoresSafeArea()

            CursorAutoHideView(isEnabled: shouldAutoHideCursor, idleSeconds: 3.0)
                .allowsHitTesting(false)

            MouseIdleVisibilityView(
                isEnabled: shouldAutoHideCursor,
                idleSeconds: 3.0,
                isVisible: $isRecordDeckVisible
            )
            .allowsHitTesting(false)

            // HUD and Hypnogram List - top left (below LIVE if visible)
            VStack(alignment: .leading, spacing: 8) {
                if state.windowState.isVisible("hypnogramList") {
                    HypnogramListView(
                        store: HypnogramStore.shared,
                        onLoad: { entry in
                            guard let session = HypnogramStore.shared.loadSession(from: entry) else {
                                AppNotifications.show("Failed to load recipe", flash: true)
                                return
                            }
                            dream.appendSessionToHistory(session)
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
        .overlay(alignment: .center) {
            HStack(spacing: 0) {
                if state.windowState.isVisible("leftSidebar") {
                    LeftSidebarView(state: state, dream: dream, player: dream.activePlayer)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                if state.windowState.isVisible("rightSidebar") {
                    RightSidebarView(state: state, dream: dream, effectsSession: dream.effectsLibrarySession)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(12)
            .animation(.easeInOut(duration: 0.25), value: state.windowState.isVisible("leftSidebar"))
            .animation(.easeInOut(duration: 0.25), value: state.windowState.isVisible("rightSidebar"))
        }
        .overlay(alignment: .top) {
            if !state.windowState.isCleanScreen && dream.isLiveModeAvailable {
                Picker("", selection: Binding(
                    get: { dream.isLiveMode ? 1 : 0 },
                    set: { newValue in
                        if (newValue == 1) != dream.isLiveMode {
                            dream.toggleLiveMode()
                        }
                    }
                )) {
                    Text("Preview").tag(0)
                    Text("Live").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .padding(.top, 12)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if !state.windowState.isCleanScreen && isRecordDeckVisible {
                    RecordDeckBar(
                        isPaused: dream.activePlayer.isPaused,
                        isRecording: dream.isRecording,
                        rangeText: dream.recordingRangeDisplayText,
                        onPrevious: { dream.previousClip() },
                        onPlayPause: { dream.togglePause() },
                        onNext: { dream.nextClip() },
                        onRecordToggle: { dream.toggleRecording() },
                        onSaveRecording: { dream.saveRecording() },
                        onRenderRecording: { dream.renderRecording() }
                    )
                    .frame(maxWidth: 720)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if state.windowState.isVisible("keyboardHints") {
                    KeyboardHintBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 12)
            .animation(.easeInOut(duration: 0.25), value: state.windowState.isVisible("keyboardHints"))
            .animation(.easeInOut(duration: 0.2), value: isRecordDeckVisible)
        }
        .overlay(alignment: .topTrailing) {
            if let indicator = topRightIndicator {
                Text(indicator.text)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(indicator.color)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                    .padding(.leading, 14)
                    .padding(.trailing, 28)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Right-side panels: Live preview (bottom)
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                if dream.isLiveModeAvailable && state.windowState.isVisible("livePreview") {
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
            .animation(.easeInOut(duration: 0.2), value: state.windowState.isVisible("livePreview"))
        }
        .appNotifications()
        .background(Color.black)
        .onAppear {
            state.windowState.register("leftSidebar", defaultVisible: true)
            state.windowState.register("rightSidebar", defaultVisible: true)
            state.windowState.register("keyboardHints", defaultVisible: true)
        }
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
