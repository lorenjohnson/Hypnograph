//
//  Dream.swift
//  Hypnograph
//
//  Dream feature: video/image composition with a single preview path.
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
final class Dream: ObservableObject {
    let state: HypnographState
    let renderQueue: RenderEngine.ExportQueue

    /// Global templates store (shared across preview + live)
    let effectsLibrarySession: EffectsSession

    /// Global RECENT effects store (shared across preview + live)
    let recentEffectsStore: RecentEffectChainsStore

    // MARK: - Player States

    /// Preview deck - a layered clip
    let player: DreamPlayerState

    /// Live display - external monitor output (moved from HypnographState)
    let livePlayer: LivePlayer

    /// Subscriptions to forward player state changes to Dream's objectWillChange
    private var playerSubscriptions: Set<AnyCancellable> = []

    /// The active preview player (always the preview deck)
    var activePlayer: DreamPlayerState { player }

    /// Live mode: Edit (local preview) vs Live (mirror live display)
    enum LiveMode {
        case edit
        case live
    }

    @Published var liveMode: LiveMode = .edit

    var isLiveMode: Bool { liveMode == .live }
    var isLiveModeAvailable: Bool { state.settings.liveModeEnabled }

    // MARK: - Clip History HUD

    /// Flash-only clip position indicator (e.g. "3/57") shown when manually navigating history.
    @Published private(set) var clipHistoryIndicatorText: String?

    private var clipHistoryIndicatorClearWorkItem: DispatchWorkItem?

    // MARK: - Clip History Persistence

    private var clipHistorySaveTimer: Timer?
    private var clipHistorySaveCancellables: Set<AnyCancellable> = []

    // MARK: - Audio Output

    /// Audio controller manages device selection and volume for preview/live
    let audioController: DreamAudioController

    /// Convenience accessors for audio state (forwarded from controller)
    var previewAudioDevice: AudioOutputDevice? {
        get { audioController.previewAudioDevice }
        set { audioController.previewAudioDevice = newValue }
    }

    var liveAudioDevice: AudioOutputDevice? {
        get { audioController.liveAudioDevice }
        set { audioController.liveAudioDevice = newValue }
    }

    var previewVolume: Float {
        get { audioController.previewVolume }
        set { audioController.previewVolume = newValue }
    }

    var liveVolume: Float {
        get { audioController.liveVolume }
        set { audioController.liveVolume = newValue }
    }

    var previewAudioDeviceUID: String? { audioController.previewAudioDeviceUID }
    var liveAudioDeviceUID: String? { audioController.liveAudioDeviceUID }

    /// Returns the active EffectManager based on live mode
    /// In live mode, effects go to the live display; in edit mode, to the active player
    var activeEffectManager: EffectManager {
        isLiveMode ? livePlayer.effectManager : activePlayer.effectManager
    }

    /// Returns the active EffectsSession based on live mode
    /// In Step 4 (MVR), templates are global across modes.
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

    init(state: HypnographState, renderQueue: RenderEngine.ExportQueue) {
        self.state = state
        self.renderQueue = renderQueue

        // Step 4 (MVR): one canonical library store across modes (no migration).
        // This points all template browsing/apply to the same file going forward.
        self.effectsLibrarySession = EffectsSession(filename: "effects-library.json")
        self.recentEffectsStore = RecentEffectChainsStore()

        // Create the preview player state (single deck) + live display
        self.player = DreamPlayerState(config: state.settings.playerConfig, effectsSession: effectsLibrarySession)
        self.livePlayer = LivePlayer(settings: state.settings, effectsSession: effectsLibrarySession)

        // Wire RECENT store into all effect managers
        player.effectManager.recentStore = recentEffectsStore
        livePlayer.effectManager.recentStore = recentEffectsStore

        // Create audio controller (handles device selection, volume, persistence)
        self.audioController = DreamAudioController(settingsStore: state.settingsStore, livePlayer: livePlayer)

        // Forward player state changes to Dream's objectWillChange for SwiftUI reactivity
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
                self.state.windowState.set("livePreview", visible: false)
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

        // Restore clip history if available
        restoreClipHistory()

        // Save clip history when app terminates and on edits
        setupClipHistoryPersistence()
    }

    // MARK: - Clip History Persistence

