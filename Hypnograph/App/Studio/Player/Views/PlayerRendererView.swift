//
//  PlayerRendererView.swift
//  Hypnograph
//
//  Studio player renderer view using the Metal player pipeline.
//  Uses PlayerContentView for A/B player transitions with shader effects.
//

import SwiftUI
import AVFoundation
import CoreMedia
import QuartzCore
import HypnoCore

/// Studio player renderer view for layered player state.
/// Uses PlayerContentView for GPU-accelerated frame display with shader transitions.
struct PlayerRendererView: NSViewRepresentable {
    @ObservedObject var main: Studio

    // MARK: - Player Coordinator
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

    func makeCoordinator() -> PlayerCoordinator {
        PlayerCoordinator()
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
        let player = main.activePlayer
        let composition = main.currentComposition
        let endBehavior = main.playerEndBehavior
        let aspectRatio = main.currentHypnogramAspectRatio
        let displayResolution = main.currentHypnogramOutputResolution
        let sourceFraming = main.currentHypnogramSourceFraming
        let transitionStyle = main.currentCompositionTransitionStyle
        let transitionDuration = main.currentCompositionTransitionDuration
        let studio = main

        // Always update playRate so closures use current value
        c.playRate = composition.playRate
        c.endBehavior = endBehavior
        c.onCompositionEnded = { [weak studio] in
            studio?.handlePlayerCompositionEnd() ?? false
        }
        c.isAllStillImages = composition.layers.allSatisfy { $0.mediaClip.file.mediaKind == .image }
        c.isTimelineScrubbing = player.isTimelineScrubbing
        if player.isPaused || !canAdvanceCurrentComposition(endBehavior, isLastCompositionInSequence: main.isLastCompositionInSequence) {
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
            deferCompositionLoadInFlight(false, coordinator: c, token: bindingUpdateToken)
            player.hasPendingGeneratedNextComposition = false
            if player.currentLayerTimeOffset != nil {
                deferCurrentSourceTime(nil, coordinator: c, token: bindingUpdateToken)
            }
            c.stillClipTimer?.invalidate()
            c.stillClipTimer = nil
            c.isAutoAdvanceInFlight = false
            c.didRequestPreEndAdvance = false
            c.lastRenderedComposition = nil
            return
        }

        // Use display resolution for the in-app player surface
        let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: displayResolution.maxDimension)

        let newID = compositionIdentity(for: composition)

