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
    @ObservedObject private var panels: PanelStateController
    @ObservedObject private var appSettingsStore: AppSettingsStore
    @ObservedObject private var externalLoadHarness = ExternalMediaLoadHarness.shared
    @StateObject private var panelHostService = PanelHostService()
    @State private var panelsCurrentlyAutoHidden = false
    @State private var completedDownloadIdentifiersThisLoad: Set<String> = []
    @State private var previouslyVisibleDownloadIdentifiers: Set<String> = []

    private static let hidePanelsNowNotification = Notification.Name("StudioHidePanelsNow")
    private static let showPanelsNowNotification = Notification.Name("StudioShowPanelsNow")

    init(state: HypnographState, main: Studio) {
        self.state = state
        self.main = main
        _panels = ObservedObject(initialValue: main.panels)
        _appSettingsStore = ObservedObject(initialValue: state.appSettingsStore)
    }

    private var layerTrimContexts: [LayerTrimContext] {
        let layers = main.activePlayer.layers
        guard !layers.isEmpty else { return [] }

        func makeContext(layer: Layer, index: Int) -> LayerTrimContext? {
            guard layer.mediaClip.file.mediaKind == .video else { return nil }

            let total = max(0.1, layer.mediaClip.file.duration.seconds)
            let start = max(0, min(layer.mediaClip.startTime.seconds, total))
            let maxSelection = total
            let selectedDuration = min(layer.mediaClip.duration.seconds, maxSelection, total - start)
            let end = max(start + 0.1, min(start + selectedDuration, total))

            return LayerTrimContext(
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
        PlayerControlsPanel(
            isPaused: main.activePlayer.isPaused,
            isLoopCurrentCompositionEnabled: main.isLoopCurrentCompositionEnabled,
            currentCompositionText: main.currentCompositionIndicatorText,
            compositionLengthSeconds: main.activePlayer.targetDuration.seconds,
            layerTrimContexts: layerTrimContexts,
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
            onCommitLayerTrimRange: { layerIndex, range in
                main.setLayerRange(
                    sourceIndex: layerIndex,
                    startSeconds: range.lowerBound,
                    endSeconds: range.upperBound
                )
            }
        )
        .frame(maxWidth: 920)
    }

    private var hypnogramsContent: some View {
        HypnogramsPanel(
            store: HypnogramStore.shared,
            historyEntries: main.activePlayer.hypnogram.compositions.enumerated().map { index, composition in
                HistoryCompositionEntry(
                    index: index,
                    composition: composition,
                    isCurrent: index == main.activePlayer.currentCompositionIndex
                )
            },
            onLoad: { entry in
                guard let hypnogram = HypnogramStore.shared.loadHypnogram(from: entry) else {
                    AppNotifications.show("Failed to load hypnogram", flash: true)
                    return
                }
                main.appendHypnogramToHistory(hypnogram, sourceURL: entry.sessionURL)
                AppNotifications.show("Loaded: \(entry.name)", flash: true)
            },
            onJumpToHistory: { index in
                main.jumpToComposition(at: index)
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
                        panelHostService.hidePanelsForCanvasInteraction()
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

                if main.isLiveModeAvailable && panels.isPanelVisible("livePreviewPanel") {
                    LivePreviewPanel(
                        livePlayer: main.livePlayer,
                        onClose: {
                            panels.setPanelVisible("livePreviewPanel", visible: false)
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
            .animation(.easeInOut(duration: 0.2), value: panels.isPanelVisible("livePreviewPanel"))
        }
        .background(
            PanelHostBridge(
                hostService: panelHostService,
                showHypnograms: panels.isPanelVisible("hypnogramsPanel"),
                showSources: panels.isPanelVisible("sourcesPanel"),
                showNewCompositions: panels.isPanelVisible("newCompositionsPanel"),
                showOutputSettings: panels.isPanelVisible("outputSettingsPanel"),
                showComposition: panels.isPanelVisible("compositionPanel"),
                showEffects: panels.isPanelVisible("effectsPanel"),
                showPlayerControls: true,
                expectedParentFullScreen: panels.mainWindowFullScreen,
                panelFrames: [
                    "hypnogramsPanel": panels.panelFrame("hypnogramsPanel"),
                    "sourcesPanel": panels.panelFrame("sourcesPanel"),
                    "newCompositionsPanel": panels.panelFrame("newCompositionsPanel"),
                    "outputSettingsPanel": panels.panelFrame("outputSettingsPanel"),
                    "compositionPanel": panels.panelFrame("compositionPanel"),
                    "effectsPanel": panels.panelFrame("effectsPanel"),
                    "playerControlsPanel": panels.panelFrame("playerControlsPanel")
                ].compactMapValues { $0 },
                panelOrder: panels.panelOrderIDs(),
                autoHidePanels: appSettingsStore.value.autoHidePanelsEnabled,
                keyboardAccessibilityOverridesEnabled: appSettingsStore.value.keyboardAccessibilityOverridesEnabled,
                onPanelVisibilityChanged: { panelID, isVisible in
                    panels.setPanelVisible(panelID, visible: isVisible)
                },
                onPanelFrameChanged: { panelID, frame in
                    panels.setPanelFrame(frame, for: panelID)
                },
                onPanelOrderChanged: { panelOrder in
                    panels.setPanelOrder(panelOrder)
                },
                onPanelsAutoHiddenChanged: { isHidden in
                    DispatchQueue.main.async {
                        panelsCurrentlyAutoHidden = isHidden
                        panels.setPanelsHidden(isHidden)
                    }
                },
                hypnogramsContent: AnyView(
                    hypnogramsContent
                ),
                sourcesContent: AnyView(
                    SourcesPanel(state: state, main: main)
                ),
                newCompositionsContent: AnyView(
                    NewCompositionsPanel(state: state, main: main)
                ),
                outputSettingsContent: AnyView(
                    OutputSettingsPanel(state: state, main: main)
                ),
                compositionContent: AnyView(
                    CompositionPanel(state: state, main: main)
                ),
                effectsContent: AnyView(
                    EffectsPanel(state: state, main: main)
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
            panelHostService.hidePanelsNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.showPanelsNowNotification)) { _ in
            panelHostService.showPanelsNow()
        }
        .onAppear {
            panels.registerPanel("hypnogramsPanel", defaultVisible: false)
            panels.registerPanel("sourcesPanel", defaultVisible: false)
            panels.registerPanel("newCompositionsPanel", defaultVisible: true)
            panels.registerPanel("outputSettingsPanel", defaultVisible: true)
            panels.registerPanel("compositionPanel", defaultVisible: true)
            panels.registerPanel("effectsPanel", defaultVisible: true)
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
