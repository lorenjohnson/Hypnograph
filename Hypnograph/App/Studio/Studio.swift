//
//  Studio.swift
//  Hypnograph
//
//  Studio feature: video/image composition with a single preview path.
//

import Foundation
import CoreGraphics
import CoreMedia
import Combine
import SwiftUI
import AVFoundation
import AppKit
import Photos
import HypnoCore
import HypnoUI

@MainActor
final class Studio: ObservableObject {
    let state: HypnographState
    let panels: PanelStateController
    let renderQueue: RenderEngine.ExportQueue
    let dependencies: StudioDependencies
    let panelHostService: FilePanelService
    let photosIntegrationService: PhotosIntegrationService
    let historyPersistenceService: HistoryPersistenceService

    /// Global templates store (shared across preview + live)
    let effectsLibrarySession: EffectsSession

    /// Global RECENT effects store (shared across preview + live)
    let recentEffectsStore: RecentEffectChainsStore

    // MARK: - Player States

    /// In-app deck - a layered clip
    let player: PlayerState

    /// Live display - external monitor output (moved from HypnographState)
    let livePlayer: LivePlayer

    /// Subscriptions to forward player state changes to Studio's objectWillChange
    private var playerSubscriptions: Set<AnyCancellable> = []

    /// Working file target for each composition currently present in Studio's current hypnogram.
    /// This stays app-local rather than becoming part of the persisted model.
    private var saveTargetsByCompositionID: [UUID: URL] = [:]
    @Published private(set) var activeWorkingHypnogramURL: URL?
    @Published private(set) var hasUnsavedWorkingHypnogramChanges = false
    private var suppressWorkingHypnogramDirtyTracking = false

    /// The active preview player (always the preview deck)
    var activePlayer: PlayerState { player }

    /// Live mode: Edit (local preview) vs Live (mirror live display)
    enum LiveMode {
        case edit
        case live
    }

    @Published var liveMode: LiveMode = .edit
    @Published var outputResolution: OutputResolution = PlayerConfiguration.defaultPlayerResolution

    var isLiveMode: Bool { liveMode == .live }
    var isLiveModeAvailable: Bool { state.settings.liveModeEnabled }
    var isUsingDefaultWorkingHypnogram: Bool { activeWorkingHypnogramURL == nil }

    // MARK: - History HUD

    /// Flash-only composition position indicator (e.g. "3/57") shown when manually navigating history.
    @Published var historyIndicatorText: String?

    var historyIndicatorClearWorkItem: DispatchWorkItem?
    var compositionSelectionWorkItem: DispatchWorkItem?
    var compositionSelectionUpdateToken: UInt64 = 0

    // MARK: - History Persistence

    var historySaveTimer: Timer?
    var historySaveCancellables: Set<AnyCancellable> = []

    // MARK: - Audio Output

    /// Audio controller manages device selection and volume for in-app/live
    let audioController: AudioController

    /// Convenience accessors for audio state (forwarded from controller)
    /// In-app audio output device.
    var audioDevice: AudioOutputDevice? {
        get { audioController.audioDevice }
        set { audioController.audioDevice = newValue }
    }

    var liveAudioDevice: AudioOutputDevice? {
        get { audioController.liveAudioDevice }
        set { audioController.liveAudioDevice = newValue }
    }

    /// In-app volume.
    var volume: Float {
        get { audioController.volume }
        set { audioController.volume = newValue }
    }

    var liveVolume: Float {
        get { audioController.liveVolume }
        set { audioController.liveVolume = newValue }
    }

    var audioDeviceUID: String? { audioController.audioDeviceUID }
    var liveAudioDeviceUID: String? { audioController.liveAudioDeviceUID }

    /// Returns the active EffectManager based on live mode
    /// In live mode, effects go to the live display; in edit mode, to the active player
    var activeEffectManager: EffectManager {
        isLiveMode ? livePlayer.effectManager : activePlayer.effectManager
    }

