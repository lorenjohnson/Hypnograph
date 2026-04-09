//
//  PlayerView.swift
//  Hypnograph
//
//  Studio player view using the Metal playback pipeline.
//  Uses PlayerContentView for A/B player transitions with shader effects.
//

import SwiftUI
import AVFoundation
import CoreMedia
import QuartzCore
import HypnoCore

/// Studio player view for layered playback.
/// Uses PlayerContentView for GPU-accelerated frame display with shader transitions.
struct PlayerView: NSViewRepresentable {
    let playbackEndBehavior: Studio.PlaybackEndBehavior
    let isLastCompositionInSequence: Bool
    let composition: Composition
    let aspectRatio: AspectRatio
    let displayResolution: OutputResolution
    let sourceFraming: SourceFraming
    let onCompositionEnded: (() -> Bool)?
    @Binding var currentLayerIndex: Int
    @Binding var currentSourceTime: CMTime?
    @Binding var isPrimaryCompositionLoadInFlight: Bool
    @Binding var hasPendingGeneratedNextComposition: Bool
    @Binding var currentCompositionLoadFailure: PlayerState.CompositionLoadFailure?
    let isPaused: Bool
    let effectsChangeCounter: Int
    let hypnogramRevision: Int
    let effectManager: EffectManager
    /// Volume level (0.0 to 1.0) - use 0 for muted
    let volume: Float
    /// Audio output device UID (nil = system default)
    var audioDeviceUID: String? = nil
    /// Transition style for composition changes
    var transitionStyle: TransitionRenderer.TransitionType = .crossfade
    /// Transition duration in seconds
    var transitionDuration: Double = 1.5
    /// Called when the incoming composition has actually presented a frame.
    var onCompositionFramePresented: ((UUID?) -> Void)? = nil
    /// Called when playback reaches the end and should be reflected as paused in UI state.
    var onPlaybackStoppedAtEnd: (() -> Void)? = nil

    // MARK: - Coordinator
    //
    // Auto-advance state machine:
    // ─────────────────────────
    // The coordinator manages automatic composition advancement where compositions
    // play through once and then advance to the next composition. The key challenge is
    // coordinating the timing so transitions start before the current composition ends,
    // while avoiding runaway advancement if the next composition isn't ready yet.
    //
    // State flags:
    // - `didRequestPreEndAdvance`: Set when we've requested the next composition via
    //   `onCompositionEnded()`. Prevents duplicate requests during the same composition.
    // - `isAutoAdvanceInFlight`: Set when a composition change is in progress (building
    //   composition + transitioning). If the current composition ends again while this
    //   is true, we loop the current composition instead of requesting another advance.
    //
    // Flow:
    // 1. Time observer fires when remaining time <= transitionDuration + 0.25s
    // 2. If not already advancing, set both flags and call `onCompositionEnded()`
    // 3. Parent builds new composition and calls `loadAndTransition()`
    // 4. Transition completes → `isAutoAdvanceInFlight` cleared
    // 5. New composition plays → `didRequestPreEndAdvance` reset when compositionID changes
    //
    // Edge cases:
    // - If composition is very short, end notification may fire before transition completes
    //   → we loop the outgoing composition to maintain smooth visuals
    // - Pausing or disabling auto-advance resets both flags

    @MainActor
    class Coordinator {
        var contentView: PlayerContentView?
        var stillClipTimer: Timer?
        var compositionID: String?
        var bindingUpdateToken: UInt64 = 0
        var currentTask: Task<Void, Never>?
        var lastPauseState: Bool?
        var lastEffectsCounter: Int?
        var lastSessionRevision: Int?
        var playRate: Float = 0.8
        var lastAppliedPlayRate: Float?
        var transitionDuration: Double = 1.5
        var lastVolume: Float?
        var playbackEndBehavior: Studio.PlaybackEndBehavior = .advanceAcrossCompositions(loopAtSequenceEnd: false, generateAtSequenceEnd: true)
        var onCompositionEnded: (() -> Bool)?
        var isAllStillImages: Bool = false
        var lastRenderedComposition: Composition?
        /// Whether this is the first composition load (no transition needed)
        var isFirstLoad: Bool = true
        /// Use a sentinel to distinguish "never set" from "set to nil (system default)"
        private static let notSetSentinel = "___NOT_SET___"
        var lastAudioDeviceUID: String? = notSetSentinel
        /// Observers for player item end notifications
        var playbackEndObservers: [Any] = []
        /// Observers for per-player time updates (used for pre-end advancing)
        var playbackTimeObservers: [Any] = []
        /// Guard so we request auto-advance at most once per active composition.
        /// Reset when compositionID changes (new composition loaded).
        var didRequestPreEndAdvance: Bool = false
        /// Prevent runaway auto-advance while a new composition is being built/transitioned in.
        /// If the current composition ends again before the next composition is ready, we loop the current composition
        /// instead of requesting another advance. Cleared when transition completes.
        var isAutoAdvanceInFlight: Bool = false

