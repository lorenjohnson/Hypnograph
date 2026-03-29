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
    let windows: WindowStateController
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

    /// Working file target for each composition currently present in Studio history.
    /// This stays app-local rather than becoming part of the persisted model.
    private var saveTargetsByCompositionID: [UUID: URL] = [:]

    /// The active preview player (always the preview deck)
    var activePlayer: PlayerState { player }

    /// Live mode: Edit (local preview) vs Live (mirror live display)
    enum LiveMode {
        case edit
        case live
    }

    @Published var liveMode: LiveMode = .edit

    var isLiveMode: Bool { liveMode == .live }
    var isLiveModeAvailable: Bool { state.settings.liveModeEnabled }

    // MARK: - History HUD

    /// Flash-only composition position indicator (e.g. "3/57") shown when manually navigating history.
    @Published var historyIndicatorText: String?

    var historyIndicatorClearWorkItem: DispatchWorkItem?

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
        self.windows = WindowStateController()
        self.renderQueue = renderQueue
        self.dependencies = dependencies
        self.panelHostService = dependencies.makePanelHostService()
        self.photosIntegrationService = dependencies.photosIntegrationService
        self.historyPersistenceService = dependencies.historyPersistenceService

        // One canonical effects library across modes.
        self.effectsLibrarySession = EffectsSession(filename: "effects-library.json")
        self.recentEffectsStore = RecentEffectChainsStore()

        // Create the preview player state (single deck) + live display
        self.player = PlayerState(config: state.settings.playerConfig, effectsSession: effectsLibrarySession)
        self.livePlayer = LivePlayer(settings: state.settings, effectsSession: effectsLibrarySession)

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
                self.windows.setWindowVisible("livePreview", visible: false)
                if self.livePlayer.isVisible {
                    self.livePlayer.hide()
                }
            }
            .store(in: &playerSubscriptions)

        state.settingsStore.$value
            .map(\.sourceFraming)
            .removeDuplicates()
            .sink { [weak self] framing in
                self?.livePlayer.setSourceFraming(framing)
            }
            .store(in: &playerSubscriptions)

        // Wire transition settings to LivePlayer
        state.settingsStore.$value
            .map(\.transitionStyle)
            .removeDuplicates()
            .sink { [weak self] style in
                self?.livePlayer.transitionType = style
            }
            .store(in: &playerSubscriptions)

        state.settingsStore.$value
            .map(\.transitionDuration)
            .removeDuplicates()
            .sink { [weak self] duration in
                self?.livePlayer.crossfadeDuration = duration
            }
            .store(in: &playerSubscriptions)

        // Sync player config changes back to settings
        player.$config
            .dropFirst() // Skip initial value
            .sink { [weak self] config in
                guard let self = self else { return }
                self.state.settingsStore.update { $0.playerConfig = config }
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

        // Common view parameters
        let composition = player.currentComposition
        let aspectRatio = player.config.aspectRatio
        let displayResolution = player.config.playerResolution
        let sourceFraming = state.settings.sourceFraming
        let shouldAdvanceOnClipEnd = state.settings.playbackEndBehavior == .autoAdvance
        let onCompositionEnded: (() -> Bool)? = { [weak self] in
            guard let self else { return false }
            return self.advanceOrGenerateOnCompositionEnded()
        }
        let currentLayerIndexBinding = Binding(
            get: { player.currentLayerIndex },
            set: { player.currentLayerIndex = $0 }
        )
        let currentSourceTimeBinding = Binding(
            get: { player.currentClipTimeOffset },
            set: { player.currentClipTimeOffset = $0 }
        )
        let viewID = "main-preview-\(player.config.viewID)-\(player.playRate)"

        return AnyView(
            PlayerView(
                composition: composition,
                aspectRatio: aspectRatio,
                displayResolution: displayResolution,
                sourceFraming: sourceFraming,
                autoAdvanceOnCompositionEnd: shouldAdvanceOnClipEnd,
                onCompositionEnded: onCompositionEnded,
                currentLayerIndex: currentLayerIndexBinding,
                currentSourceTime: currentSourceTimeBinding,
                isPaused: player.isPaused,
                effectsChangeCounter: player.effectsChangeCounter,
                hypnogramRevision: player.hypnogramRevision,
                effectManager: player.effectManager,
                volume: volume,
                audioDeviceUID: audioDeviceUID,
                historyPlaybackRate: timelinePlaybackRate,
                transitionStyle: state.settings.transitionStyle,
                transitionDuration: state.settings.transitionDuration
            )
            .id(viewID)
        )
    }

    /// Build a hypnogram snapshot for display/export (timestamp + effects library snapshot)
    func makeDisplayHypnogram() -> Hypnogram {
        let createdAt = Date()
        var composition = activePlayer.currentComposition
        composition.createdAt = createdAt
        return Hypnogram(compositions: [composition], createdAt: createdAt)
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

    func pruneSaveTargetsToCurrentHistory() {
        let validIDs = Set(activePlayer.hypnogram.compositions.map(\.id))
        saveTargetsByCompositionID = saveTargetsByCompositionID.filter { validIDs.contains($0.key) }
    }

}
