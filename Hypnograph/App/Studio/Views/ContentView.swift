import SwiftUI
import AVFoundation
import Combine
import PhotosUI
import Photos
import HypnoCore
import HypnoUI

struct ContentView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio
    @ObservedObject private var externalLoadHarness = ExternalMediaLoadHarness.shared
    @StateObject private var panelHostService = StudioWindowHostService()
    @State private var isPlayerControlsVisible: Bool = true

    private var clipTrimContexts: [ClipTrimContext] {
        let layers = main.activePlayer.layers
        guard !layers.isEmpty else { return [] }

        let maxSelectionForClip = max(0.1, main.activePlayer.targetDuration.seconds)

        func makeContext(layer: HypnogramLayer, index: Int) -> ClipTrimContext? {
            guard layer.mediaClip.file.mediaKind == .video else { return nil }

            let total = max(0.1, layer.mediaClip.file.duration.seconds)
            let start = max(0, min(layer.mediaClip.startTime.seconds, total))
            let maxSelection = max(0.1, min(maxSelectionForClip, total))
            let selectedDuration = min(layer.mediaClip.duration.seconds, maxSelection, total - start)
            let end = max(start + 0.1, min(start + selectedDuration, total))

            return ClipTrimContext(
                layerIndex: index,
                fileID: layer.mediaClip.file.id,
                source: layer.mediaClip.file.source,
                clipLabel: layerTitle(for: layer),
                totalDurationSeconds: total,
                maxSelectionDurationSeconds: maxSelection,
                selectedRangeSeconds: start...end
            )
        }

        if main.activePlayer.currentSourceIndex == -1 {
            return layers.enumerated().compactMap { index, layer in
                makeContext(layer: layer, index: index)
            }
        }

        let index = main.activePlayer.currentSourceIndex
        guard index >= 0, index < layers.count else { return [] }
        guard let context = makeContext(layer: layers[index], index: index) else { return [] }
        return [context]
    }

    private func layerTitle(for layer: HypnogramLayer) -> String {
        switch layer.mediaClip.file.source {
        case .url(let url):
            return url.lastPathComponent
        case .external(let identifier):
            return photosFilename(for: identifier) ?? "Photos Item"
        }
    }

    private func photosFilename(for identifier: String) -> String? {
        guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)

        if let resource = resources.first(where: { $0.type == .pairedVideo || $0.type == .video || $0.type == .photo }) {
            return resource.originalFilename
        }
        return resources.first?.originalFilename
    }

    private var topRightIndicator: (text: String, color: Color)? {
        // LIVE indicator (same placement/size as the layer indicator)
        if main.isLiveMode {
            return ("LIVE", .red)
        }

        if let clipText = main.clipHistoryIndicatorText {
            return (clipText, .blue)
        }

        // Layer indicators: show during flash solo (1-9 hold) or global hold (`) while global effects are suspended.
        guard !main.activePlayer.layers.isEmpty else { return nil }

        if main.activePlayer.effectManager.flashSoloIndex != nil {
            return ("\(main.activePlayer.currentSourceIndex + 1)/\(main.activePlayer.layers.count)", .red)
        }

        if main.activePlayer.isGlobalEffectSuspended {
            return ("GLOBAL/\(main.activePlayer.layers.count)", .red)
        }

        return nil
    }

    private var shouldAutoHideCursor: Bool {
        if main.isLiveMode {
            guard let player = main.livePlayer.activeAVPlayer else { return false }
            return player.rate != 0
        }

        let clip = main.activePlayer.currentHypnogram
        let hasVideo = clip.layers.contains { $0.mediaClip.file.mediaKind == .video }
        return hasVideo && (main.activePlayer.isPaused == false)
    }

    @ViewBuilder
    private func topRightIndicatorBadge(_ indicator: (text: String, color: Color)) -> some View {
        Text(indicator.text)
            .font(.system(size: 36, weight: .bold))
            .foregroundStyle(indicator.color)
            .padding(.vertical, 14)
            .padding(.leading, 14)
            .padding(.trailing, 28)
    }

    @ViewBuilder
    private var playerControlsOverlay: some View {
        VStack(spacing: 0) {
            if isPlayerControlsVisible {
                PlayerControlsBar(
                    isPaused: main.activePlayer.isPaused,
                    isLoopCurrentClipEnabled: main.isLoopCurrentClipEnabled,
                    currentClipText: main.currentClipIndicatorText,
                    clipLengthSeconds: main.activePlayer.targetDuration.seconds,
                    clipTrimContexts: clipTrimContexts,
                    volume: Binding(
                        get: { Double(main.volume) },
                        set: { main.volume = Float($0) }
                    ),
                    timelinePlaybackRate: main.timelinePlaybackRate,
                    timelinePlaybackControlValue: Binding(
                        get: { main.timelinePlaybackControlValue },
                        set: { main.timelinePlaybackControlValue = $0 }
                    ),
                    isTimelinePlaybackReverse: Binding(
                        get: { main.isTimelinePlaybackReverse },
                        set: { main.isTimelinePlaybackReverse = $0 }
                    ),
                    onPrevious: { main.previousClip() },
                    onPlayPause: { main.togglePause() },
                    onNext: { main.nextClip() },
                    onToggleLoopCurrentClipMode: { main.toggleLoopCurrentClipMode() },
                    onSnapshotCurrent: { main.saveSnapshotImage() },
                    onSaveCurrent: { main.save() },
                    onRenderCurrent: { main.renderAndSaveVideo() },
                    onCommitClipTrimRange: { layerIndex, range in
                        main.setLayerClipRange(
                            sourceIndex: layerIndex,
                            startSeconds: range.lowerBound,
                            endSeconds: range.upperBound,
                            maxDurationSeconds: main.activePlayer.targetDuration.seconds
                        )
                    }
                )
                .frame(maxWidth: 920)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: isPlayerControlsVisible)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Studio display
            main.makeDisplayView()
                .ignoresSafeArea()

            CursorAutoHideView(isEnabled: shouldAutoHideCursor, idleSeconds: 3.0)
                .allowsHitTesting(false)

            MouseIdleVisibilityView(
                isEnabled: true,
                idleSeconds: 3.0,
                startHiddenOnEnable: state.windowState.isCleanScreen,
                activityIgnoreLeftInset: 0,
                activityIgnoreRightInset: 0,
                isVisible: $isPlayerControlsVisible
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
                            main.appendSessionToHistory(session)
                            AppNotifications.show("Loaded: \(entry.name)", flash: true)
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.top, main.isLiveMode ? 56 : 12)
            .padding(.leading, 12)
            .animation(.easeInOut(duration: 0.2), value: state.windowState.isVisible("hypnogramList"))
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if !state.windowState.isCleanScreen && main.isLiveModeAvailable {
                    Picker("", selection: Binding(
                        get: { main.isLiveMode ? 1 : 0 },
                        set: { newValue in
                            if (newValue == 1) != main.isLiveMode {
                                main.toggleLiveMode()
                            }
                        }
                    )) {
                        Text("Edit").tag(0)
                        Text("Live").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                if !state.windowState.isCleanScreen && state.windowState.isVisible("keyboardHints") {
                    KeyboardHintBar()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let loadStatus = externalLoadHarness.status {
                    externalLoadStatusBadge(loadStatus)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
            .animation(.easeInOut(duration: 0.2), value: externalLoadHarness.status)
            .animation(.easeInOut(duration: 0.25), value: state.windowState.isVisible("keyboardHints"))
        }
        .overlay(alignment: .bottom) {
            playerControlsOverlay
        }
        .overlay(alignment: .topTrailing) {
            if let indicator = topRightIndicator {
                topRightIndicatorBadge(indicator)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Right-side panels: Live panel (bottom)
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                if main.isLiveModeAvailable && state.windowState.isVisible("livePreview") {
                    LivePreviewPanel(
                        livePlayer: main.livePlayer,
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
        .background(
            StudioPanelHostBridge(
                hostService: panelHostService,
                showSources: state.windowState.isVisible("sourcesWindow"),
                showNewClips: state.windowState.isVisible("newClipsWindow"),
                showOutputSettings: state.windowState.isVisible("outputSettingsWindow"),
                showComposition: state.windowState.isVisible("compositionWindow"),
                showEffects: state.windowState.isVisible("effectsWindow"),
                sourcesContent: AnyView(
                    SourcesWindowView(state: state, main: main)
                ),
                newClipsContent: AnyView(
                    NewClipsWindowView(state: state, main: main, player: main.activePlayer)
                ),
                outputSettingsContent: AnyView(
                    OutputSettingsWindowView(state: state, main: main, player: main.activePlayer)
                ),
                compositionContent: AnyView(
                    CompositionWindowView(state: state, main: main)
                ),
                effectsContent: AnyView(
                    EffectsWindowView(state: state, main: main, effectsSession: main.effectsLibrarySession)
                )
            )
            .frame(width: 0, height: 0)
        )
        .appNotifications()
        .background(Color.black)
        .onAppear {
            state.windowState.register("sourcesWindow", defaultVisible: false)
            state.windowState.register("newClipsWindow", defaultVisible: true)
            state.windowState.register("outputSettingsWindow", defaultVisible: true)
            state.windowState.register("compositionWindow", defaultVisible: true)
            state.windowState.register("effectsWindow", defaultVisible: true)
            state.windowState.register("keyboardHints", defaultVisible: true)
        }
        .onChange(of: state.windowState.isCleanScreen) { _, isCleanScreen in
            isPlayerControlsVisible = !isCleanScreen
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

    @ViewBuilder
    private func externalLoadStatusBadge(_ status: ExternalMediaLoadHarness.Status) -> some View {
        HStack(spacing: 8) {
            switch status.phase {
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .downloading:
                ProgressView(value: status.progress ?? 0, total: 1)
                    .frame(width: 86)
            case .timeout, .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(status.title)
                    .font(.caption.weight(.semibold))
                if let detail = status.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}