        func audioDeviceChanged(to newUID: String?) -> Bool {
            if lastAudioDeviceUID == Self.notSetSentinel { return true }
            return lastAudioDeviceUID != newUID
        }

        func removePlaybackEndObservers() {
            for observer in playbackEndObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            playbackEndObservers.removeAll()
        }

        func removePlaybackTimeObservers() {
            guard let contentView else { return }
            for (idx, observer) in playbackTimeObservers.enumerated() {
                // Observers were registered for each player in `contentView.allPlayers` order.
                // If counts don't match (due to a re-init), just attempt removal on both players.
                if idx < contentView.allPlayers.count {
                    contentView.allPlayers[idx].removeTimeObserver(observer)
                } else {
                    for player in contentView.allPlayers {
                        player.removeTimeObserver(observer)
                    }
                }
            }
            playbackTimeObservers.removeAll()
        }

        func beginBindingUpdateCycle() -> UInt64 {
            bindingUpdateToken &+= 1
            return bindingUpdateToken
        }

    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        return container
    }

    @MainActor
    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator

        // Always update playRate so closures use current value
        c.playRate = composition.playRate
        c.transitionDuration = transitionDuration
        c.playbackEndBehavior = playbackEndBehavior
        c.onCompositionEnded = onCompositionEnded
        c.isAllStillImages = composition.layers.allSatisfy { $0.mediaClip.file.mediaKind == .image }
        if isPaused || !canAdvanceCurrentComposition(playbackEndBehavior, isLastCompositionInSequence: isLastCompositionInSequence) {
            c.isAutoAdvanceInFlight = false
            c.didRequestPreEndAdvance = false
        }

        guard !composition.layers.isEmpty else {
            let bindingUpdateToken = c.beginBindingUpdateCycle()
            // Just pause, don't tear down - sources might be added back immediately
            c.contentView?.activeAVPlayer?.pause()
            c.currentTask?.cancel()
            c.currentTask = nil
            c.compositionID = nil
            onCompositionFramePresented?(nil)
            deferCompositionLoadInFlight(false, coordinator: c, token: bindingUpdateToken)
            hasPendingGeneratedNextComposition = false
            if currentSourceTime != nil {
                deferCurrentSourceTime(nil, coordinator: c, token: bindingUpdateToken)
            }
            c.stillClipTimer?.invalidate()
            c.stillClipTimer = nil
            c.isAutoAdvanceInFlight = false
            c.didRequestPreEndAdvance = false
            c.lastRenderedComposition = nil
            return
        }