    /// Returns the active EffectsSession based on live mode
    /// Templates are shared across edit/live modes.
    var effectsSession: EffectsSession {
        effectsLibrarySession
    }

    func toggleLiveMode() {
        guard isLiveModeAvailable else {
            if liveMode != .edit {
                liveMode = .edit
            }
            return
        }
        liveMode = (liveMode == .edit) ? .live : .edit
        print("🎬 Live Mode: \(liveMode == .live ? "LIVE" : "Edit")")
    }

    // MARK: - Init

    init(
        state: HypnographState,
        renderQueue: RenderEngine.ExportQueue,
        dependencies: StudioDependencies = .live
    ) {
        self.state = state
        self.panels = PanelStateController()
        self.renderQueue = renderQueue
        self.dependencies = dependencies
        self.panelHostService = dependencies.makePanelHostService()
        self.photosIntegrationService = dependencies.photosIntegrationService
        self.historyPersistenceService = dependencies.historyPersistenceService

        // One canonical effects library across modes.
        self.effectsLibrarySession = EffectsSession(filename: "effects-library.json")
        self.recentEffectsStore = RecentEffectChainsStore()

        // Create the preview player state (single deck) + live display
        let initialPlayerConfig = PlayerConfiguration.defaultValue(maxLayers: state.settings.maxLayers)
        self.player = PlayerState(config: initialPlayerConfig, effectsSession: effectsLibrarySession)
        self.livePlayer = LivePlayer(
            config: initialPlayerConfig,
            sourceFraming: .fill,
            transitionStyle: .crossfade,
            transitionDuration: 1.0,
            effectsSession: effectsLibrarySession
        )

        // Wire RECENT store into all effect managers
        player.effectManager.recentStore = recentEffectsStore
        livePlayer.effectManager.recentStore = recentEffectsStore

        // Create audio controller (handles device selection, volume, persistence)
        self.audioController = AudioController(settingsStore: state.settingsStore, livePlayer: livePlayer)

        // Forward player state changes to Studio's objectWillChange for SwiftUI reactivity
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &playerSubscriptions)