        if newID != c.compositionID {
            let previousID = c.compositionID
            let bindingUpdateToken = c.beginBindingUpdateCycle()
            let outgoingRenderedComposition = c.lastRenderedComposition

            freezeOutgoingEffectsIfNeeded(coordinator: c, previousID: previousID)

            c.currentTask?.cancel()
            c.compositionID = newID
            c.didRequestPreEndAdvance = false
            c.suppressCurrentTimeReporting = true
            deferCompositionLoadInFlight(true, coordinator: c, token: bindingUpdateToken)
            deferCompositionLoadFailure(nil, coordinator: c, token: bindingUpdateToken)

            c.currentTask = Task { @MainActor in
                let engine = RenderEngine()
                let config = RenderEngine.Config(
                    outputSize: outputSize,
                    frameRate: 30,
                    enableEffects: true,
                    sourceFraming: sourceFraming,
                    useSourceFrameRate: true
                )

                let result = await engine.makePlayerItem(
                    composition: composition,
                    config: config,
                    effectManager: player.effectManager
                )

                guard !Task.isCancelled else {
                    deferCompositionLoadInFlight(false, coordinator: c, token: bindingUpdateToken)
                    player.hasPendingGeneratedNextComposition = false
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
                    content.setVolume(main.volume)
                    content.setAudioOutputDevice(main.audioDeviceUID)
                    c.lastVolume = main.volume
                    c.lastAudioDeviceUID = main.audioDeviceUID

                    // Determine transition type:
                    // - First load: no transition (instant)
                    // - Subsequent loads: use configured transition
                    let effectiveTransition: TransitionRenderer.TransitionType
                    let effectiveTransitionDuration: Double
                    let hasExistingRenderedComposition = c.contentView != nil && outgoingRenderedComposition != nil
                    let isSameCompositionReload = outgoingRenderedComposition?.id == composition.id
                    c.pendingPostLoadSourceTime = isSameCompositionReload ? player.currentLayerTimeOffset : nil
                    if c.isFirstLoad || !hasExistingRenderedComposition {
                        effectiveTransition = .none
                        effectiveTransitionDuration = transitionDuration
                        c.isFirstLoad = false
                    } else if isSameCompositionReload {
                        effectiveTransition = .none
                        effectiveTransitionDuration = transitionDuration
                    } else {
                        effectiveTransition = player.pendingCompositionTransitionStyle ?? transitionStyle
                        effectiveTransitionDuration = player.pendingCompositionTransitionDuration ?? transitionDuration
                    }
                    c.transitionDuration = effectiveTransitionDuration
                    player.pendingCompositionTransitionStyle = nil
                    player.pendingCompositionTransitionDuration = nil

                    // Determine play rate (nil if paused or all still images)
                    let effectiveRate = effectiveVideoRate(for: c)
                    let playRate: Float? = (player.isPaused || c.isAllStillImages) ? nil : effectiveRate

                    // Load with transition - this starts the incoming player when a rate is provided.
                    content.loadAndTransition(
                        playerItem: playerItem,
                        transitionType: effectiveTransition,
                        duration: effectiveTransitionDuration,
                        playRate: playRate,
                        incomingEffectManager: player.effectManager
                    ) {
                        Task { @MainActor in
                            if let pendingPostLoadSourceTime = c.pendingPostLoadSourceTime {
                                content.scrubActiveFrame(at: pendingPostLoadSourceTime)
                                c.pendingPostLoadSourceTime = nil
                            }
                            c.suppressCurrentTimeReporting = false
                            c.isAutoAdvanceInFlight = false
                        }
                    }
                    deferCompositionLoadInFlight(false, coordinator: c, token: bindingUpdateToken)
                    player.hasPendingGeneratedNextComposition = false

                    c.lastPauseState = player.isPaused
                    c.lastEffectsCounter = player.effectsChangeCounter
                    c.lastSessionRevision = main.hypnogramRevision
                    c.lastAppliedPlayRate = playRate
                    c.lastRenderedComposition = composition

                    // For still images, schedule the timer for auto-advance
                    if c.isAllStillImages && !player.isPaused {
                        self.scheduleStillClipTimer(coordinator: c)
                    }

                    // Setup looping or composition-ended callback
                    self.setupEndHandling(content: content, coordinator: c)

                case .failure(let error):
                    deferCompositionLoadInFlight(false, coordinator: c, token: bindingUpdateToken)
                    player.hasPendingGeneratedNextComposition = false
                    if case .allSourcesFailedToLoad = error {
                        deferCompositionLoadFailure(.init(compositionID: composition.id), coordinator: c, token: bindingUpdateToken)
                    } else {
                        deferCompositionLoadFailure(nil, coordinator: c, token: bindingUpdateToken)
                    }
                    c.suppressCurrentTimeReporting = false
                    error.log(context: "PlayerRendererView")
                    c.compositionID = nil
                    c.isAutoAdvanceInFlight = false
                    if player.currentLayerTimeOffset != nil {
                        deferCurrentSourceTime(nil, coordinator: c, token: bindingUpdateToken)
                    }
                }
            }
        } else {
            if c.lastPauseState != player.isPaused {
                if c.isAllStillImages {
                    if player.isPaused {
                        c.stillClipTimer?.invalidate()
                        c.stillClipTimer = nil
                    } else {
                        scheduleStillClipTimer(coordinator: c)
                    }
                } else if player.isPaused {
                    c.contentView?.activeAVPlayer?.pause()
                    c.lastAppliedPlayRate = nil
                } else {
                    let effectiveRate = effectiveVideoRate(for: c)
                    c.contentView?.activeAVPlayer?.playImmediately(atRate: effectiveRate)
                    c.lastAppliedPlayRate = effectiveRate
                }
                c.lastPauseState = player.isPaused
            }

            // If play rate changes while playing, apply it immediately without rebuilding the composition.
            if !c.isAllStillImages, !player.isPaused {
                let effectiveRate = effectiveVideoRate(for: c)
                if c.lastAppliedPlayRate != effectiveRate {
                    c.contentView?.activeAVPlayer?.rate = effectiveRate
                    c.lastAppliedPlayRate = effectiveRate
                }
            }

            let didEffectsChange = c.lastEffectsCounter != player.effectsChangeCounter
            if didEffectsChange {
                c.lastEffectsCounter = player.effectsChangeCounter
            }

            let didSessionMutate = c.lastSessionRevision != main.hypnogramRevision
            if didSessionMutate {
                c.lastSessionRevision = main.hypnogramRevision
            }

            if didEffectsChange || didSessionMutate {
                if let content = c.contentView {
                    if c.isAllStillImages {
                        // Force redraw of still frame at t=0
                        content.refreshActiveFrame(at: .zero)
                    } else if player.isPaused {
                        // Only force redraw when paused
                        if let currentTime = content.activeAVPlayer?.currentTime() {
                            content.refreshActiveFrame(at: currentTime)
                        }
                    }
                }
            }

            if let requestedSourceTime = player.requestedLayerTimeOffset,
               let content = c.contentView {
                let activeTime = content.activeAVPlayer?.currentTime() ?? .invalid
                let activeSeconds = activeTime.seconds
                let requestedSeconds = requestedSourceTime.seconds
                let needsSeek =
                    !activeTime.isValid ||
                    !activeSeconds.isFinite ||
                    abs(activeSeconds - requestedSeconds) > 0.02

                if needsSeek {
                    if player.isTimelineScrubbing {
                        content.scrubActiveFrame(at: requestedSourceTime)
                    } else {
                        content.refreshActiveFrame(at: requestedSourceTime)
                    }
                }

                DispatchQueue.main.async {
                    player.requestedLayerTimeOffset = nil
                }
            }

            // Keep a current snapshot of the active composition so outgoing transitions
            // freeze the latest edited state instead of stale composition-time state.
            c.lastRenderedComposition = composition
        }