        // Use display resolution for in-app playback
        let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: displayResolution.maxDimension)

        let newID = compositionIdentity(for: composition)

        if newID != c.compositionID {
            let previousID = c.compositionID
            let bindingUpdateToken = c.beginBindingUpdateCycle()

            freezeOutgoingEffectsIfNeeded(coordinator: c, previousID: previousID)

            c.currentTask?.cancel()
            c.compositionID = newID
            c.didRequestPreEndAdvance = false
            onCompositionFramePresented?(nil)
            deferCompositionLoadInFlight(true, coordinator: c, token: bindingUpdateToken)
            deferCompositionLoadFailure(nil, coordinator: c, token: bindingUpdateToken)

            c.currentTask = Task { @MainActor in
                let engine = RenderEngine()
                let config = RenderEngine.Config(
                    outputSize: outputSize,
                    frameRate: 30,
                    enableEffects: true,
                    sourceFraming: sourceFraming
                )

                let result = await engine.makePlayerItem(
                    composition: composition,
                    config: config,
                    effectManager: effectManager
                )

                guard !Task.isCancelled else {
                    deferCompositionLoadInFlight(false, coordinator: c, token: bindingUpdateToken)
                    hasPendingGeneratedNextComposition = false
                    if c.compositionID == newID { c.compositionID = nil }
                    return
                }

                guard c.compositionID == newID else { return }

                switch result {
                case .success(let playerItem):
                    deferCompositionLoadFailure(nil, coordinator: c, token: bindingUpdateToken)
                    // Create or reuse content view
                    let content: PlayerContentView
                    if let existing = c.contentView {
                        content = existing
                    } else {
                        content = PlayerContentView(frame: nsView.bounds)
                        content.autoresizingMask = [.width, .height]
                        c.contentView = content
                        c.isFirstLoad = true
                    }

                    // Set content mode based on aspect ratio
                    let contentMode: HypnoCore.RendererView.ContentMode = aspectRatio.isFillWindow ? .aspectFill : .aspectFit
                    content.setContentMode(contentMode)

                    // Add content view to container if needed
                    if content.superview != nsView {
                        content.translatesAutoresizingMaskIntoConstraints = false
                        nsView.addSubview(content)
                        NSLayoutConstraint.activate([
                            content.topAnchor.constraint(equalTo: nsView.topAnchor),
                            content.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
                            content.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                            content.trailingAnchor.constraint(equalTo: nsView.trailingAnchor)
                        ])
                    }

                    // Use high-quality audio time pitch algorithm
                    playerItem.audioTimePitchAlgorithm = .timeDomain

                    // Apply volume and audio device
                    content.setVolume(self.volume)
                    content.setAudioOutputDevice(self.audioDeviceUID)
                    c.lastVolume = self.volume
                    c.lastAudioDeviceUID = self.audioDeviceUID

                    // Determine transition type:
                    // - First load: no transition (instant)
                    // - Subsequent loads: use configured transition
                    let effectiveTransition: TransitionRenderer.TransitionType
                    if c.isFirstLoad || previousID == nil {
                        effectiveTransition = .none
                        c.isFirstLoad = false
                    } else {
                        effectiveTransition = self.transitionStyle
                    }

                    // Determine play rate (nil if paused or all still images)
                    let effectiveRate = effectiveVideoPlaybackRate(for: c)
                    let playRate: Float? = (self.isPaused || c.isAllStillImages) ? nil : effectiveRate

                    // Load with transition - this starts playback on the incoming player
                    content.loadAndTransition(
                        playerItem: playerItem,
                        transitionType: effectiveTransition,
                        duration: self.transitionDuration,
                        playRate: playRate,
                        incomingEffectManager: self.effectManager,
                        onIncomingFramePresented: {
                            self.onCompositionFramePresented?(composition.id)
                        }
                    ) {
                        Task { @MainActor in
                            c.isAutoAdvanceInFlight = false
                        }
                    }
                    deferCompositionLoadInFlight(false, coordinator: c, token: bindingUpdateToken)
                    hasPendingGeneratedNextComposition = false

                    c.lastPauseState = self.isPaused
                    c.lastEffectsCounter = effectsChangeCounter
                    c.lastSessionRevision = hypnogramRevision
                    c.lastAppliedPlayRate = playRate
                    c.lastRenderedComposition = composition

                    // For still images, schedule the timer for auto-advance
                    if c.isAllStillImages && !self.isPaused {
                        self.scheduleStillClipTimer(coordinator: c)
                    }

                    // Setup looping or composition-ended callback
                    self.setupPlaybackEndHandling(content: content, coordinator: c)

                case .failure(let error):
                    deferCompositionLoadInFlight(false, coordinator: c, token: bindingUpdateToken)
                    hasPendingGeneratedNextComposition = false
                    if case .allSourcesFailedToLoad = error {
                        deferCompositionLoadFailure(.init(compositionID: composition.id), coordinator: c, token: bindingUpdateToken)
                    } else {
                        deferCompositionLoadFailure(nil, coordinator: c, token: bindingUpdateToken)
                    }
                    error.log(context: "PlayerView")
                    c.compositionID = nil
                    c.isAutoAdvanceInFlight = false
                    if currentSourceTime != nil {
                        deferCurrentSourceTime(nil, coordinator: c, token: bindingUpdateToken)
                    }
                }
            }
        } else {
            if c.lastPauseState != isPaused {
                if c.isAllStillImages {
                    if isPaused {
                        c.stillClipTimer?.invalidate()
                        c.stillClipTimer = nil
                    } else {
                        scheduleStillClipTimer(coordinator: c)
                    }
                } else if isPaused {
                    c.contentView?.activeAVPlayer?.pause()
                    c.lastAppliedPlayRate = nil
                } else {
                    let effectiveRate = effectiveVideoPlaybackRate(for: c)
                    c.contentView?.activeAVPlayer?.playImmediately(atRate: effectiveRate)
                    c.lastAppliedPlayRate = effectiveRate
                }
                c.lastPauseState = isPaused
            }

            // If play rate changes while playing, apply it immediately without rebuilding the composition.
            if !c.isAllStillImages, !isPaused {
                let effectiveRate = effectiveVideoPlaybackRate(for: c)
                if c.lastAppliedPlayRate != effectiveRate {
                    c.contentView?.activeAVPlayer?.rate = effectiveRate
                    c.lastAppliedPlayRate = effectiveRate
                }
            }

            let didEffectsChange = c.lastEffectsCounter != effectsChangeCounter
            if didEffectsChange {
                c.lastEffectsCounter = effectsChangeCounter
            }

            let didSessionMutate = c.lastSessionRevision != hypnogramRevision
            if didSessionMutate {
                c.lastSessionRevision = hypnogramRevision
            }

            if didEffectsChange || didSessionMutate {
                if let content = c.contentView {
                    self.onCompositionFramePresented?(nil)
                    content.notifyOnNextPresentedFrame {
                        self.onCompositionFramePresented?(composition.id)
                    }
                    if c.isAllStillImages {
                        // Force redraw of still frame at t=0
                        content.refreshActiveFrame(at: .zero)
                    } else if isPaused {
                        // Only force redraw when paused
                        if let currentTime = content.activeAVPlayer?.currentTime() {
                            content.refreshActiveFrame(at: currentTime)
                        }
                    }
                }
            }

            // Keep a current snapshot of the active composition so outgoing transitions
            // freeze the latest edited state instead of stale composition-time state.
            c.lastRenderedComposition = composition
        }

        // Apply volume
        if c.lastVolume != volume {
            c.contentView?.setVolume(volume)
            c.lastVolume = volume
        }

        // Apply audio output device routing
        if c.audioDeviceChanged(to: audioDeviceUID) {
            c.contentView?.setAudioOutputDevice(audioDeviceUID)
            c.lastAudioDeviceUID = audioDeviceUID
        }
    }

    private func deferCompositionLoadInFlight(_ value: Bool, coordinator: Coordinator, token: UInt64) {
        guard isPrimaryCompositionLoadInFlight != value else { return }
        DispatchQueue.main.async {
            guard coordinator.bindingUpdateToken == token else { return }
            self.isPrimaryCompositionLoadInFlight = value
        }
    }

    private func deferCompositionLoadFailure(
        _ value: PlayerState.CompositionLoadFailure?,
        coordinator: Coordinator,
        token: UInt64
    ) {
        guard currentCompositionLoadFailure != value else { return }
        DispatchQueue.main.async {
            guard coordinator.bindingUpdateToken == token else { return }
            self.currentCompositionLoadFailure = value
        }
    }

    private func deferCurrentSourceTime(_ value: CMTime?, coordinator: Coordinator, token: UInt64) {
        let currentSeconds = currentSourceTime?.seconds
        let newSeconds = value?.seconds
        guard currentSeconds != newSeconds || (currentSourceTime == nil) != (value == nil) else { return }
        DispatchQueue.main.async {
            guard coordinator.bindingUpdateToken == token else { return }
            self.currentSourceTime = value
        }
    }

    /// Setup looping or composition-ended notification handling for all players
    @MainActor
    private func setupPlaybackEndHandling(content: PlayerContentView, coordinator c: Coordinator) {
        // Remove any existing observers
        c.removePlaybackEndObservers()
        c.removePlaybackTimeObservers()

        // Register observer for each player's current item
        for player in content.allPlayers {
            guard let playerItem = player.currentItem else { continue }

            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak c, weak player] _ in
                Task { @MainActor [weak c, weak player] in
                    guard let c = c, let player = player else { return }

                    let shouldPlay = (c.lastPauseState != true)
                    let rate = effectiveVideoPlaybackRate(for: c)
                    let seekToStartAndPlayIfNeeded = {
                        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                            guard finished else { return }
                            guard shouldPlay else { return }
                            player.playImmediately(atRate: rate)
                        }
                    }

                    // If a transition is in progress, never loop the outgoing player.
                    // Restarting the outgoing composition mid-transition is visually jarring.
                    if c.contentView?.playerView.activeTransition != nil,
                       player !== c.contentView?.activeAVPlayer {
                        return
                    }

                    switch c.playbackEndBehavior {
                    case .advanceAcrossCompositions:
                        // Auto-advance: only advance when the ACTIVE player ends
                        // (not when the outgoing transition player loops)
                        if player === c.contentView?.activeAVPlayer {
                            guard canAdvanceCurrentComposition(
                                c.playbackEndBehavior,
                                isLastCompositionInSequence: self.isLastCompositionInSequence
                            ) else {
                                player.pause()
                                self.onPlaybackStoppedAtEnd?()
                                c.lastPauseState = true
                                return
                            }
                            if c.isAutoAdvanceInFlight {
                                seekToStartAndPlayIfNeeded()
                                return
                            }
                            triggerAutoAdvance(c)
                        } else {
                            // Outgoing player during transition - just loop it
                            seekToStartAndPlayIfNeeded()
                        }
                    case .loopComposition:
                        // Loop mode: seek to beginning and continue
                        seekToStartAndPlayIfNeeded()
                    case .stopAtEnd:
                        player.pause()
                        self.onPlaybackStoppedAtEnd?()
                        c.lastPauseState = true
                    }
                }
            }
            c.playbackEndObservers.append(observer)
        }

        // In auto-advance mode, request the next composition before the current one ends so the transition
        // can complete before playback reaches the end of the outgoing composition (avoids a pause).
        //
        // We base this on *real time* remaining (video seconds / playRate).
        for player in content.allPlayers {
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak c, weak player] _ in
                Task { @MainActor [weak c, weak player] in
                    guard let c, let player, let contentView = c.contentView else { return }
                    guard canAdvanceCurrentComposition(
                        c.playbackEndBehavior,
                        isLastCompositionInSequence: self.isLastCompositionInSequence
                    ) else { return }
                    guard c.lastPauseState != true else { return }
                    guard !c.didRequestPreEndAdvance else { return }
                    guard !c.isAutoAdvanceInFlight else { return }
                    guard contentView.playerView.activeTransition == nil else { return }
                    guard player === contentView.activeAVPlayer else { return }

                    guard let item = player.currentItem,
                          item.status == .readyToPlay,
                          item.duration.isValid,
                          item.duration.isNumeric else {
                        return
                    }

                    let dur = item.duration.seconds
                    let now = player.currentTime().seconds
                    guard dur.isFinite, now.isFinite, dur > 0 else { return }

                    let remainingVideoSeconds = max(0.0, dur - now)
                    let rate = max(0.0001, Double(effectiveVideoPlaybackRate(for: c)))
                    let remainingRealSeconds = remainingVideoSeconds / rate

                    // Trigger next composition build/transition slightly before the desired transition window.
                    // Add a small lead-in to account for:
                    // - transition start deferral until incoming has a frame
                    // - AVPlayer end-of-item rounding (a few frames early)
                    // - render/build scheduling jitter
                    let threshold = max(0.05, c.transitionDuration + 0.25)
                    if remainingRealSeconds <= threshold {
                        triggerAutoAdvance(c)
                    }
                }
            }
            c.playbackTimeObservers.append(token)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            tearDown(coordinator: coordinator)
        }
    }

    // MARK: - Helpers

    private func compositionIdentity(for composition: Composition) -> String {
        let pairs: [String] = composition.layers.enumerated().map { index, layer in
            let name = layer.mediaClip.file.displayName
            let start = layer.mediaClip.startTime.seconds
            let dur = layer.mediaClip.duration.seconds
            let muted = layer.isMuted ? "1" : "0"
            let transformsStr = layer.transforms.map { t in
                "\(t.a),\(t.b),\(t.c),\(t.d),\(t.tx),\(t.ty)"
            }.joined(separator: ";")
            return "\(name)|\(start)|\(dur)|\(muted)|\(transformsStr)"
        }
        let durationPart = "dur=\(composition.effectiveDuration.seconds)"
        let aspectRatioPart = "aspect=\(aspectRatio.displayString)"
        let resolutionPart = "resolution=\(displayResolution.rawValue)"
        let framingPart = "framing=\(sourceFraming.rawValue)"
        return pairs.joined(separator: ";;")
            + "||" + durationPart
            + "||" + aspectRatioPart
            + "||" + resolutionPart
            + "||" + framingPart
    }

    @MainActor
    private func freezeOutgoingEffectsIfNeeded(coordinator c: Coordinator, previousID: String?) {
        guard previousID != nil,
              let content = c.contentView,
              !c.isFirstLoad,
              let outgoingComposition = c.lastRenderedComposition else { return }

        // Freeze the currently visible composition's effect context before switching composition identity.
        // This prevents outgoing frames from adopting incoming composition effects during transition/build delay.
        let frozenManager = effectManager.makeTransitionSnapshotManager(
            frozenComposition: outgoingComposition,
            preserveTemporalState: true
        )
        content.freezeActiveSlotEffects(using: frozenManager)
    }

    @MainActor
    private func scheduleStillClipTimer(coordinator c: Coordinator) {
        c.stillClipTimer?.invalidate()
        c.stillClipTimer = nil

        guard c.lastPauseState != true else { return }
        guard canAdvanceCurrentComposition(
            c.playbackEndBehavior,
            isLastCompositionInSequence: isLastCompositionInSequence
        ) else { return }

        let seconds = max(0.05, composition.effectiveDuration.seconds)
        c.stillClipTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in
                triggerAutoAdvance(c)
            }
        }
    }

    @MainActor
    private func triggerAutoAdvance(_ coordinator: Coordinator) {
        coordinator.didRequestPreEndAdvance = true
        coordinator.isAutoAdvanceInFlight = true

        let didAdvance = coordinator.onCompositionEnded?() ?? false
        if !didAdvance {
            coordinator.didRequestPreEndAdvance = false
            coordinator.isAutoAdvanceInFlight = false
        }
    }

    private func effectiveVideoPlaybackRate(for coordinator: Coordinator) -> Float {
        coordinator.playRate
    }

    private func isAdvanceAcrossCompositions(_ behavior: Studio.PlaybackEndBehavior) -> Bool {
        if case .advanceAcrossCompositions = behavior {
            return true
        }
        return false
    }

    private func canAdvanceCurrentComposition(
        _ behavior: Studio.PlaybackEndBehavior,
        isLastCompositionInSequence: Bool
    ) -> Bool {
        switch behavior {
        case .loopComposition, .stopAtEnd:
            return false
        case .advanceAcrossCompositions(let loopAtSequenceEnd, let generateAtSequenceEnd):
            if !isLastCompositionInSequence {
                return true
            }
            return loopAtSequenceEnd || generateAtSequenceEnd
        }
    }

    // MARK: - Teardown

    @MainActor
    private static func tearDown(coordinator c: Coordinator) {
        c.stillClipTimer?.invalidate()
        c.stillClipTimer = nil

        c.removePlaybackEndObservers()
        c.removePlaybackTimeObservers()
        c.isAutoAdvanceInFlight = false

        c.contentView?.stop()
        c.contentView = nil
        c.compositionID = nil
        c.lastRenderedComposition = nil
    }
}