        // Forward audio controller changes for SwiftUI reactivity
        audioController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &playerSubscriptions)

        // Forward settings changes (e.g., playback end behavior toggle) for SwiftUI reactivity
        state.settingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &playerSubscriptions)

        // If the live feature flag is disabled while running, gracefully return to preview-only mode.
        state.settingsStore.$value
            .map(\.liveModeEnabled)
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self, !isEnabled else { return }
                if self.liveMode == .live {
                    self.liveMode = .edit
                }
                self.panels.setPanelVisible("livePreviewPanel", visible: false)
                if self.livePlayer.isVisible {
                    self.livePlayer.hide()
                }
            }
            .store(in: &playerSubscriptions)

        // Persist only the generation-related portion of player config.
        player.$config
            .map(\.maxLayers)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] maxLayers in
                guard let self = self else { return }
                self.state.settingsStore.update { $0.maxLayers = maxLayers }
            }
            .store(in: &playerSubscriptions)

        // Restore history if available
        restoreHistory()

        // Save history when app terminates and on edits
        setupHistoryPersistence()
    }

    // MARK: - Display

    func makeDisplayView() -> AnyView {
        if isLiveMode {
            return AnyView(
                LivePlayerScreen(livePlayer: livePlayer)
                    .id("main-live-\(livePlayer.config.viewID)")
            )
        }

        if activePlayer.hypnogram.compositions.isEmpty || activePlayer.layers.isEmpty {
            // Avoid an infinite "generate new clip" loop when the media library is empty.
            if state.library.assetCount == 0 {
                return AnyView(NoSourcesView(state: state, main: self))
            }

            if activePlayer.hypnogram.compositions.isEmpty {
                replaceHistoryWithNewComposition()
            } else if activePlayer.layers.isEmpty {
                // Defensive: keep history shape, just replace the current composition if it is empty.
                replaceCurrentCompositionWithNewComposition()
            }
        }

        let player = activePlayer
        let composition = player.currentComposition

        if currentCompositionRequiresPhotosAccess(composition) && !state.photosAuthorizationStatus.canRead {
            return AnyView(PhotosAccessRequiredView(state: state, main: self))
        }

        if currentCompositionHasNoReachableSources(composition) {
            return AnyView(CompositionSourcesUnavailableView(main: self))
        }

        if player.currentCompositionLoadFailure?.compositionID == composition.id {
            return AnyView(CompositionSourcesUnavailableView(main: self))
        }

        // Common view parameters
        let aspectRatio = currentDocumentAspectRatio
        let displayResolution = currentDocumentPlayerResolution
        let sourceFraming = currentDocumentSourceFraming
        let shouldAdvanceOnCompositionEnd = state.settings.playbackEndBehavior == .autoAdvance
        let onCompositionEnded: (() -> Bool)? = { [weak self] in
            guard let self else { return false }
            return self.advanceOrGenerateOnCompositionEnded()
        }
        let currentLayerIndexBinding = Binding(
            get: { player.currentLayerIndex },
            set: { player.currentLayerIndex = $0 }
        )
        let currentSourceTimeBinding = Binding(
            get: { player.currentLayerTimeOffset },
            set: { player.currentLayerTimeOffset = $0 }
        )
        let compositionLoadInFlightBinding = Binding(
            get: { player.isPrimaryCompositionLoadInFlight },
            set: { player.isPrimaryCompositionLoadInFlight = $0 }
        )
        let pendingGeneratedNextCompositionBinding = Binding(
            get: { player.hasPendingGeneratedNextComposition },
            set: { player.hasPendingGeneratedNextComposition = $0 }
        )
        let viewID = "main-preview-\(player.config.viewID)-\(player.playRate)"

        return AnyView(
            PlayerView(
                composition: composition,
                aspectRatio: aspectRatio,
                displayResolution: displayResolution,
                sourceFraming: sourceFraming,
                autoAdvanceOnCompositionEnd: shouldAdvanceOnCompositionEnd,
                onCompositionEnded: onCompositionEnded,
                currentLayerIndex: currentLayerIndexBinding,
                currentSourceTime: currentSourceTimeBinding,
                isPrimaryCompositionLoadInFlight: compositionLoadInFlightBinding,
                hasPendingGeneratedNextComposition: pendingGeneratedNextCompositionBinding,
                currentCompositionLoadFailure: Binding(
                    get: { player.currentCompositionLoadFailure },
                    set: { player.currentCompositionLoadFailure = $0 }
                ),
                isPaused: player.isPaused,
                effectsChangeCounter: player.effectsChangeCounter,
                hypnogramRevision: player.hypnogramRevision,
                effectManager: player.effectManager,
                volume: volume,
                audioDeviceUID: audioDeviceUID,
                transitionStyle: currentDocumentTransitionStyle,
                transitionDuration: currentDocumentTransitionDuration,
                onCompositionFramePresented: { [weak self, weak player] compositionID in
                    guard let player else { return }

                    if compositionID == nil {
                        if player.suppressNextPreviewInvalidation {
                            player.suppressNextPreviewInvalidation = false
                            return
                        }

                        player.currentRenderedCompositionID = nil
                        player.currentCompositionPreviewNeedsRefresh = true
                        return
                    }

                    player.currentRenderedCompositionID = compositionID
                    guard player.currentCompositionPreviewNeedsRefresh else { return }
                    self?.persistCurrentCompositionPreviewIfNeeded()
                }
            )
            .id(viewID)
        )
    }

    private func currentCompositionRequiresPhotosAccess(_ composition: Composition) -> Bool {
        composition.layers.contains { layer in
            if case .external = layer.mediaClip.file.source {
                return true
            }
            return false
        }
    }

    private func currentCompositionHasNoReachableSources(_ composition: Composition) -> Bool {
        guard !composition.layers.isEmpty else { return false }

        return !composition.layers.contains { layer in
            switch layer.mediaClip.file.source {
            case .url(let url):
                return FileManager.default.fileExists(atPath: url.path)
            case .external:
                return state.photosAuthorizationStatus.canRead
            }
        }
    }

    /// Build a hypnogram snapshot for display/export (timestamp + effects library snapshot)
    func makeDisplayHypnogram() -> Hypnogram {
        let createdAt = Date()
        var composition = activePlayer.currentComposition
        composition.createdAt = createdAt
        return makeHypnogramWithCurrentDocumentContext(
            compositions: [composition],
            currentCompositionIndex: 0,
            createdAt: createdAt
        )
    }

    func makeHypnogramWithCurrentDocumentContext(
        compositions: [Composition],
        currentCompositionIndex: Int?,
        snapshot: String? = nil,
        createdAt: Date = Date()
    ) -> Hypnogram {
        Hypnogram(
            compositions: compositions,
            currentCompositionIndex: currentCompositionIndex,
            aspectRatio: currentDocumentAspectRatio,
            playerResolution: currentDocumentPlayerResolution,
            outputResolution: currentDocumentOutputResolution,
            sourceFraming: currentDocumentSourceFraming,
            transitionStyle: currentDocumentTransitionStyle,
            transitionDuration: currentDocumentTransitionDuration,
            snapshot: snapshot,
            createdAt: createdAt
        )
    }

    var currentDocumentAspectRatio: AspectRatio {
        activePlayer.config.aspectRatio
    }

    var currentDocumentPlayerResolution: OutputResolution {
        activePlayer.config.playerResolution
    }

    var currentDocumentOutputResolution: OutputResolution {
        outputResolution
    }

    var currentDocumentSourceFraming: SourceFraming {
        livePlayer.currentSourceFraming
    }

    var currentDocumentTransitionStyle: TransitionRenderer.TransitionType {
        livePlayer.transitionType
    }

    var currentDocumentTransitionDuration: Double {
        livePlayer.crossfadeDuration
    }

    private func resolvedAspectRatio(for hypnogram: Hypnogram) -> AspectRatio {
        hypnogram.aspectRatio ?? PlayerConfiguration.defaultAspectRatio
    }

    private func resolvedPlayerResolution(for hypnogram: Hypnogram) -> OutputResolution {
        hypnogram.playerResolution
            ?? hypnogram.outputResolution
            ?? PlayerConfiguration.defaultPlayerResolution
    }

    private func resolvedOutputResolution(for hypnogram: Hypnogram) -> OutputResolution {
        hypnogram.outputResolution
            ?? hypnogram.playerResolution
            ?? PlayerConfiguration.defaultPlayerResolution
    }

    private func resolvedSourceFraming(for hypnogram: Hypnogram) -> SourceFraming {
        hypnogram.sourceFraming ?? .fill
    }

    private func resolvedTransitionStyle(for hypnogram: Hypnogram) -> TransitionRenderer.TransitionType {
        hypnogram.transitionStyle ?? .crossfade
    }

    private func resolvedTransitionDuration(for hypnogram: Hypnogram) -> Double {
        hypnogram.transitionDuration ?? 1.0
    }

    func copyDocumentContext(from hypnogram: Hypnogram) {
        player.hypnogram.aspectRatio = resolvedAspectRatio(for: hypnogram)
        player.hypnogram.playerResolution = resolvedPlayerResolution(for: hypnogram)
        player.hypnogram.outputResolution = resolvedOutputResolution(for: hypnogram)
        player.hypnogram.sourceFraming = resolvedSourceFraming(for: hypnogram)
        player.hypnogram.transitionStyle = resolvedTransitionStyle(for: hypnogram)
        player.hypnogram.transitionDuration = resolvedTransitionDuration(for: hypnogram)
    }

    func syncCurrentHypnogramDocumentContextFromRuntime() {
        player.hypnogram.aspectRatio = currentDocumentAspectRatio
        player.hypnogram.playerResolution = currentDocumentPlayerResolution
        player.hypnogram.outputResolution = currentDocumentOutputResolution
        player.hypnogram.sourceFraming = currentDocumentSourceFraming
        player.hypnogram.transitionStyle = currentDocumentTransitionStyle
        player.hypnogram.transitionDuration = currentDocumentTransitionDuration
    }

    func applyCurrentHypnogramDocumentContextToRuntime() {
        let aspectRatio = resolvedAspectRatio(for: player.hypnogram)
        let playerResolution = resolvedPlayerResolution(for: player.hypnogram)
        let outputResolution = resolvedOutputResolution(for: player.hypnogram)
        let sourceFraming = resolvedSourceFraming(for: player.hypnogram)
        let transitionStyle = resolvedTransitionStyle(for: player.hypnogram)
        let transitionDuration = resolvedTransitionDuration(for: player.hypnogram)

        player.hypnogram.aspectRatio = aspectRatio
        player.hypnogram.playerResolution = playerResolution
        player.hypnogram.outputResolution = outputResolution
        player.hypnogram.sourceFraming = sourceFraming
        player.hypnogram.transitionStyle = transitionStyle
        player.hypnogram.transitionDuration = transitionDuration
        self.outputResolution = outputResolution

        if player.config.aspectRatio != aspectRatio {
            player.config.aspectRatio = aspectRatio
        }
        if player.config.playerResolution != playerResolution {
            player.config.playerResolution = playerResolution
        }
        if livePlayer.config.aspectRatio != aspectRatio {
            livePlayer.config.aspectRatio = aspectRatio
        }
        if livePlayer.config.playerResolution != playerResolution {
            livePlayer.config.playerResolution = playerResolution
        }

        livePlayer.setSourceFraming(sourceFraming)
        livePlayer.transitionType = transitionStyle
        livePlayer.crossfadeDuration = transitionDuration
    }

    var currentSaveTargetURL: URL? {
        saveTargetsByCompositionID[activePlayer.currentComposition.id]
    }

    func setSaveTargetURL(_ url: URL?, for compositionID: UUID) {
        if let url {
            saveTargetsByCompositionID[compositionID] = url
        } else {
            saveTargetsByCompositionID.removeValue(forKey: compositionID)
        }
    }

    func assignSaveTargetIfUnambiguous(_ url: URL?, for compositions: [Composition]) {
        guard compositions.count == 1, let composition = compositions.first else { return }
        setSaveTargetURL(url, for: composition.id)
    }

    func clearSaveTarget(for compositionID: UUID) {
        saveTargetsByCompositionID.removeValue(forKey: compositionID)
    }

    func clearAllSaveTargets() {
        saveTargetsByCompositionID.removeAll()
    }

    func pruneSaveTargetsToCurrentHypnogram() {
        let validIDs = Set(activePlayer.hypnogram.compositions.map(\.id))
        saveTargetsByCompositionID = saveTargetsByCompositionID.filter { validIDs.contains($0.key) }
    }

    func setActiveWorkingHypnogramURL(_ url: URL?) {
        activeWorkingHypnogramURL = url
        if url == nil {
            hasUnsavedWorkingHypnogramChanges = false
        }
    }

    func clearUnsavedWorkingHypnogramChanges() {
        hasUnsavedWorkingHypnogramChanges = false
    }

    func markWorkingHypnogramDirtyIfNeeded() {
        guard !suppressWorkingHypnogramDirtyTracking else { return }
        guard activeWorkingHypnogramURL != nil else { return }
        hasUnsavedWorkingHypnogramChanges = true
    }

    func performWithoutMarkingWorkingHypnogramDirty(_ work: () -> Void) {
        let wasSuppressed = suppressWorkingHypnogramDirtyTracking
        suppressWorkingHypnogramDirtyTracking = true
        work()
        suppressWorkingHypnogramDirtyTracking = wasSuppressed
    }

}
