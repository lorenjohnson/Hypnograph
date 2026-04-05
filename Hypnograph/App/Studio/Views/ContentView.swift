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

    private var hasTrackedDownloadsThisLoad: Bool {
        !visibleCurrentCompositionDownloadRows.isEmpty ||
        !previouslyVisibleDownloadIdentifiers.isEmpty ||
        !completedDownloadIdentifiersThisLoad.isEmpty
    }

    private var shouldShowCurrentCompositionDownloadHUD: Bool {
        main.activePlayer.isPrimaryCompositionLoadInFlight && hasTrackedDownloadsThisLoad
    }

    private var currentCompositionDownloadAggregateProgress: Double {
        if !visibleCurrentCompositionDownloadRows.isEmpty {
            return visibleCurrentCompositionDownloadRows.map(\.progress).min() ?? 0
        }

        if shouldShowCurrentCompositionDownloadHUD {
            return 1
        }

        return 0
    }

    @ViewBuilder
    private func topRightIndicatorBadge(_ indicator: (text: String, color: Color)) -> some View {
        Text(indicator.text)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(indicator.color)
            .padding(.vertical, 6)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 34, alignment: .center)
    }

    @ViewBuilder
    private func currentCompositionDownloadHUD(progress: Double) -> some View {
        ProgressView(value: min(max(progress, 0), 1), total: 1)
            .progressViewStyle(.circular)
            .controlSize(.regular)
            .frame(width: 20, height: 20)
            .padding(3)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.22))
            )
        .frame(width: 30, height: 30, alignment: .center)
        .accessibilityLabel("Apple Photos download progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Studio display
            main.makeDisplayView()
                .ignoresSafeArea()
                .overlay {
                    CanvasPanelToggleHitView {
                        windowHostService.hidePanelsForCanvasInteraction()
                    }
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
            HStack(alignment: .center, spacing: 4) {
                if shouldShowCurrentCompositionDownloadHUD {
                    currentCompositionDownloadHUD(progress: currentCompositionDownloadAggregateProgress)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                if let indicator = topRightIndicator {
                    topRightIndicatorBadge(indicator)
                }
            }
            .frame(height: 34, alignment: .trailing)
            .padding(.top, 10)
            .padding(.trailing, 12)
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
                expectedParentFullScreen: windows.mainWindowFullScreen,
                panelFrames: [
                    "hypnogramList": windows.panelFrame("hypnogramList"),
                    "sourcesWindow": windows.panelFrame("sourcesWindow"),
                    "newClipsWindow": windows.panelFrame("newClipsWindow"),
                    "outputSettingsWindow": windows.panelFrame("outputSettingsWindow"),
                    "compositionWindow": windows.panelFrame("compositionWindow"),
                    "effectsWindow": windows.panelFrame("effectsWindow"),
                    "playerControlsWindow": windows.panelFrame("playerControlsWindow")
                ].compactMapValues { $0 },
                panelOrder: windows.panelOrderIDs(),
                autoHideWindows: appSettingsStore.value.autoHideWindowsEnabled,
                keyboardAccessibilityOverridesEnabled: appSettingsStore.value.keyboardAccessibilityOverridesEnabled,
                onPanelVisibilityChanged: { windowID, isVisible in
                    windows.setWindowVisible(windowID, visible: isVisible)
                },
                onPanelFrameChanged: { windowID, frame in
                    windows.setPanelFrame(frame, for: windowID)
                },
                onPanelOrderChanged: { panelOrder in
                    windows.setPanelOrder(panelOrder)
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

}

private struct CanvasPanelToggleHitView: NSViewRepresentable {
    let onToggle: () -> Void

    func makeNSView(context: Context) -> CanvasPanelToggleNSView {
        let view = CanvasPanelToggleNSView()
        view.onToggle = onToggle
        return view
    }

    func updateNSView(_ nsView: CanvasPanelToggleNSView, context: Context) {
        nsView.onToggle = onToggle
    }
}

private final class CanvasPanelToggleNSView: NSView {
    var onToggle: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onToggle?()
    }
}