    private func setupClipHistoryPersistence() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveClipHistory(synchronous: true)
                self?.state.settingsStore.save(synchronous: true)
            }
        }

        player.$sessionRevision
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleClipHistorySave()
            }
            .store(in: &clipHistorySaveCancellables)

        player.$currentHypnogramIndex
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleClipHistorySave()
            }
            .store(in: &clipHistorySaveCancellables)
    }

    private func scheduleClipHistorySave() {
        clipHistorySaveTimer?.invalidate()
        clipHistorySaveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveClipHistory(synchronous: false)
            }
        }
    }

    func saveClipHistory(synchronous: Bool) {
        let url = Environment.clipHistoryURL
        let history = ClipHistoryFile(
            hypnograms: player.session.hypnograms,
            currentHypnogramIndex: player.currentHypnogramIndex
        )

        if synchronous {
            do {
                try ClipHistoryIO.save(history, url: url, historyLimit: state.settings.historyLimit)
            } catch {
                print("⚠️ Dream: Failed to save clip history (sync): \(error)")
            }
            return
        }

        let historyLimit = state.settings.historyLimit
        DispatchQueue.global(qos: .utility).async {
            do {
                try ClipHistoryIO.save(history, url: url, historyLimit: historyLimit)
            } catch {
                print("⚠️ Dream: Failed to save clip history: \(error)")
            }
        }
    }

    /// Restore persisted clip history (preview deck).
    private func restoreClipHistory() {
        if let history = ClipHistoryIO.load(url: Environment.clipHistoryURL, historyLimit: state.settings.historyLimit),
           !history.hypnograms.isEmpty {
            let session = HypnographSession(hypnograms: history.hypnograms)
            player.session = session
            player.currentHypnogramIndex = history.currentHypnogramIndex
            player.notifySessionMutated()
            player.currentSourceIndex = -1
            player.effectManager.clearFrameBuffer()
            player.notifySessionChanged()
            print("📼 Restored clip history (\(history.hypnograms.count) hypnograms)")
            return
        }

        // Default: start a fresh history with one generated clip.
        replaceHistoryWithNewClip()
    }

    /// Build export settings on-demand with current player config
    private func exportSettings() -> CGSize {
        let outputSize = renderSize(
            aspectRatio: activePlayer.config.aspectRatio,
            maxDimension: activePlayer.config.playerResolution.maxDimension
        )
        return outputSize
    }

    // MARK: - Shared helpers

    private var sourceCount: Int { activePlayer.activeLayerCount }

    private var currentDisplayIndex: Int {
        sourceCount > 0 ? activePlayer.currentSourceIndex + 1 : 0
    }

    var currentClipIndicatorText: String {
        let clips = player.session.hypnograms
        guard !clips.isEmpty else { return "Clip --" }
        let displayIndex = max(0, min(player.currentHypnogramIndex, clips.count - 1)) + 1
        return "Clip \(displayIndex)"
    }

    var isLoopCurrentClipEnabled: Bool {
        state.settings.playbackEndBehavior == .loopCurrentClip
    }

    // MARK: - Clip History

    private func makeRandomClip(preservingGlobalEffectFrom previous: Hypnogram?) -> Hypnogram {
        let clipLengthMin = max(0.1, state.settings.clipLengthMinSeconds)
        let clipLengthMax = max(clipLengthMin, state.settings.clipLengthMaxSeconds)
        let clipLengthSeconds = Double.random(in: clipLengthMin...clipLengthMax)
        let targetDuration = CMTime(seconds: clipLengthSeconds, preferredTimescale: 600)
        let playRateBounds: ClosedRange<Double> = 0.2...2.0
        let configuredPlayRateMin = min(max(state.settings.clipPlayRateMin, playRateBounds.lowerBound), playRateBounds.upperBound)
        let configuredPlayRateMax = min(max(state.settings.clipPlayRateMax, playRateBounds.lowerBound), playRateBounds.upperBound)
        let playRateMin = min(configuredPlayRateMin, configuredPlayRateMax)
        let playRateMax = max(configuredPlayRateMin, configuredPlayRateMax)
        let selectedPlayRate: Float = {
            guard playRateMax > playRateMin else { return Float(playRateMin) }
            let randomRate = Double.random(in: playRateMin...playRateMax)
            let steppedRate = (randomRate * 10).rounded() / 10
            return Float(min(max(steppedRate, playRateBounds.lowerBound), playRateBounds.upperBound))
        }()

        let maxLayers = max(1, player.config.maxLayers)
        let layerCount = Int.random(in: 1...maxLayers)
        let randomTemplates = effectsLibrarySession.chains.filter { $0.hasEnabledEffects }

        func shouldApplyRandomizedEffect(enabled: Bool, frequency: Double) -> Bool {
            guard enabled else { return false }
            let chance = min(max(frequency, 0), 1)
            guard chance > 0 else { return false }
            return Double.random(in: 0...1) < chance
        }

        func randomTemplateChain() -> EffectChain? {
            guard let template = randomTemplates.randomElement() else { return nil }
            return EffectChain(duplicating: template, sourceTemplateId: template.id)
        }

        var globalEffectChain = previous?.effectChain.clone()
        if shouldApplyRandomizedEffect(
            enabled: state.settings.randomGlobalEffect,
            frequency: state.settings.randomGlobalEffectFrequency
        ) {
            globalEffectChain = randomTemplateChain() ?? globalEffectChain
        }

        var layers: [HypnogramLayer] = []
        layers.reserveCapacity(layerCount)

        for i in 0..<layerCount {
            guard let mediaClip = state.library.randomClip(clipLength: targetDuration.seconds) else { continue }
            let blendMode = (i == 0) ? BlendMode.sourceOver : BlendMode.defaultMontage
            let layerEffectChain: EffectChain
            if shouldApplyRandomizedEffect(
                enabled: state.settings.randomLayerEffect,
                frequency: state.settings.randomLayerEffectFrequency
            ) {
                layerEffectChain = randomTemplateChain() ?? EffectChain()
            } else {
                layerEffectChain = EffectChain()
            }

            layers.append(
                HypnogramLayer(
                    mediaClip: mediaClip,
                    blendMode: blendMode,
                    effectChain: layerEffectChain
                )
            )
        }

        return Hypnogram(
            layers: layers,
            targetDuration: targetDuration,
            playRate: selectedPlayRate,
            effectChain: globalEffectChain,
            createdAt: Date()
        )
    }

    private func enforceHistoryLimit() {
        let limit = max(1, state.settings.historyLimit)
        let overflow = max(0, player.session.hypnograms.count - limit)
        guard overflow > 0 else { return }

        player.session.hypnograms.removeFirst(overflow)
        player.currentHypnogramIndex = max(0, player.currentHypnogramIndex - overflow)
        player.notifySessionMutated()
    }

    private func applyClipSelectionChanged(manual: Bool) {
        player.clampCurrentSourceIndex()
        player.currentClipTimeOffset = nil
        player.effectManager.clearFrameBuffer()
        player.effectManager.invalidateBlendAnalysis()
        player.notifySessionChanged()

        if manual {
            flashClipHistoryIndicator()
        }
    }

    private func replaceHistoryWithNewClip() {
        let hypnogram = makeRandomClip(preservingGlobalEffectFrom: nil)
        player.session = HypnographSession(hypnograms: [hypnogram])
        player.currentHypnogramIndex = 0
        player.currentSourceIndex = -1
        player.notifySessionMutated()
        applyClipSelectionChanged(manual: false)
    }

    private func replaceCurrentClipWithNewClip(manual: Bool = false) {
        let hypnogram = makeRandomClip(preservingGlobalEffectFrom: player.currentHypnogram)
        player.currentHypnogram = hypnogram
        player.currentSourceIndex = -1
        applyClipSelectionChanged(manual: manual)
    }

    private func appendNewClipAndSelect(manual: Bool) {
        let hypnogram = makeRandomClip(preservingGlobalEffectFrom: player.currentHypnogram)
        player.session.hypnograms.append(hypnogram)
        player.currentHypnogramIndex = player.session.hypnograms.count - 1
        player.currentSourceIndex = -1
        player.notifySessionMutated()
        enforceHistoryLimit()
        applyClipSelectionChanged(manual: manual)
    }

    private func advanceOrGenerateOnClipEnded() {
        if state.settings.playbackEndBehavior == .autoAdvance {
            let nextIndex = player.currentHypnogramIndex + 1
            if nextIndex < player.session.hypnograms.count {
                player.currentHypnogramIndex = nextIndex
                applyClipSelectionChanged(manual: false)
            } else {
                appendNewClipAndSelect(manual: false)
            }
            return
        }
    }

    func previousClip() {
        guard player.currentHypnogramIndex > 0 else { return }
        player.currentHypnogramIndex -= 1
        applyClipSelectionChanged(manual: true)
    }

    func nextClip() {
        let nextIndex = player.currentHypnogramIndex + 1
        if nextIndex < player.session.hypnograms.count {
            player.currentHypnogramIndex = nextIndex
            applyClipSelectionChanged(manual: true)
        } else {
            // At end of history: treat "next" as "new hypnogram"
            new()
        }
    }

    func deleteCurrentClip() {
        guard !player.session.hypnograms.isEmpty else { return }

        if player.session.hypnograms.count == 1 {
            replaceHistoryWithNewClip()
            applyClipSelectionChanged(manual: true)
            return
        }

        let index = player.currentHypnogramIndex
        player.session.hypnograms.remove(at: index)
        if player.currentHypnogramIndex >= player.session.hypnograms.count {
            player.currentHypnogramIndex = max(0, player.session.hypnograms.count - 1)
        }
        player.notifySessionMutated()
        applyClipSelectionChanged(manual: true)
    }

    func clearClipHistory() {
        let hypnogram = player.currentHypnogram
        player.session = HypnographSession(hypnograms: [hypnogram])
        player.currentHypnogramIndex = 0
        player.notifySessionMutated()
        applyClipSelectionChanged(manual: true)
    }

    private func flashClipHistoryIndicator() {
        guard !player.session.hypnograms.isEmpty else { return }
        clipHistoryIndicatorText = "\(player.currentHypnogramIndex + 1)/\(player.session.hypnograms.count)"

        clipHistoryIndicatorClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.clipHistoryIndicatorText = nil
        }
        clipHistoryIndicatorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    /// Add a source to the given player
    private func addSourceToPlayer(_ player: DreamPlayerState, length: Double? = nil) {
        // Use default clip length if not provided
        let clipLength = length ?? player.targetDuration.seconds
        guard let mediaClip = state.library.randomClip(clipLength: clipLength) else { return }
        addSourceToPlayer(player, mediaClip: mediaClip)
    }

    /// Add a specific clip as a new source layer.
    private func addSourceToPlayer(_ player: DreamPlayerState, mediaClip: MediaClip) {
        let blendMode = player.layers.isEmpty ? BlendMode.sourceOver : BlendMode.defaultMontage
        let layer = HypnogramLayer(mediaClip: mediaClip, blendMode: blendMode)
        player.layers.append(layer)
        player.currentSourceIndex = player.layers.count - 1
    }

    /// Build a clip from a local file URL (image or video).
    private func makeClip(forFileURL url: URL, preferredLength: Double) -> MediaClip? {
        let targetLength = max(0.1, preferredLength)

        let videoAsset = AVURLAsset(url: url)
        let totalVideoSeconds = videoAsset.duration.seconds
        let hasVideoTrack = videoAsset.tracks(withMediaType: .video).first != nil
        if hasVideoTrack, totalVideoSeconds.isFinite, totalVideoSeconds > 0, videoAsset.isPlayable {
            let clipLength = min(targetLength, totalVideoSeconds)
            let source = MediaSource.url(url)
            let file = MediaFile(
                source: source,
                mediaKind: .video,
                duration: CMTime(seconds: totalVideoSeconds, preferredTimescale: 600)
            )
            return MediaClip(
                file: file,
                startTime: .zero,
                duration: CMTime(seconds: clipLength, preferredTimescale: 600)
            )
        }

        guard let image = StillImageCache.ciImage(for: url), !image.extent.isEmpty else {
            return nil
        }

        let source = MediaSource.url(url)
        let imageDuration = CMTime(seconds: targetLength, preferredTimescale: 600)
        let file = MediaFile(source: source, mediaKind: .image, duration: imageDuration)
        return MediaClip(file: file, startTime: .zero, duration: imageDuration)
    }

    /// Build a clip from a Photos asset identifier (image or video).
    private func makeClip(forPhotosAssetIdentifier identifier: String, preferredLength: Double) -> MediaClip? {
        guard ApplePhotos.shared.status.canRead else { return nil }
        guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else { return nil }

        let targetLength = max(0.1, preferredLength)
        let source = MediaSource.external(identifier: identifier)

        switch asset.mediaType {
        case .video:
            let totalVideoSeconds = asset.duration
            guard totalVideoSeconds.isFinite, totalVideoSeconds > 0 else { return nil }
            let clipLength = min(targetLength, totalVideoSeconds)
            let file = MediaFile(
                source: source,
                mediaKind: .video,
                duration: CMTime(seconds: totalVideoSeconds, preferredTimescale: 600)
            )
            return MediaClip(
                file: file,
                startTime: .zero,
                duration: CMTime(seconds: clipLength, preferredTimescale: 600)
            )

        case .image:
            let imageDuration = CMTime(seconds: targetLength, preferredTimescale: 600)
            let file = MediaFile(source: source, mediaKind: .image, duration: imageDuration)
            return MediaClip(file: file, startTime: .zero, duration: imageDuration)

        default:
            return nil
        }
    }

    // MARK: - Layer Navigation
    // Note: Flash solo is handled by NSEvent key hold detection in HypnographAppDelegate

    func nextSource() {
        activePlayer.nextSource()
    }

    func previousSource() {
        activePlayer.previousSource()
    }

    func selectSource(index: Int) {
        activePlayer.selectSource(index)
    }

    // MARK: - Layer Trim

    /// Update a specific layer's clip range (video only).
    /// `startSeconds...endSeconds` are absolute offsets within the source media file.
    func setLayerClipRange(
        sourceIndex: Int,
        startSeconds: Double,
        endSeconds: Double,
        maxDurationSeconds: Double? = nil
    ) {
        guard sourceIndex >= 0, sourceIndex < activePlayer.layers.count else { return }

        var layers = activePlayer.layers
        var layer = layers[sourceIndex]
        guard layer.mediaClip.file.mediaKind == .video else { return }

        let totalSeconds = max(0.1, layer.mediaClip.file.duration.seconds)
        let minimumDuration = min(0.1, totalSeconds)
        let maxWindow = max(
            minimumDuration,
            min(totalSeconds, maxDurationSeconds ?? totalSeconds)
        )

        var clampedStart = max(0, min(startSeconds, totalSeconds - minimumDuration))
        var clampedEnd = max(clampedStart + minimumDuration, min(endSeconds, totalSeconds))

        if (clampedEnd - clampedStart) > maxWindow {
            clampedEnd = clampedStart + maxWindow
            if clampedEnd > totalSeconds {
                clampedEnd = totalSeconds
                clampedStart = max(0, clampedEnd - maxWindow)
            }
        }

        let newDuration = min(maxWindow, max(minimumDuration, clampedEnd - clampedStart))

        layer.mediaClip = MediaClip(
            file: layer.mediaClip.file,
            startTime: CMTime(seconds: clampedStart, preferredTimescale: 600),
            duration: CMTime(seconds: newDuration, preferredTimescale: 600)
        )

        layers[sourceIndex] = layer
        activePlayer.layers = layers
        activePlayer.currentClipTimeOffset = nil
    }

    /// Update the currently selected layer's clip range (video only).
    /// `startSeconds...endSeconds` are absolute offsets within the source media file.
    func setCurrentLayerClipRange(
        startSeconds: Double,
        endSeconds: Double,
        maxDurationSeconds: Double? = nil
    ) {
        setLayerClipRange(
            sourceIndex: activePlayer.currentSourceIndex,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            maxDurationSeconds: maxDurationSeconds
        )
    }

    // MARK: - Effects

    /// Cycle effect for current layer (global when -1, source when 0+)
    func cycleEffect(direction: Int = 1) {
        activeEffectManager.cycleEffect(for: activePlayer.currentSourceIndex, direction: direction)

        let effectName = activeEffectManager.effectName(for: activePlayer.currentSourceIndex)
        let layerLabel = activePlayer.currentSourceIndex == -1 ? "Global" : "Source \(activePlayer.currentSourceIndex + 1)"
        AppNotifications.show("\(layerLabel): \(effectName)", flash: true, duration: 1.5)
    }

    /// Clear effect for current layer only
    func clearCurrentLayerEffect() {
        activeEffectManager.clearEffect(for: activePlayer.currentSourceIndex)

        let layerLabel = activePlayer.currentSourceIndex == -1 ? "Global" : "Source \(activePlayer.currentSourceIndex + 1)"
        AppNotifications.show("\(layerLabel): None", flash: true, duration: 1.5)
    }

    // MARK: - Settings helpers

    func setAspectRatio(_ ratio: AspectRatio) {
        activePlayer.config.aspectRatio = ratio
        // Config changes are auto-saved via $config subscription
        // Notify Dream to update menus
        objectWillChange.send()
    }

    func setOutputResolution(_ resolution: OutputResolution) {
        activePlayer.config.playerResolution = resolution
        // Also update in settings for persistence
        state.settingsStore.update { $0.outputResolution = resolution }
        // Notify Dream to update menus
        objectWillChange.send()
    }

    // MARK: - Display

    func makeDisplayView() -> AnyView {
        if isLiveMode {
            return AnyView(
                LivePlayerScreen(livePlayer: livePlayer)
                    .id("dream-live-\(livePlayer.config.viewID)")
            )
        }

        if activePlayer.session.hypnograms.isEmpty || activePlayer.layers.isEmpty {
            // Avoid an infinite "generate new clip" loop when the media library is empty.
            if state.library.assetCount == 0 {
                return AnyView(NoSourcesView(state: state))
            }

            if activePlayer.session.hypnograms.isEmpty {
                replaceHistoryWithNewClip()
            } else if activePlayer.layers.isEmpty {
                // Defensive: keep history shape, just replace the current clip if it is empty.
                replaceCurrentClipWithNewClip()
            }
        }

        let player = activePlayer

        // Common view parameters
        let clip = player.currentHypnogram
        let aspectRatio = player.config.aspectRatio
        let displayResolution = player.config.playerResolution
        let sourceFraming = state.settings.sourceFraming
        let shouldAdvanceOnClipEnd = state.settings.playbackEndBehavior == .autoAdvance
        let onClipEnded: (() -> Void)? = { [weak self] in
            guard let self else { return }
            self.advanceOrGenerateOnClipEnded()
        }
        let currentSourceIndexBinding = Binding(
            get: { player.currentSourceIndex },
            set: { player.currentSourceIndex = $0 }
        )
        let currentSourceTimeBinding = Binding(
            get: { player.currentClipTimeOffset },
            set: { player.currentClipTimeOffset = $0 }
        )
        let viewID = "dream-preview-\(player.config.viewID)-\(player.playRate)"

        return AnyView(
            PreviewPlayerView(
                clip: clip,
                aspectRatio: aspectRatio,
                displayResolution: displayResolution,
                sourceFraming: sourceFraming,
                autoAdvanceOnClipEnd: shouldAdvanceOnClipEnd,
                onClipEnded: onClipEnded,
                currentSourceIndex: currentSourceIndexBinding,
                currentSourceTime: currentSourceTimeBinding,
                isPaused: player.isPaused,
                effectsChangeCounter: player.effectsChangeCounter,
                sessionRevision: player.sessionRevision,
                effectManager: player.effectManager,
                volume: previewVolume,
                audioDeviceUID: previewAudioDeviceUID,
                transitionStyle: state.settings.transitionStyle,
                transitionDuration: state.settings.transitionDuration
            )
            .id(viewID)
        )
    }

    /// The live session from the active player - use for direct access/mutation
    var currentSession: HypnographSession {
        get { activePlayer.session }
        set { activePlayer.session = newValue }
    }

    /// Build a session snapshot for display/export (timestamp + effects library snapshot)
    func makeDisplaySession() -> HypnographSession {
        let createdAt = Date()
        var hypnogram = activePlayer.currentHypnogram
        hypnogram.createdAt = createdAt
        return HypnographSession(hypnograms: [hypnogram], createdAt: createdAt)
    }

    // MARK: - Lifecycle

    func new() {
        // Clear frame buffer to prevent memory bloat from stored CIImages
        activePlayer.effectManager.clearFrameBuffer()

        // Clear image cache if it's getting large to prevent memory bloat
        let cacheSize = StillImageCache.cacheSize()
        if cacheSize.ciImages > 30 || cacheSize.cgImages > 30 {
            StillImageCache.clear()
        }

        appendNewClipAndSelect(manual: true)
    }

    /// Send current hypnogram to live display
    func sendToLivePlayer() {
        livePlayer.send(
            clip: activePlayer.currentHypnogram.copyForExport(),
            config: activePlayer.config
        )
    }

    func toggleHUD() {
        state.windowState.toggle("hud")
    }

    func togglePause() {
        activePlayer.togglePause()
    }

    func toggleLoopCurrentClipMode() {
        state.toggleLoopCurrentClipMode()
    }

    func addSource() {
        addSourceToPlayer(activePlayer)
    }

    /// Add a source layer from an explicit local file.
    @discardableResult
    func addSource(fromFileURL url: URL) -> Bool {
        guard let mediaClip = makeClip(forFileURL: url, preferredLength: activePlayer.targetDuration.seconds) else {
            AppNotifications.show("Couldn't add source from file", flash: true, duration: 1.5)
            return false
        }
        addSourceToPlayer(activePlayer, mediaClip: mediaClip)
        return true
    }

    /// Add a source layer from an explicit Photos asset identifier.
    @discardableResult
    func addSource(fromPhotosAssetIdentifier identifier: String) -> Bool {
        guard let mediaClip = makeClip(forPhotosAssetIdentifier: identifier, preferredLength: activePlayer.targetDuration.seconds) else {
            AppNotifications.show("Couldn't add source from Photos", flash: true, duration: 1.5)
            return false
        }
        addSourceToPlayer(activePlayer, mediaClip: mediaClip)
        return true
    }

    func newRandomClip() {
        replaceClipForCurrentSource()
    }

    func removeCurrentLayer() {
        let idx: Int
        if activePlayer.currentSourceIndex == -1 {
            if activePlayer.layers.count == 1 {
                idx = 0
            } else {
                if activePlayer.layers.isEmpty {
                    AppNotifications.show("No layers selected", flash: true, duration: 1.25)
                } else {
                    AppNotifications.show("Select a layer (1-9)", flash: true, duration: 1.25)
                }
                return
            }
        } else {
            idx = activePlayer.currentSourceIndex
        }

        guard idx >= 0, idx < activePlayer.layers.count else { return }

        // If this is the only source, "delete source" should behave like other
        // per-layer curation: replace the layer with a new random source.
        if activePlayer.layers.count == 1 {
            replaceClip(forSourceIndex: idx)
            return
        }

        activePlayer.layers.remove(at: idx)

        if idx >= activePlayer.layers.count {
            activePlayer.currentSourceIndex = activePlayer.layers.count - 1
        }
    }

    func duplicateCurrentLayer() {
        let idx: Int
        if activePlayer.currentSourceIndex == -1 {
            if activePlayer.layers.count == 1 {
                idx = 0
            } else {
                if activePlayer.layers.isEmpty {
                    AppNotifications.show("No layers to duplicate", flash: true, duration: 1.25)
                } else {
                    AppNotifications.show("Select a layer (1-9)", flash: true, duration: 1.25)
                }
                return
            }
        } else {
            idx = activePlayer.currentSourceIndex
        }

        guard idx >= 0, idx < activePlayer.layers.count else { return }

        let duplicatedLayer = duplicatedLayerWithNewFileID(from: activePlayer.layers[idx])
        let insertIndex = idx + 1
        activePlayer.layers.insert(duplicatedLayer, at: insertIndex)
        activePlayer.currentSourceIndex = insertIndex
    }

    private func duplicatedLayerWithNewFileID(from layer: HypnogramLayer) -> HypnogramLayer {
        let sourceFile = layer.mediaClip.file
        let duplicatedFile = MediaFile(
            source: sourceFile.source,
            mediaKind: sourceFile.mediaKind,
            duration: sourceFile.duration
        )
        let duplicatedClip = MediaClip(
            file: duplicatedFile,
            startTime: layer.mediaClip.startTime,
            duration: layer.mediaClip.duration
        )

        var duplicatedLayer = layer
        duplicatedLayer.mediaClip = duplicatedClip
        return duplicatedLayer
    }

    /// Replace the clip for current source with a new random one
    private func replaceClipForCurrentSource() {
        let idx = activePlayer.currentSourceIndex
        replaceClip(forSourceIndex: idx)
    }

    private func replaceClip(forSourceIndex idx: Int) {
        guard idx >= 0, idx < activePlayer.layers.count else { return }
        guard let mediaClip = state.library.randomClip(clipLength: activePlayer.targetDuration.seconds) else { return }
        activePlayer.layers[idx].mediaClip = mediaClip
    }

    private func currentFrameSnapshot() -> CGImage? {
        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            return nil
        }

        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace)
    }

    /// Save current hypnogram: snapshot with embedded recipe (.hypno file)
    /// This is the main save action (S / Cmd-S)
    func save() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Dream: no current frame available for save")
            return
        }

        print("Dream: saving hypnogram...")

        // Get the current session with effects library snapshot
        let session = makeDisplaySession().copyForExport()

        // Save as .hypno and record in HypnogramStore (powers Favorites/Recents panel).
        if let entry = HypnogramStore.shared.add(session: session, snapshot: cgImage, isFavorite: false) {
            print("✅ Dream: Hypnogram saved to \(entry.sessionURL.path)")
            AppNotifications.show("Hypnogram saved", flash: true)

            // Also save to Apple Photos if write access is available
            if ApplePhotos.shared.status.canWrite {
                Task {
                    let success = await ApplePhotos.shared.saveImage(at: entry.sessionURL)
                    if success {
                        print("✅ Dream: Hypnogram added to Apple Photos")
                    }
                }
            }
        } else {
            print("Dream: failed to save hypnogram")
            AppNotifications.show("Failed to save", flash: true)
        }
    }

    /// Render and save the hypnogram as a video file (enqueue to render queue)
    /// This is the legacy save behavior - available in menu without hotkey
    func renderAndSaveVideo() {
        guard !activePlayer.layers.isEmpty else {
            print("Dream: no sources to render.")
            return
        }

        // Deep copy clip with fresh effect instances to avoid sharing state with preview
        let renderHypnogram = activePlayer.currentHypnogram.copyForExport()

        // Create renderer with current settings (aspect ratio + resolution)
        let outputSize = exportSettings()

        print("Dream: enqueueing clip with \(renderHypnogram.layers.count) layer(s), duration: \(renderHypnogram.targetDuration.seconds)s")

        // Enqueue immediately (don't defer - the renderer handles async internally)
        // RenderEngine.ExportQueue provides status messages via onStatusMessage callback
        renderQueue.enqueue(
            clip: renderHypnogram,
            outputFolder: state.settings.outputURL,
            outputSize: outputSize,
            sourceFraming: state.settings.sourceFraming
        )

        // Reset for next hypnogram
        // Defer this to avoid modifying @Published during button action
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.new()
        }
    }

    /// Save hypnogram to a specific location (with file picker)
    func saveAs() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Dream: no current frame available for save")
            return
        }

        let session = makeDisplaySession().copyForExport()
        SessionFileActions.saveAs(session: session, snapshot: cgImage) {
            AppNotifications.show("Hypnogram saved", flash: true)
        }
    }

    /// Open a .hypno or .hypnogram recipe file
    func openRecipe() {
        SessionFileActions.openSession(
            onLoaded: { [weak self] session in
                self?.appendSessionToHistory(session)
                AppNotifications.show("Recipe loaded", flash: true)
            },
            onFailure: {
                AppNotifications.show("Failed to load recipe", flash: true)
            }
        )
    }

    private func appendLoadedHypnograms(_ hypnograms: [Hypnogram]) {
        let oldCount = activePlayer.session.hypnograms.count
        activePlayer.session.hypnograms.append(contentsOf: hypnograms)
        activePlayer.currentHypnogramIndex = oldCount
        activePlayer.currentSourceIndex = -1
        activePlayer.notifySessionMutated()
        enforceHistoryLimit()
        applyClipSelectionChanged(manual: true)
    }

    /// Load a recipe into the current player.
    /// Loaded clips are always appended to history.
    func appendSessionToHistory(_ session: HypnographSession) {
        // Ensure effect chains have names (required for library matching)
        var mutableSession = session
        mutableSession.ensureEffectChainNames()

        // Ensure we're editing the preview deck
        liveMode = .edit

        let loadedHypnograms = mutableSession.hypnograms
        guard !loadedHypnograms.isEmpty else { return }

        // Import effect chains used in the recipe into the session
        // (adds missing chains, replaces same-named chains with recipe versions)
        EffectChainLibraryActions.importChainsFromSession(mutableSession, into: effectsSession)

        appendLoadedHypnograms(loadedHypnograms)
    }

    /// Favorite the current hypnogram (save to store as favorite)
    func favoriteCurrentHypnogram() {
        guard !activePlayer.layers.isEmpty else {
            print("Dream: no sources to favorite")
            return
        }

        // Grab current frame for snapshot
        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            print("Dream: no current frame available for favorite")
            return
        }

        // Convert CIImage to CGImage
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace) else {
            print("Dream: failed to convert CIImage to CGImage for favorite")
            return
        }

        if let entry = HypnogramStore.shared.add(
            session: makeDisplaySession(),
            snapshot: cgImage,
            isFavorite: true
        ) {
            AppNotifications.show("Added to favorites: \(entry.name)", flash: true)
        }
    }

    // MARK: - Montage blend modes

    private func blendModeForSourceIndex(_ idx: Int) -> String {
        guard idx >= 0, idx < activePlayer.layers.count else { return BlendMode.sourceOver }
        return activePlayer.layers[idx].blendMode ?? (idx == 0 ? BlendMode.sourceOver : BlendMode.defaultMontage)
    }

    func currentBlendModeDisplayName() -> String {
        blendModeForSourceIndex(activePlayer.currentSourceIndex)
            .replacingOccurrences(of: "CI", with: "")
            .replacingOccurrences(of: "BlendMode", with: "")
    }

    func cycleBlendMode(at index: Int? = nil) {
        let idx = index ?? activePlayer.currentSourceIndex
        guard idx > 0, idx < activePlayer.layers.count else { return } // bottom layer stays SourceOver

        // Cycle blend mode - this writes directly to sources via the setter closure
        activePlayer.effectManager.cycleBlendMode(for: idx)
    }



    // MARK: - Effects

    /// Clear all effects AND reset blend modes to Screen (default)
    func clearAllEffects() {
        activeEffectManager.clearEffect(for: -1)  // Global

        // Get source count from appropriate context
        let sourceCount = isLiveMode
            ? livePlayer.activeLayerCount
            : activePlayer.activeLayerCount

        for i in 0..<sourceCount {
            activeEffectManager.clearEffect(for: i)
            // Reset blend mode on source (keep first one as SourceOver) - only in Edit mode
            if !isLiveMode && i > 0 && i < activePlayer.layers.count {
                activePlayer.layers[i].blendMode = BlendMode.defaultMontage
            }
        }
    }

    // MARK: - Source Management Helpers

    /// Exclude current source from library
    func excludeCurrentSource() {
        curateCurrentSource(.excluded)
    }

    func favoriteCurrentSource() {
        curateCurrentSource(.favorited)
    }

    private enum SourceCurationAction {
        case excluded
        case favorited

        var notification: String {
            switch self {
            case .excluded: return "Source excluded"
            case .favorited: return "Favorite added"
            }
        }

        var failureNotification: String {
            switch self {
            case .excluded: return "Failed to exclude source"
            case .favorited: return "Failed to add favorite"
            }
        }
    }

    private func resolveSelectedSourceIndexForCuration() -> Int? {
        if activePlayer.currentSourceIndex == -1 {
            if activePlayer.layers.count == 1 {
                return 0
            }
            return nil
        }
        return activePlayer.currentSourceIndex
    }

    private func curateCurrentSource(_ action: SourceCurationAction) {
        guard let idx = resolveSelectedSourceIndexForCuration() else {
            if activePlayer.layers.isEmpty {
                AppNotifications.show("No layers selected", flash: true, duration: 1.25)
            } else {
                AppNotifications.show("Select a layer (1-9)", flash: true, duration: 1.25)
            }
            return
        }

        guard idx >= 0, idx < activePlayer.layers.count else {
            AppNotifications.show("No layer selected", flash: true, duration: 1.25)
            return
        }

        let file = activePlayer.layers[idx].mediaClip.file

        switch file.source {
        case .url:
            switch action {
            case .excluded:
                state.library.exclude(file: file)
                replaceClip(forSourceIndex: idx)
            case .favorited:
                state.sourceFavoritesStore.add(file.source)
            }

            AppNotifications.show(action.notification, flash: true)

        case .external(let identifier):
            ApplePhotos.shared.refreshStatus()
            guard ApplePhotos.shared.status.canWrite else {
                if action == .favorited {
                    AppNotifications.show("Photos permission required", flash: true, duration: 1.25)
                } else {
                    replaceClip(forSourceIndex: idx)
                    state.library.removeFromIndex(source: file.source)
                    AppNotifications.show("Photos permission required", flash: true, duration: 1.25)
                }
                return
            }

            if action == .excluded {
                replaceClip(forSourceIndex: idx)
                state.library.removeFromIndex(source: file.source)
            }

            Task {
                let success: Bool
                switch action {
                case .excluded:
                    success = await ApplePhotos.shared.addAssetToExcludedAlbumInHypnographFolder(localIdentifier: identifier)
                case .favorited:
                    success = await ApplePhotos.shared.addAssetToFavoritesAlbumInHypnographFolder(localIdentifier: identifier)
                }

                AppNotifications.show(success ? action.notification : action.failureNotification, flash: true, duration: 1.25)
            }
        }
    }

}

// Keep indices positive when wrapping.
private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    guard modulus > 0 else { return 0 }
    let r = value % modulus
    return r >= 0 ? r : r + modulus
}
