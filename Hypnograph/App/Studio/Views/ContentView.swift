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
    @ObservedObject private var settingsStore: StudioSettingsStore
    @ObservedObject private var hypnogramStore: HypnogramStore
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
        _settingsStore = ObservedObject(initialValue: state.settingsStore)
        _hypnogramStore = ObservedObject(initialValue: HypnogramStore.shared)
    }

    private var layerTrimContexts: [LayerTrimContext] {
        let currentLayers = main.currentLayers
        guard !currentLayers.isEmpty else { return [] }

        func makeContext(layer: Layer, index: Int) -> LayerTrimContext? {
            let isVideo = layer.mediaClip.file.mediaKind == .video
            let selectedDuration = max(0.1, layer.mediaClip.duration.seconds)
            let total = isVideo
                ? max(0.1, layer.mediaClip.file.duration.seconds)
                : max(selectedDuration, max(main.targetDuration.seconds, 20))
            let start = isVideo
                ? max(0, min(layer.mediaClip.startTime.seconds, total))
                : 0
            let maxSelection = total
            let end = isVideo
                ? max(start + 0.1, min(start + min(selectedDuration, min(maxSelection, total - start)), total))
                : max(0.1, min(selectedDuration, total))

            return LayerTrimContext(
                layerIndex: index,
                fileID: layer.mediaClip.file.id,
                source: layer.mediaClip.file.source,
                mediaKind: layer.mediaClip.file.mediaKind,
                clipLabel: LayerMetadataFormatter.displayLabel(for: layer),
                blendMode: index == 0 ? BlendMode.sourceOver : (layer.blendMode ?? BlendMode.defaultMontage),
                opacity: layer.opacity,
                canMoveUp: index > 0,
                canMoveDown: index < currentLayers.count - 1,
                canDelete: currentLayers.count > 1,
                isMuted: layer.isMuted,
                isVisible: layer.opacity > 0.001,
                isSoloActive: main.activePlayer.effectManager.flashSoloIndex == index,
                totalDurationSeconds: total,
                maxSelectionDurationSeconds: maxSelection,
                selectedRangeSeconds: start...end
            )
        }

        return currentLayers.enumerated().compactMap { index, layer in
            makeContext(layer: layer, index: index)
        }
    }

    private var currentCompositionEntries: [CompositionEntry] {
        main.hypnogram.compositions.enumerated().map { index, composition in
            CompositionEntry(
                index: index,
                composition: composition,
                isCurrent: index == main.currentCompositionIndex
            )
        }
    }

    private var studioPanelToolbarItems: [StudioPanelToolbarItem] {
        StudioPanelDescriptor.allCases.map { descriptor in
            StudioPanelToolbarItem(descriptor: descriptor)
        }
    }

    private var panelOpacity: Double {
        settingsStore.value.panelOpacity.clamped(to: 0.32...0.92)
    }

    private var panelOpacityBinding: Binding<Double> {
        Binding(
            get: { panelOpacity },
            set: { newValue in
                settingsStore.update { settings in
                    settings.panelOpacity = newValue.clamped(to: 0.32...0.92)
                }
            }
        )
    }

    private var liveModeSelectionBinding: Binding<Int> {
        Binding(
            get: { main.isLiveMode ? 1 : 0 },
            set: { newValue in
                if (newValue == 1) != main.isLiveMode {
                    main.toggleLiveMode()
                }
            }
        )
    }

    private var shouldShowStudioPanelToolbar: Bool {
        !panels.panelsHidden
    }

    private var topOverlayPadding: CGFloat {
        10
    }

    private var topRightIndicator: (text: String, color: Color)? {
        // LIVE indicator (same placement/size as the layer indicator)
        if main.isLiveMode {
            return ("LIVE", .red)
        }

        if shouldShowPersistentCompositionIndicator {
            return (main.currentCompositionPositionText, .blue)
        }

        if let clipText = main.compositionPositionIndicatorText {
            return (clipText, .blue)
        }

        // Layer indicators: show during flash solo (1-9 hold) or composition hold (`) while composition effect chains are suspended.
        guard !main.currentLayers.isEmpty else { return nil }

        if main.activePlayer.effectManager.flashSoloIndex != nil {
            return ("\(main.activePlayer.currentLayerIndex + 1)/\(main.currentLayers.count)", .red)
        }

        if main.activePlayer.isCompositionEffectSuspended {
            return ("GLOBAL/\(main.currentLayers.count)", .red)
        }

        return nil
    }

    private var shouldShowPersistentCompositionIndicator: Bool {
        guard !panelsCurrentlyAutoHidden else { return false }
        return main.isViewingEarlierComposition
    }

    private var shouldAutoHideCursor: Bool {
        if main.isLiveMode {
            guard let player = main.livePlayer.activeAVPlayer else { return false }
            return player.rate != 0
        }

        let clip = main.currentComposition
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

        let composition = main.currentComposition
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
        VStack(spacing: 8) {
            StudioPanelToolbarView(
                items: studioPanelToolbarItems,
                isPanelVisible: { panelID in panels.isPanelVisible(panelID) },
                onTogglePanel: { panelID in
                    panels.togglePanel(panelID)
                },
                panelOpacity: panelOpacityBinding,
                liveModeSelection: main.isLiveModeAvailable ? liveModeSelectionBinding : nil
            )
            .opacity(panelOpacity)

            PlayerControlsPanel(
                isPaused: main.activePlayer.isPaused,
                isLoopCompositionEnabled: main.isLoopCompositionEnabled,
                isLoopSequenceEnabled: main.isLoopSequenceEnabled,
                selectedLayerIndex: main.activePlayer.currentLayerIndex,
                compositionLengthSeconds: main.targetDuration.seconds,
                sequenceEntries: currentCompositionEntries,
                layerTrimContexts: layerTrimContexts,
                visualOpacity: panelOpacity,
                volume: Binding(
                    get: { Double(main.volume) },
                    set: { main.volume = Float($0) }
                ),
                onJumpToComposition: { index in
                    main.jumpToComposition(at: index)
                },
                onDeleteCompositionEntry: { index in
                    main.deleteComposition(at: index)
                },
                onMoveComposition: { sourceID, targetID in
                    main.moveComposition(sourceID: sourceID, targetID: targetID)
                },
                onPrevious: { main.previousComposition() },
                onPlayPause: { main.togglePause() },
                onNext: { main.nextComposition() },
                onSelectLayer: { index in
                    main.selectSource(index)
                },
                onMoveLayerUp: { index in
                    main.moveLayerUp(at: index)
                },
                onMoveLayerDown: { index in
                    main.moveLayerDown(at: index)
                },
                onDeleteLayer: { index in
                    main.deleteLayer(at: index)
                },
                onSetLayerBlendMode: { index, blendMode in
                    main.setLayerBlendMode(at: index, blendMode: blendMode)
                },
                onSetLayerOpacity: { index, opacity in
                    main.setLayerOpacity(at: index, opacity: opacity)
                },
                onToggleLayerMute: { index in
                    main.toggleLayerMute(at: index)
                },
                onToggleLayerSolo: { index in
                    main.toggleLayerSolo(at: index)
                },
                onToggleLayerVisibility: { index in
                    main.toggleLayerVisibility(at: index)
                },
                onAddSourceFromFiles: { main.addSourceFromFilesPanel() },
                onAddSourceFromPhotos: { main.addSourceFromPhotosPicker() },
                onAddSourceFromRandom: { main.addSourceFromRandom() },
                onCyclePlaybackLoopMode: { main.cyclePlaybackLoopMode() },
                onSnapshotCurrent: { main.saveSnapshotImage() },
                onSaveCurrent: { main.saveComposition() },
                onRenderCurrent: { main.renderAndSaveVideo() },
                onRenderSequence: { main.renderAndSaveSequenceVideo() },
                onCommitLayerTrimRange: { layerIndex, range in
                    main.setLayerRange(
                        sourceIndex: layerIndex,
                        startSeconds: range.lowerBound,
                        endSeconds: range.upperBound
                    )
                }
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var hypnogramsContent: some View {
        HypnogramsPanel(
            recentEntries: hypnogramStore.recent,
            favoriteEntries: hypnogramStore.favorites,
            onLoad: { entry in
                guard let hypnogram = hypnogramStore.loadHypnogram(from: entry) else {
                    AppNotifications.show("Failed to load hypnogram", flash: true)
                    return
                }
                _ = main.openHypnogramAsWorkingDocument(hypnogram, sourceURL: entry.sessionURL)
            },
            onToggleFavorite: { entry in
                hypnogramStore.toggleFavorite(entry)
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

            if shouldShowStudioPanelToolbar {
                VStack(spacing: 0) {
                    Spacer()

                    playerControlsContent
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
                .ignoresSafeArea(edges: .bottom)
                .zIndex(35)
            }

            CursorAutoHideView(isEnabled: shouldAutoHideCursor, idleSeconds: 3.0)
                .allowsHitTesting(false)
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
            .padding(.top, topOverlayPadding)
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
                    .opacity(panelOpacity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, topOverlayPadding)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
            .animation(.easeInOut(duration: 0.2), value: panels.isPanelVisible("livePreviewPanel"))
        }
        .background(
            PanelHostBridge(
                hostService: panelHostService,
                showHypnograms: panels.isPanelVisible("hypnogramsPanel"),
                showNewCompositions: panels.isPanelVisible("newCompositionsPanel"),
                showProperties: panels.isPanelVisible("propertiesPanel"),
                showEffects: panels.isPanelVisible("effectsPanel"),
                showPlayerControls: false,
                expectedParentFullScreen: panels.mainWindowFullScreen,
                panelFrames: [
                    "hypnogramsPanel": panels.panelFrame("hypnogramsPanel"),
                    "newCompositionsPanel": panels.panelFrame("newCompositionsPanel"),
                    "propertiesPanel": panels.panelFrame("propertiesPanel"),
                    "effectsPanel": panels.panelFrame("effectsPanel"),
                    "playerControlsPanel": panels.panelFrame("playerControlsPanel")
                ].compactMapValues { $0 },
                panelOrder: panels.panelOrderIDs(),
                panelOpacity: panelOpacity,
                autoHidePanels: settingsStore.value.autoHidePanelsEnabled,
                keyboardAccessibilityOverridesEnabled: settingsStore.value.keyboardAccessibilityOverridesEnabled,
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
                newCompositionsContent: AnyView(
                    NewCompositionsPanel(state: state, main: main)
                ),
                propertiesContent: AnyView(
                    PropertiesPanel(state: state, main: main)
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
            panels.registerPanel("newCompositionsPanel", defaultVisible: true)
            panels.registerPanel("propertiesPanel", defaultVisible: true)
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
        .sheet(isPresented: $state.showPhotosPickerForSource) {
            PhotosPickerSheet(
                isPresented: $state.showPhotosPickerForSource,
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
        .sheet(isPresented: $state.showPhotosPickerForAddLayer) {
            PhotosPickerSheet(
                isPresented: $state.showPhotosPickerForAddLayer,
                preselectedIdentifiers: [],
                selectionLimit: 1,
                onSelection: { identifiers in
                    guard let selectedIdentifier = identifiers.first else { return }
                    _ = main.addSource(fromPhotosAssetIdentifier: selectedIdentifier)
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
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onToggle?()
    }
}
