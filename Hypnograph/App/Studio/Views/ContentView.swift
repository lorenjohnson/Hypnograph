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
    @ObservedObject private var windows: WindowStateController
    @ObservedObject private var appSettingsStore: AppSettingsStore
    @ObservedObject private var externalLoadHarness = ExternalMediaLoadHarness.shared
    @StateObject private var windowHostService = WindowHostService()
    @State private var panelsCurrentlyAutoHidden = false
    @State private var completedDownloadIdentifiersThisLoad: Set<String> = []
    @State private var previouslyVisibleDownloadIdentifiers: Set<String> = []

    private static let hidePanelsNowNotification = Notification.Name("StudioHidePanelsNow")
    private static let showPanelsNowNotification = Notification.Name("StudioShowPanelsNow")

    init(state: HypnographState, main: Studio) {
        self.state = state
        self.main = main
        _windows = ObservedObject(initialValue: main.windows)
        _appSettingsStore = ObservedObject(initialValue: state.appSettingsStore)
    }

    private var clipTrimContexts: [ClipTrimContext] {
        let layers = main.activePlayer.layers
        guard !layers.isEmpty else { return [] }

        func makeContext(layer: Layer, index: Int) -> ClipTrimContext? {
            guard layer.mediaClip.file.mediaKind == .video else { return nil }

            let total = max(0.1, layer.mediaClip.file.duration.seconds)
            let start = max(0, min(layer.mediaClip.startTime.seconds, total))
            let maxSelection = total
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

        if main.activePlayer.currentLayerIndex == -1 {
            return layers.enumerated().compactMap { index, layer in
                makeContext(layer: layer, index: index)
            }
        }

        let index = main.activePlayer.currentLayerIndex
        guard index >= 0, index < layers.count else { return [] }
        guard let context = makeContext(layer: layers[index], index: index) else { return [] }
        return [context]
    }

    private func layerTitle(for layer: Layer) -> String {
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

        if shouldShowPersistentHistoryIndicator {
            return (main.currentHistoryPositionText, .blue)
        }

        if let clipText = main.historyIndicatorText {
            return (clipText, .blue)
        }

        // Layer indicators: show during flash solo (1-9 hold) or global hold (`) while global effects are suspended.
        guard !main.activePlayer.layers.isEmpty else { return nil }

        if main.activePlayer.effectManager.flashSoloIndex != nil {
            return ("\(main.activePlayer.currentLayerIndex + 1)/\(main.activePlayer.layers.count)", .red)
        }

        if main.activePlayer.isGlobalEffectSuspended {
            return ("GLOBAL/\(main.activePlayer.layers.count)", .red)
        }

        return nil
    }

    private var shouldShowPersistentHistoryIndicator: Bool {
        guard !panelsCurrentlyAutoHidden else { return false }
        return main.isViewingHistoryComposition
    }

    private var shouldAutoHideCursor: Bool {
        if main.isLiveMode {
            guard let player = main.livePlayer.activeAVPlayer else { return false }
            return player.rate != 0
        }

        let clip = main.activePlayer.currentComposition
        let hasVideo = clip.layers.contains { $0.mediaClip.file.mediaKind == .video }
        return hasVideo && (main.activePlayer.isPaused == false)
    }

    private struct CurrentCompositionDownloadRow: Identifiable, Equatable {
        let id: String
        let identifier: String
        let title: String
        let subtitle: String
        let progress: Double
    }

    private var currentCompositionDownloadRows: [CurrentCompositionDownloadRow] {
        guard !main.isLiveMode else { return [] }
        guard main.activePlayer.isPrimaryCompositionLoadInFlight else { return [] }

        let composition = main.activePlayer.currentComposition
        guard !composition.layers.isEmpty else { return [] }

        let latestDownloadsByIdentifier = Dictionary(
            grouping: externalLoadHarness.activeDownloads,
            by: \.localIdentifier
        ).compactMapValues { $0.last }

        return composition.layers.enumerated().compactMap { index, layer -> CurrentCompositionDownloadRow? in
            guard case .external(let identifier) = layer.mediaClip.file.source,
                  let status = latestDownloadsByIdentifier[identifier] else {
                return nil
            }

            return CurrentCompositionDownloadRow(
                id: "\(identifier)-\(index)",
                identifier: identifier,
                title: layer.mediaClip.file.displayName,
                subtitle: status.mediaLabel,
                progress: status.progress
            )
        }
    }

    private var visibleCurrentCompositionDownloadRows: [CurrentCompositionDownloadRow] {
        currentCompositionDownloadRows.filter { row in
            !completedDownloadIdentifiersThisLoad.contains(row.identifier)
        }
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

    private var playerControlsContent: some View {
        PlayerControlsBar(
            isPaused: main.activePlayer.isPaused,
            isLoopCurrentCompositionEnabled: main.isLoopCurrentCompositionEnabled,
            currentCompositionText: main.currentCompositionIndicatorText,
            compositionLengthSeconds: main.activePlayer.targetDuration.seconds,
            clipTrimContexts: clipTrimContexts,
            volume: Binding(
                get: { Double(main.volume) },
                set: { main.volume = Float($0) }
            ),
            onPrevious: { main.previousComposition() },
            onPlayPause: { main.togglePause() },
            onNext: { main.nextComposition() },
            onToggleLoopCurrentCompositionMode: { main.toggleLoopCurrentCompositionMode() },
            onSnapshotCurrent: { main.saveSnapshotImage() },
            onSaveCurrent: { main.save() },
            onRenderCurrent: { main.renderAndSaveVideo() },
            onCommitClipTrimRange: { layerIndex, range in
                main.setLayerClipRange(
                    sourceIndex: layerIndex,
                    startSeconds: range.lowerBound,
                    endSeconds: range.upperBound
                )
            }
        )
        .frame(maxWidth: 920)
    }

    private var hypnogramsContent: some View {
        HypnogramListView(
            store: HypnogramStore.shared,
            onLoad: { entry in
                guard let hypnogram = HypnogramStore.shared.loadHypnogram(from: entry) else {
                    AppNotifications.show("Failed to load hypnogram", flash: true)
                    return
                }
                main.appendHypnogramToHistory(hypnogram, sourceURL: entry.sessionURL)
                AppNotifications.show("Loaded: \(entry.name)", flash: true)
            }
        )
    }

    private var playerControlsLayoutSignature: Int {
        clipTrimContexts.count
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Studio display
            main.makeDisplayView()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    windowHostService.hidePanelsForCanvasInteraction()
                }

            CursorAutoHideView(isEnabled: shouldAutoHideCursor, idleSeconds: 3.0)
                .allowsHitTesting(false)

        }
        .overlay(alignment: .top) {
            if main.isLiveModeAvailable {
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
                .padding(.top, 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let indicator = topRightIndicator {
                topRightIndicatorBadge(indicator)
            }
        }
        .overlay {
            if !visibleCurrentCompositionDownloadRows.isEmpty {
                currentCompositionDownloadOverlay(rows: visibleCurrentCompositionDownloadRows)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Right-side panels: Live panel (bottom)
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                if main.isLiveModeAvailable && windows.isWindowVisible("livePreview") {
                    LivePreviewPanel(
                        livePlayer: main.livePlayer,
                        onClose: {
                            windows.setWindowVisible("livePreview", visible: false)
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
            .animation(.easeInOut(duration: 0.2), value: windows.isWindowVisible("livePreview"))
        }
        .background(
            WindowHostBridge(
                hostService: windowHostService,
                showHypnograms: windows.isWindowVisible("hypnogramList"),
                showSources: windows.isWindowVisible("sourcesWindow"),
                showNewClips: windows.isWindowVisible("newClipsWindow"),
                showOutputSettings: windows.isWindowVisible("outputSettingsWindow"),
                showComposition: windows.isWindowVisible("compositionWindow"),
                showEffects: windows.isWindowVisible("effectsWindow"),
                showPlayerControls: true,
                playerControlsLayoutSignature: playerControlsLayoutSignature,
                autoHideWindows: appSettingsStore.value.autoHideWindowsEnabled,
                keyboardAccessibilityOverridesEnabled: appSettingsStore.value.keyboardAccessibilityOverridesEnabled,
                onPanelVisibilityChanged: { windowID, isVisible in
                    windows.setWindowVisible(windowID, visible: isVisible)
                },
                onPanelsAutoHiddenChanged: { isHidden in
                    DispatchQueue.main.async {
                        panelsCurrentlyAutoHidden = isHidden
                        windows.setPanelsHidden(isHidden)
                    }
                },
                hypnogramsContent: AnyView(
                    hypnogramsContent
                ),
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
                ),
                playerControlsContent: AnyView(
                    playerControlsContent
                )
            )
            .frame(width: 0, height: 0)
        )
        .appNotifications()
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: Self.hidePanelsNowNotification)) { _ in
            windowHostService.hidePanelsNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.showPanelsNowNotification)) { _ in
            windowHostService.showPanelsNow()
        }
        .onAppear {
            windows.registerWindow("hypnogramList", defaultVisible: false)
            windows.registerWindow("sourcesWindow", defaultVisible: false)
            windows.registerWindow("newClipsWindow", defaultVisible: true)
            windows.registerWindow("outputSettingsWindow", defaultVisible: true)
            windows.registerWindow("compositionWindow", defaultVisible: true)
            windows.registerWindow("effectsWindow", defaultVisible: true)
        }
        .onChange(of: main.activePlayer.isPrimaryCompositionLoadInFlight) { _, isInFlight in
            if isInFlight {
                completedDownloadIdentifiersThisLoad = []
                previouslyVisibleDownloadIdentifiers = Set(visibleCurrentCompositionDownloadRows.map(\.identifier))
            } else {
                completedDownloadIdentifiersThisLoad = []
                previouslyVisibleDownloadIdentifiers = []
            }
        }
        .onChange(of: visibleCurrentCompositionDownloadRows) { _, rows in
            let currentIdentifiers = Set(rows.map(\.identifier))
            let completedIdentifiers = previouslyVisibleDownloadIdentifiers.subtracting(currentIdentifiers)
            if !completedIdentifiers.isEmpty {
                completedDownloadIdentifiersThisLoad.formUnion(completedIdentifiers)
            }
            previouslyVisibleDownloadIdentifiers = currentIdentifiers
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

    static var studioHidePanelsNowNotification: Notification.Name {
        hidePanelsNowNotification
    }

    static var studioShowPanelsNowNotification: Notification.Name {
        showPanelsNowNotification
    }

    @ViewBuilder
    private func currentCompositionDownloadOverlay(rows: [CurrentCompositionDownloadRow]) -> some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloading Apple Photos Assets")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Playback will look incomplete until these source items finish downloading.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(row.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Spacer(minLength: 10)

                                Text("\(Int((row.progress * 100).rounded()))%")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.68))
                            }

                            ProgressView(value: row.progress, total: 1)
                                .tint(.blue)

                            Text(row.subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(32)
        }
    }
}