        // Apply volume
        if c.lastVolume != main.volume {
            c.contentView?.setVolume(main.volume)
            c.lastVolume = main.volume
        }

        // Apply audio output device routing
        if c.audioDeviceChanged(to: main.audioDeviceUID) {
            c.contentView?.setAudioOutputDevice(main.audioDeviceUID)
            c.lastAudioDeviceUID = main.audioDeviceUID
        }
    }

    private func deferCompositionLoadInFlight(_ value: Bool, coordinator: PlayerCoordinator, token: UInt64) {
        guard main.activePlayer.isPrimaryCompositionLoadInFlight != value else { return }
        DispatchQueue.main.async {
            guard coordinator.bindingUpdateToken == token else { return }
            self.main.activePlayer.isPrimaryCompositionLoadInFlight = value
        }
    }

    private func deferCompositionLoadFailure(
        _ value: PlayerState.CompositionLoadFailure?,
        coordinator: PlayerCoordinator,
        token: UInt64
    ) {
        guard main.activePlayer.currentCompositionLoadFailure != value else { return }
        DispatchQueue.main.async {
            guard coordinator.bindingUpdateToken == token else { return }
            self.main.activePlayer.currentCompositionLoadFailure = value
        }
    }

    private func deferCurrentSourceTime(_ value: CMTime?, coordinator: PlayerCoordinator, token: UInt64) {
        let currentSeconds = main.activePlayer.currentLayerTimeOffset?.seconds
        let newSeconds = value?.seconds
        let currentTime = main.activePlayer.currentLayerTimeOffset
        guard currentSeconds != newSeconds || (currentTime == nil) != (value == nil) else { return }
        guard coordinator.bindingUpdateToken == token else { return }
        self.main.activePlayer.currentLayerTimeOffset = value
    }

    /// Setup looping or composition-ended notification handling for all players.
    @MainActor
    private func setupEndHandling(content: PlayerContentView, coordinator c: PlayerCoordinator) {
        // Remove any existing observers
        c.removeEndObservers()
        c.removeTimeObservers()

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
                    let rate = effectiveVideoRate(for: c)
                    let seekToStartAndPlayIfNeeded = {
                        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                            guard finished else { return }
                            guard shouldPlay else { return }
                            player.playImmediately(atRate: rate)
                        }
                    }
                    let seekToStartAndStop = {
                        let bindingUpdateToken = c.bindingUpdateToken
                        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                            guard finished else { return }
                            player.pause()
                            deferCurrentSourceTime(.zero, coordinator: c, token: bindingUpdateToken)
                            self.main.activePlayer.isPaused = true
                            c.lastPauseState = true
                        }
                    }

                    // If a transition is in progress, never loop the outgoing player.
                    // Restarting the outgoing composition mid-transition is visually jarring.
                    if c.contentView?.playerView.activeTransition != nil,
                       player !== c.contentView?.activeAVPlayer {
                        return
                    }

                    switch c.endBehavior {
                    case .advanceAcrossCompositions:
                        // Auto-advance: only advance when the ACTIVE player ends
                        // (not when the outgoing transition player loops)
                        if player === c.contentView?.activeAVPlayer {
                            guard canAdvanceCurrentComposition(
                                c.endBehavior,
                                isLastCompositionInSequence: self.main.isLastCompositionInSequence
                            ) else {
                                seekToStartAndStop()
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
                        seekToStartAndStop()
                    }
                }
            }
            c.endObservers.append(observer)
        }

        // In auto-advance mode, request the next composition before the current one ends so the transition
        // can complete before the outgoing composition finishes (avoids a pause).
        //
        // We base this on *real time* remaining (video seconds / playRate).
        for player in content.allPlayers {
            let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
            let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak c, weak player] _ in
                Task { @MainActor [weak c, weak player] in
                    guard let c, let player, let contentView = c.contentView else { return }
                    guard player === contentView.activeAVPlayer else { return }

                    let bindingUpdateToken = c.bindingUpdateToken
                    if !c.isTimelineScrubbing && !c.suppressCurrentTimeReporting {
                        deferCurrentSourceTime(player.currentTime(), coordinator: c, token: bindingUpdateToken)
                    }

                    guard canAdvanceCurrentComposition(
                        c.endBehavior,
                        isLastCompositionInSequence: self.main.isLastCompositionInSequence
                    ) else { return }
                    guard c.lastPauseState != true else { return }
                    guard !c.didRequestPreEndAdvance else { return }
                    guard !c.isAutoAdvanceInFlight else { return }
                    guard contentView.playerView.activeTransition == nil else { return }

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
                    let rate = max(0.0001, Double(effectiveVideoRate(for: c)))
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
            c.timeObservers.append(token)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: PlayerCoordinator) {
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
        let aspectRatioPart = "aspect=\(main.currentHypnogramAspectRatio.displayString)"
        let resolutionPart = "resolution=\(main.currentHypnogramOutputResolution.rawValue)"
        let framingPart = "framing=\(main.currentHypnogramSourceFraming.rawValue)"
        return pairs.joined(separator: ";;")
            + "||" + durationPart
            + "||" + aspectRatioPart
            + "||" + resolutionPart
            + "||" + framingPart
    }

    @MainActor
    private func freezeOutgoingEffectsIfNeeded(coordinator c: PlayerCoordinator, previousID: String?) {
        guard previousID != nil,
              let content = c.contentView,
              !c.isFirstLoad,
              let outgoingComposition = c.lastRenderedComposition else { return }

        // Freeze the currently visible composition's effect context before switching composition identity.
        // This prevents outgoing frames from adopting incoming composition effects during transition/build delay.
        let frozenManager = main.activePlayer.effectManager.makeTransitionSnapshotManager(
            frozenComposition: outgoingComposition,
            preserveTemporalState: true
        )
        content.freezeActiveSlotEffects(using: frozenManager)
    }

    @MainActor
    private func scheduleStillClipTimer(coordinator c: PlayerCoordinator) {
        c.stillClipTimer?.invalidate()
        c.stillClipTimer = nil

        guard c.lastPauseState != true else { return }
        guard canAdvanceCurrentComposition(
            c.endBehavior,
            isLastCompositionInSequence: main.isLastCompositionInSequence
        ) else { return }

        let seconds = max(0.05, main.currentComposition.effectiveDuration.seconds)
        c.stillClipTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in
                triggerAutoAdvance(c)
            }
        }
    }

    @MainActor
    private func triggerAutoAdvance(_ coordinator: PlayerCoordinator) {
        coordinator.didRequestPreEndAdvance = true
        coordinator.isAutoAdvanceInFlight = true

        let didAdvance = coordinator.onCompositionEnded?() ?? false
        if !didAdvance {
            coordinator.didRequestPreEndAdvance = false
            coordinator.isAutoAdvanceInFlight = false
        }
    }

    private func effectiveVideoRate(for coordinator: PlayerCoordinator) -> Float {
        coordinator.playRate
    }

    private func canAdvanceCurrentComposition(
        _ behavior: Studio.PlayerEndBehavior,
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
    private static func tearDown(coordinator c: PlayerCoordinator) {
        c.stillClipTimer?.invalidate()
        c.stillClipTimer = nil

        c.removeEndObservers()
        c.removeTimeObservers()
        c.isAutoAdvanceInFlight = false

        c.contentView?.stop()
        c.contentView = nil
        c.compositionID = nil
        c.lastRenderedComposition = nil
    }
}
