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
    enum PlaybackEndBehavior {
        case stopAtEnd
        case loopComposition
        case advanceAcrossCompositions(loopAtSequenceEnd: Bool, generateAtSequenceEnd: Bool)
    }

    static let defaultAspectRatio: AspectRatio = .ratio16x9
    static let defaultPlayerResolution: OutputResolution = .p1080

    let state: HypnographState
    let panels: PanelStateController
    let renderQueue: RenderEngine.ExportQueue
    let panelHostService: FilePanelService
    let photosIntegrationService: PhotosIntegrationService
    let compositionPreviewPersistenceScheduler = CompositionPreviewPersistenceScheduler()

    /// Global templates store (shared across preview + live)
    let effectsLibrarySession: EffectsSession

    /// Global RECENT effects store (shared across preview + live)
    let recentEffectsStore: RecentEffectChainsStore

    // MARK: - Player States

    @Published var hypnogram: Hypnogram
    @Published var currentCompositionIndex: Int
    @Published private(set) var hypnogramRevision: Int = 0

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
    @Published var isShowingFullClips = false
    var isLiveMode: Bool { liveMode == .live }
    var isLiveModeAvailable: Bool { state.settings.liveModeEnabled }
    var isUsingDefaultHypnogram: Bool { activeWorkingHypnogramURL == nil }

    // MARK: - Composition Position HUD

    /// Flash-only composition position indicator (e.g. "3/57") shown when manually navigating compositions.
    @Published var compositionPositionIndicatorText: String?

    var compositionPositionIndicatorClearWorkItem: DispatchWorkItem?
    var compositionSelectionWorkItem: DispatchWorkItem?
    var compositionSelectionUpdateToken: UInt64 = 0

    // MARK: - Default Hypnogram Persistence

    var defaultHypnogramSaveTimer: Timer?
    var defaultHypnogramSaveCancellables: Set<AnyCancellable> = []

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

    func toggleShowFullClips() {
        isShowingFullClips.toggle()
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
        self.panelHostService = dependencies.makePanelHostService()
        self.photosIntegrationService = dependencies.photosIntegrationService

        // One canonical effects library across modes.
        self.effectsLibrarySession = EffectsSession(filename: "effects-library.json")
        self.recentEffectsStore = RecentEffectChainsStore()

        let initialHypnogram = Hypnogram(
            compositions: [
                Composition(
                    layers: [],
                    targetDuration: CMTime(seconds: 15, preferredTimescale: 600),
                    playRate: 1.0
                )
            ]
        )
        self.hypnogram = initialHypnogram
        self.currentCompositionIndex = 0

        // Create the preview player state (single deck) + live display
        let initialPlayerConfig = PlayerConfiguration.defaultValue(maxLayers: state.settings.maxLayers)
        self.player = PlayerState(
            config: initialPlayerConfig,
            effectsSession: effectsLibrarySession
        )
        self.livePlayer = LivePlayer(
            aspectRatio: Studio.defaultAspectRatio,
            outputResolution: Studio.defaultPlayerResolution,
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

        player.configureDocumentBindings(
            compositionProvider: { [unowned self] in self.currentComposition },
            hypnogramEffectChainProvider: { [unowned self] in self.currentHypnogramEffectChain },
            setHypnogramEffectChain: { [weak self] chain in
                self?.currentHypnogramEffectChain = chain
            },
            setCompositionEffectChain: { [weak self] chain in
                self?.updateCurrentComposition { $0.effectChain = chain }
            },
            setSourceEffectChain: { [weak self] sourceIndex, chain in
                self?.updateCurrentComposition { composition in
                    guard sourceIndex >= 0, sourceIndex < composition.layers.count else { return }
                    composition.layers[sourceIndex].effectChain = chain
                }
            },
            setBlendMode: { [weak self] sourceIndex, blendMode in
                self?.updateCurrentComposition { composition in
                    guard sourceIndex >= 0, sourceIndex < composition.layers.count else { return }
                    composition.layers[sourceIndex].blendMode = blendMode
                }
            }
        )

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

        // Restore the default fallback hypnogram if available
        restoreDefaultHypnogram()

        // Save the default working hypnogram when app terminates and on edits
        setupDefaultHypnogramPersistence()
    }

    // MARK: - Working Hypnogram

    var currentComposition: Composition {
        get {
            let index = max(0, min(currentCompositionIndex, max(0, hypnogram.compositions.count - 1)))
            var composition = hypnogram.compositions[index]
            composition.syncTargetDurationToLayers()
            return composition
        }
        set {
            guard !hypnogram.compositions.isEmpty else { return }
            let index = max(0, min(currentCompositionIndex, hypnogram.compositions.count - 1))
            var normalized = newValue
            normalized.syncTargetDurationToLayers()
            hypnogram.compositions[index] = normalized
            markCurrentCompositionPreviewNeedsRefresh()
            notifyHypnogramChanged()
        }
    }

    var currentLayers: [Layer] {
        get { currentComposition.layers }
        set { updateCurrentComposition { $0.layers = newValue } }
    }

    var effectChain: EffectChain {
        get { currentComposition.effectChain }
        set { updateCurrentComposition { $0.effectChain = newValue } }
    }

    var currentHypnogramEffectChain: EffectChain {
        get { hypnogram.effectChain }
        set {
            updateHypnogramDocumentSettings { $0.effectChain = newValue }
            notifyHypnogramChanged()
        }
    }

    var playRate: Float {
        get { currentComposition.playRate }
        set { updateCurrentComposition { $0.playRate = newValue } }
    }

    var currentCompositionTransitionStyleOverride: TransitionRenderer.TransitionType? {
        currentComposition.transitionStyle
    }

    var currentCompositionTransitionStyle: TransitionRenderer.TransitionType {
        resolvedTransitionStyle(for: currentComposition, in: hypnogram)
    }

    var currentCompositionTransitionDurationOverride: Double? {
        currentComposition.transitionDuration
    }

    var currentCompositionTransitionDuration: Double {
        resolvedTransitionDuration(for: currentComposition, in: hypnogram)
    }

    var targetDuration: CMTime {
        get { currentComposition.effectiveDuration }
        set { updateCurrentComposition { $0.targetDuration = newValue } }
    }

    var currentLayer: Layer? {
        guard player.currentLayerIndex >= 0, player.currentLayerIndex < currentLayers.count else { return nil }
        return currentLayers[player.currentLayerIndex]
    }

    var currentMediaClip: MediaClip? {
        currentLayer?.mediaClip
    }

    func updateCurrentComposition(_ update: (inout Composition) -> Void) {
        var composition = currentComposition
        update(&composition)
        currentComposition = composition
    }

    func updateHypnogramDocumentSettings(_ update: (inout Hypnogram) -> Void) {
        var updatedHypnogram = hypnogram
        update(&updatedHypnogram)
        hypnogram = updatedHypnogram
    }

    func setHypnogram(_ newHypnogram: Hypnogram) {
        var normalizedHypnogram = newHypnogram
        for index in normalizedHypnogram.compositions.indices {
            normalizedHypnogram.compositions[index].syncTargetDurationToLayers()
        }

        hypnogram = normalizedHypnogram
        currentCompositionIndex = max(
            0,
            min(normalizedHypnogram.currentCompositionIndex ?? 0, max(0, normalizedHypnogram.compositions.count - 1))
        )
        syncCurrentCompositionPreviewPersistenceState()
        hypnogramRevision &+= 1
    }

    func notifyHypnogramChanged() {
        hypnogramRevision &+= 1
        player.effectsChangeCounter += 1
    }

    func notifyHypnogramMutated() {
        for index in hypnogram.compositions.indices {
            hypnogram.compositions[index].syncTargetDurationToLayers()
        }
        hypnogramRevision &+= 1
    }

    func selectSource(_ index: Int) {
        guard index >= 0, index < currentLayers.count else { return }
        player.currentLayerIndex = index
    }

    func nextSource() {
        guard !currentLayers.isEmpty else { return }
        if player.currentLayerIndex < 0 || player.currentLayerIndex >= currentLayers.count {
            player.currentLayerIndex = 0
        } else {
            player.currentLayerIndex = (player.currentLayerIndex + 1) % currentLayers.count
        }
    }

    func previousSource() {
        guard !currentLayers.isEmpty else { return }
        if player.currentLayerIndex < 0 || player.currentLayerIndex >= currentLayers.count {
            player.currentLayerIndex = 0
        } else if player.currentLayerIndex == 0 {
            player.currentLayerIndex = currentLayers.count - 1
        } else {
            player.currentLayerIndex -= 1
        }
    }

    func clampCurrentSourceIndex() {
        let maxIndex = currentLayers.count - 1
        if maxIndex < 0 {
            player.currentLayerIndex = 0
            return
        }
        if player.currentLayerIndex < 0 {
            player.currentLayerIndex = 0
            return
        }
        if player.currentLayerIndex > maxIndex {
            player.currentLayerIndex = maxIndex
        }
    }

    // MARK: - Display

    func makeDisplayView() -> AnyView {
        if isLiveMode {
            return AnyView(
                LivePlayerScreen(livePlayer: livePlayer)
            )
        }

        if hypnogram.compositions.isEmpty || currentLayers.isEmpty {
            // Avoid an infinite "generate new clip" loop when the media library is empty.
            if state.library.assetCount == 0 {
                return AnyView(NoSourcesView(state: state, main: self))
            }

            if hypnogram.compositions.isEmpty {
                replaceDefaultHypnogramWithNewComposition()
            } else if currentLayers.isEmpty {
                // Defensive: keep the current sequence shape, just replace the current composition if it is empty.
                replaceCurrentCompositionWithNewComposition()
            }
        }

        let player = activePlayer
        let composition = currentComposition

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
        let aspectRatio = currentHypnogramAspectRatio
        let displayResolution = currentHypnogramOutputResolution
        let sourceFraming = currentHypnogramSourceFraming
        let playbackEndBehavior: PlaybackEndBehavior
        let isLastCompositionInSequence =
            currentCompositionIndex >= max(0, hypnogram.compositions.count - 1)
        switch state.settings.playbackLoopMode {
        case .composition:
            playbackEndBehavior = .loopComposition
        case .sequence:
            playbackEndBehavior = .advanceAcrossCompositions(loopAtSequenceEnd: true, generateAtSequenceEnd: false)
        case .off:
            playbackEndBehavior = .advanceAcrossCompositions(
                loopAtSequenceEnd: false,
                generateAtSequenceEnd: state.settings.generateAtEnd
            )
        }
        let onCompositionEnded: (() -> Bool)? = { [weak self] in
            guard let self else { return false }
            switch playbackEndBehavior {
            case .stopAtEnd, .loopComposition:
                return false
            case .advanceAcrossCompositions(let loopAtSequenceEnd, let generateAtSequenceEnd):
                return self.advanceOrGenerateOnCompositionEnded(
                    loopSequenceAtEnd: loopAtSequenceEnd,
                    generateAtEnd: generateAtSequenceEnd
                )
            }
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
        return AnyView(
            PlayerView(
                playbackEndBehavior: playbackEndBehavior,
                isLastCompositionInSequence: isLastCompositionInSequence,
                composition: composition,
                aspectRatio: aspectRatio,
                displayResolution: displayResolution,
                sourceFraming: sourceFraming,
                onCompositionEnded: onCompositionEnded,
                currentLayerIndex: currentLayerIndexBinding,
                currentSourceTime: currentSourceTimeBinding,
                isPrimaryCompositionLoadInFlight: compositionLoadInFlightBinding,
                hasPendingGeneratedNextComposition: pendingGeneratedNextCompositionBinding,
                currentCompositionLoadFailure: Binding(
                    get: { player.currentCompositionLoadFailure },
                    set: { player.currentCompositionLoadFailure = $0 }
                ),
                pendingCompositionTransitionStyle: Binding(
                    get: { player.pendingCompositionTransitionStyle },
                    set: { player.pendingCompositionTransitionStyle = $0 }
                ),
                pendingCompositionTransitionDuration: Binding(
                    get: { player.pendingCompositionTransitionDuration },
                    set: { player.pendingCompositionTransitionDuration = $0 }
                ),
                isPaused: player.isPaused,
                effectsChangeCounter: player.effectsChangeCounter,
                hypnogramRevision: hypnogramRevision,
                effectManager: player.effectManager,
                volume: volume,
                audioDeviceUID: audioDeviceUID,
                transitionStyle: currentCompositionTransitionStyle,
                transitionDuration: currentCompositionTransitionDuration,
                sequenceTransitionStyle: currentHypnogramTransitionStyle,
                sequenceTransitionDuration: currentHypnogramTransitionDuration,
                onPlaybackStoppedAtEnd: { [weak self] in
                    self?.player.isPaused = true
                }
            )
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
        var composition = currentComposition
        composition.createdAt = createdAt
        return makeHypnogramWithCurrentHypnogramContext(
            compositions: [composition],
            currentCompositionIndex: 0,
            createdAt: createdAt
        )
    }

    func makeHypnogramWithCurrentHypnogramContext(
        compositions: [Composition],
        currentCompositionIndex: Int?,
        snapshot: String? = nil,
        createdAt: Date = Date()
    ) -> Hypnogram {
        Hypnogram(
            compositions: compositions,
            currentCompositionIndex: currentCompositionIndex,
            effectChain: currentHypnogramEffectChain,
            aspectRatio: currentHypnogramAspectRatio,
            outputResolution: currentHypnogramOutputResolution,
            sourceFraming: currentHypnogramSourceFraming,
            transitionStyle: currentHypnogramTransitionStyle,
            transitionDuration: currentHypnogramTransitionDuration,
            snapshot: snapshot,
            createdAt: createdAt
        )
    }

    var currentHypnogramAspectRatio: AspectRatio {
        resolvedAspectRatio(for: hypnogram)
    }

    var currentHypnogramOutputResolution: OutputResolution {
        resolvedOutputResolution(for: hypnogram)
    }

    var currentHypnogramSourceFraming: SourceFraming {
        resolvedSourceFraming(for: hypnogram)
    }

    var currentHypnogramTransitionStyle: TransitionRenderer.TransitionType {
        resolvedTransitionStyle(for: hypnogram)
    }

    var currentHypnogramTransitionDuration: Double {
        resolvedTransitionDuration(for: hypnogram)
    }

    private func resolvedAspectRatio(for hypnogram: Hypnogram) -> AspectRatio {
        hypnogram.aspectRatio ?? Studio.defaultAspectRatio
    }

    private func resolvedOutputResolution(for hypnogram: Hypnogram) -> OutputResolution {
        hypnogram.outputResolution
            ?? Studio.defaultPlayerResolution
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

    private func resolvedTransitionStyle(
        for composition: Composition,
        in hypnogram: Hypnogram
    ) -> TransitionRenderer.TransitionType {
        composition.transitionStyle ?? resolvedTransitionStyle(for: hypnogram)
    }

    private func resolvedTransitionDuration(
        for composition: Composition,
        in hypnogram: Hypnogram
    ) -> Double {
        composition.transitionDuration ?? resolvedTransitionDuration(for: hypnogram)
    }

    func effectiveTransitionStyle(for composition: Composition) -> TransitionRenderer.TransitionType {
        resolvedTransitionStyle(for: composition, in: hypnogram)
    }

    func effectiveTransitionDuration(for composition: Composition) -> Double {
        resolvedTransitionDuration(for: composition, in: hypnogram)
    }

    func setPendingTransition(for composition: Composition?) {
        player.pendingCompositionTransitionStyle = composition.map { effectiveTransitionStyle(for: $0) }
        player.pendingCompositionTransitionDuration = composition.map { effectiveTransitionDuration(for: $0) }
    }

    func setPendingImmediateCut() {
        player.pendingCompositionTransitionStyle = .none
        // Keep this tiny but nonzero so the no-transition path can still use the
        // existing instant-cut machinery without falling back to normal defaults.
        player.pendingCompositionTransitionDuration = 0.0001
    }

    func copyDocumentContext(from hypnogram: Hypnogram) {
        self.hypnogram.effectChain = hypnogram.effectChain.clone()
        self.hypnogram.aspectRatio = resolvedAspectRatio(for: hypnogram)
        self.hypnogram.outputResolution = resolvedOutputResolution(for: hypnogram)
        self.hypnogram.sourceFraming = resolvedSourceFraming(for: hypnogram)
        self.hypnogram.transitionStyle = resolvedTransitionStyle(for: hypnogram)
        self.hypnogram.transitionDuration = resolvedTransitionDuration(for: hypnogram)
    }

    func applyCurrentHypnogramDocumentContextToRuntime() {
        let aspectRatio = resolvedAspectRatio(for: hypnogram)
        let sourceFraming = resolvedSourceFraming(for: hypnogram)
        let composition = hypnogram.compositions.isEmpty ? nil : currentComposition
        let transitionStyle = composition.map { resolvedTransitionStyle(for: $0, in: hypnogram) }
            ?? resolvedTransitionStyle(for: hypnogram)
        let transitionDuration = composition.map { resolvedTransitionDuration(for: $0, in: hypnogram) }
            ?? resolvedTransitionDuration(for: hypnogram)

        hypnogram.effectChain = hypnogram.effectChain.clone()
        hypnogram.aspectRatio = aspectRatio
        hypnogram.outputResolution = resolvedOutputResolution(for: hypnogram)
        hypnogram.sourceFraming = sourceFraming
        hypnogram.transitionStyle = transitionStyle
        hypnogram.transitionDuration = transitionDuration

        livePlayer.aspectRatio = aspectRatio
        livePlayer.outputResolution = resolvedOutputResolution(for: hypnogram)
        livePlayer.setSourceFraming(sourceFraming)
        livePlayer.transitionType = transitionStyle
        livePlayer.crossfadeDuration = transitionDuration
    }

    var currentSaveTargetURL: URL? {
        saveTargetsByCompositionID[currentComposition.id]
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
        let validIDs = Set(hypnogram.compositions.map(\.id))
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
