//
//  PreviewPlayerView.swift
//  Hypnograph
//
//  Preview player using the Metal playback pipeline.
//  Uses PlayerContentView for A/B player transitions with shader effects.
//

import SwiftUI
import AVFoundation
import CoreMedia
import QuartzCore
import HypnoCore

/// Preview player view for Dream module layered playback.
/// Uses PlayerContentView for GPU-accelerated frame display with shader transitions.
struct PreviewPlayerView: NSViewRepresentable {
    let clip: HypnogramClip
    let aspectRatio: AspectRatio
    let displayResolution: OutputResolution
    let sourceFraming: SourceFraming
    let watchMode: Bool
    let onClipEnded: (() -> Void)?
    @Binding var currentSourceIndex: Int
    @Binding var currentSourceTime: CMTime?
    let isPaused: Bool
    let effectsChangeCounter: Int
    let effectManager: EffectManager
    /// Volume level (0.0 to 1.0) - use 0 for muted
    let volume: Float
    /// Audio output device UID (nil = system default)
    var audioDeviceUID: String? = nil
    /// Transition style for clip changes
    var transitionStyle: TransitionRenderer.TransitionType = .crossfade
    /// Transition duration in seconds
    var transitionDuration: Double = 1.5

    // MARK: - Coordinator
    //
    // Watch-mode state machine:
    // ─────────────────────────
    // The coordinator manages automatic clip advancement in "watch mode" where clips
    // play through once and then advance to the next clip. The key challenge is
    // coordinating the timing so transitions start before the current clip ends,
    // while avoiding runaway advancement if the next clip isn't ready yet.
    //
    // State flags:
    // - `didRequestPreEndAdvance`: Set when we've requested the next clip via
    //   `onClipEnded()`. Prevents duplicate requests during the same clip.
    // - `isWatchAdvanceInFlight`: Set when a clip change is in progress (building
    //   composition + transitioning). If the current clip ends again while this
    //   is true, we loop the current clip instead of requesting another advance.
    //
    // Flow:
    // 1. Time observer fires when remaining time <= transitionDuration + 0.25s
    // 2. If not already advancing, set both flags and call `onClipEnded()`
    // 3. Parent builds new composition and calls `loadAndTransition()`
    // 4. Transition completes → `isWatchAdvanceInFlight` cleared
    // 5. New clip plays → `didRequestPreEndAdvance` reset when compositionID changes
    //
    // Edge cases:
    // - If clip is very short, end notification may fire before transition completes
    //   → we loop the outgoing clip to maintain smooth visuals
    // - Pausing or disabling watch mode resets both flags

    @MainActor
    class Coordinator {
        var contentView: PlayerContentView?
        var containerView: NSView?
        var stillClipTimer: Timer?
        var compositionID: String?
        var currentTask: Task<Void, Never>?
        var lastPauseState: Bool?
        var lastEffectsCounter: Int?
        var currentPlayerItem: AVPlayerItem?
        var playRate: Float = 0.8
        var lastAppliedPlayRate: Float?
        var transitionDuration: Double = 1.5
        var lastVolume: Float?
        var watchMode: Bool = false
        var onClipEnded: (() -> Void)?
        var isAllStillImages: Bool = false
        /// Whether this is the first clip load (no transition needed)
        var isFirstLoad: Bool = true
        /// Used to ignore stale background Vision framing results.
        var contentFocusRequestID: UUID = UUID()
        var pendingContentFocus: PlayerView.ContentFocus?
        var smartFramingTimer: DispatchSourceTimer?
        var smartFramingRequestID: UUID?
        var smartFramingInFlight: Bool = false
        var lastFocusAnchor: CGPoint?
        var consecutiveMisses: Int = 0
        /// Use a sentinel to distinguish "never set" from "set to nil (system default)"
        private static let notSetSentinel = "___NOT_SET___"
        var lastAudioDeviceUID: String? = notSetSentinel
        /// Observers for player item end notifications
        var playbackEndObservers: [Any] = []
        /// Observers for per-player time updates (used for pre-end advancing)
        var playbackTimeObservers: [Any] = []
        /// Guard so we request a watch-mode advance at most once per active clip.
        /// Reset when compositionID changes (new clip loaded).
        var didRequestPreEndAdvance: Bool = false
        /// Prevent runaway watch-mode advancement while a new clip is being built/transitioned in.
        /// If the current clip ends again before the next clip is ready, we loop the current clip
        /// instead of requesting another advance. Cleared when transition completes.
        var isWatchAdvanceInFlight: Bool = false

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

        func stopSmartFramingTimer() {
            smartFramingTimer?.setEventHandler {}
            smartFramingTimer?.cancel()
            smartFramingTimer = nil
            smartFramingRequestID = nil
            smartFramingInFlight = false
            lastFocusAnchor = nil
            consecutiveMisses = 0
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        context.coordinator.containerView = container
        return container
    }

    @MainActor
    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator

        // Always update playRate so closures use current value
        c.playRate = clip.playRate
        c.transitionDuration = transitionDuration
        c.watchMode = watchMode
        c.onClipEnded = onClipEnded
        c.isAllStillImages = clip.sources.allSatisfy { $0.clip.file.mediaKind == .image }
        if !watchMode || isPaused {
            c.isWatchAdvanceInFlight = false
            c.didRequestPreEndAdvance = false
        }

        guard !clip.sources.isEmpty else {
            // Just pause, don't tear down - sources might be added back immediately
            c.contentView?.activeAVPlayer?.pause()
            c.currentTask?.cancel()
            c.currentTask = nil
            c.compositionID = nil
            if currentSourceTime != nil {
                currentSourceTime = nil
            }
            c.stillClipTimer?.invalidate()
            c.stillClipTimer = nil
            c.isWatchAdvanceInFlight = false
            c.didRequestPreEndAdvance = false
            return
        }

        // Use display resolution for preview
        let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: displayResolution.maxDimension)

        let newID = compositionIdentity(for: clip)

        if newID != c.compositionID {
            let previousID = c.compositionID
            c.currentTask?.cancel()
            c.compositionID = newID
            c.didRequestPreEndAdvance = false

            // Clear old player item references
            c.currentPlayerItem = nil

            c.currentTask = Task { @MainActor in
                let engine = RenderEngine()
                let config = RenderEngine.Config(
                    outputSize: outputSize,
                    frameRate: 30,
                    enableEffects: true,
                    sourceFraming: sourceFraming
                )

                let result = await engine.makePlayerItem(
                    clip: clip,
                    config: config,
                    effectManager: effectManager
                )

                guard !Task.isCancelled else {
                    if c.compositionID == newID { c.compositionID = nil }
                    return
                }

                guard c.compositionID == newID else { return }

                switch result {
                case .success(let playerItem):
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
                    let contentMode: PlayerView.ContentMode = aspectRatio.isFillWindow ? .aspectFill : .aspectFit
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
                    let playRate: Float? = (self.isPaused || c.isAllStillImages) ? nil : c.playRate

                    // Load with transition - this starts playback on the incoming player
                    content.loadAndTransition(
                        playerItem: playerItem,
                        transitionType: effectiveTransition,
                        duration: self.transitionDuration,
                        playRate: playRate
                    ) {
                        Task { @MainActor in
                            c.isWatchAdvanceInFlight = false
                            if let pending = c.pendingContentFocus {
                                c.pendingContentFocus = nil
                                c.contentView?.setContentFocus(pending)
                            }
                        }
                    }

                    // Content-aware framing (Vision): detect a person and bias framing so the head
                    // sits near the top of the window when using aspect-fill display.
                    if contentMode == .aspectFill {
                        content.setContentFocus(nil)
                        c.pendingContentFocus = nil
                        c.contentFocusRequestID = UUID()
                        c.stopSmartFramingTimer()
                        let requestID = c.contentFocusRequestID
                        let asset = playerItem.asset
                        let videoComposition = playerItem.videoComposition
                        DispatchQueue.global(qos: .utility).async { [weak c, weak content] in
                            let analysis = HumanRectanglesFraming.analyze(
                                asset: asset,
                                videoComposition: videoComposition
                            )
                            DispatchQueue.main.async {
                                guard let c, c.contentFocusRequestID == requestID else { return }
                                guard let content else { return }
                                if content.playerView.activeTransition == nil {
                                    c.pendingContentFocus = nil
                                    content.setContentFocus(analysis.contentFocus)
                                } else {
                                    c.pendingContentFocus = analysis.contentFocus
                                }
                            }
                        }
                    } else {
                        content.setContentFocus(nil)
                        c.pendingContentFocus = nil
                        c.stopSmartFramingTimer()
                    }

                    self.updateSmartFramingTimer(
                        coordinator: c,
                        content: content,
                        enabled: (contentMode == .aspectFill && !self.isPaused && !c.isAllStillImages)
                    )

                    c.currentPlayerItem = playerItem
                    c.lastPauseState = self.isPaused
                    c.lastEffectsCounter = effectsChangeCounter
                    c.lastAppliedPlayRate = playRate

                    // For still images, schedule the timer for watch mode advancement
                    if c.isAllStillImages && !self.isPaused {
                        self.scheduleStillClipTimer(coordinator: c)
                    }

                    // Setup looping or clip-ended callback
                    self.setupPlaybackEndHandling(content: content, coordinator: c)

                case .failure(let error):
                    error.log(context: "PreviewPlayerView")
                    c.compositionID = nil
                    c.isWatchAdvanceInFlight = false
                    if currentSourceTime != nil {
                        currentSourceTime = nil
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
                    c.contentView?.activeAVPlayer?.playImmediately(atRate: clip.playRate)
                    c.lastAppliedPlayRate = clip.playRate
                }
                c.lastPauseState = isPaused
            }

            // If play rate changes while playing, apply it immediately without rebuilding the composition.
            if !c.isAllStillImages, !isPaused, c.lastAppliedPlayRate != clip.playRate {
                c.contentView?.activeAVPlayer?.rate = clip.playRate
                c.lastAppliedPlayRate = clip.playRate
            }

            if let content = c.contentView {
                let contentMode: PlayerView.ContentMode = aspectRatio.isFillWindow ? .aspectFill : .aspectFit
                updateSmartFramingTimer(
                    coordinator: c,
                    content: content,
                    enabled: (contentMode == .aspectFill && !isPaused && !c.isAllStillImages)
                )
            }

            if c.lastEffectsCounter != effectsChangeCounter {
                c.lastEffectsCounter = effectsChangeCounter
                if let content = c.contentView {
                    if c.isAllStillImages {
                        // Force redraw of still frame at t=0
                        content.activeAVPlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    } else if isPaused {
                        // Only force redraw when paused
                        if let currentTime = content.activeAVPlayer?.currentTime() {
                            content.activeAVPlayer?.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                    }
                }
            }
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

    /// Setup looping or clip-ended notification handling for all players
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
                    let rate = c.playRate
                    let seekToStartAndPlayIfNeeded = {
                        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                            guard finished else { return }
                            guard shouldPlay else { return }
                            player.playImmediately(atRate: rate)
                        }
                    }

                    // If a transition is in progress, never loop the outgoing player.
                    // Restarting the outgoing clip mid-transition is visually jarring.
                    if c.contentView?.playerView.activeTransition != nil,
                       player !== c.contentView?.activeAVPlayer {
                        return
                    }

                    if c.watchMode {
                        // Watch mode: only advance when the ACTIVE player ends
                        // (not when the outgoing transition player loops)
                        if player === c.contentView?.activeAVPlayer {
                            if c.isWatchAdvanceInFlight {
                                seekToStartAndPlayIfNeeded()
                                return
                            }
                            c.isWatchAdvanceInFlight = true
                            c.didRequestPreEndAdvance = true
                            c.onClipEnded?()
                        } else {
                            // Outgoing player during transition - just loop it
                            seekToStartAndPlayIfNeeded()
                        }
                    } else {
                        // Loop mode: seek to beginning and continue
                        seekToStartAndPlayIfNeeded()
                    }
                }
            }
            c.playbackEndObservers.append(observer)
        }

        // In watch mode, request the next clip before the current one ends so the transition
        // can complete before playback reaches the end of the outgoing clip (avoids a pause).
        //
        // We base this on *real time* remaining (video seconds / playRate).
        for player in content.allPlayers {
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak c, weak player] _ in
                Task { @MainActor [weak c, weak player] in
                    guard let c, let player, let contentView = c.contentView else { return }
                    guard c.watchMode else { return }
                    guard c.lastPauseState != true else { return }
                    guard !c.didRequestPreEndAdvance else { return }
                    guard !c.isWatchAdvanceInFlight else { return }
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
                    let rate = max(0.0001, Double(c.playRate))
                    let remainingRealSeconds = remainingVideoSeconds / rate

                    // Trigger next clip build/transition slightly before the desired transition window.
                    // Add a small lead-in to account for:
                    // - transition start deferral until incoming has a frame
                    // - AVPlayer end-of-item rounding (a few frames early)
                    // - render/build scheduling jitter
                    let threshold = max(0.05, c.transitionDuration + 0.25)
                    if remainingRealSeconds <= threshold {
                        c.didRequestPreEndAdvance = true
                        c.isWatchAdvanceInFlight = true
                        c.onClipEnded?()
                    }
                }
            }
            c.playbackTimeObservers.append(token)
        }
    }

    @MainActor
    private func updateSmartFramingTimer(
        coordinator c: Coordinator,
        content: PlayerContentView,
        enabled: Bool
    ) {
        guard enabled else {
            c.stopSmartFramingTimer()
            content.setContentFocus(nil)
            return
        }

        if c.smartFramingTimer != nil, c.smartFramingRequestID == c.contentFocusRequestID {
            return
        }

        if c.smartFramingTimer != nil, c.smartFramingRequestID != c.contentFocusRequestID {
            c.stopSmartFramingTimer()
        }

        let requestID = c.contentFocusRequestID
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval: TimeInterval = 0.25
        timer.schedule(deadline: .now() + interval, repeating: interval)

        timer.setEventHandler { [weak c, weak content] in
            guard let c, let content else { return }
            guard c.contentFocusRequestID == requestID else { return }
            guard !c.smartFramingInFlight else { return }
            c.smartFramingInFlight = true

            // Capture current frame from the active AVPlayer-backed frame source.
            guard let frame = content.activeFrameSource?.bestFrame(forHostTime: CACurrentMediaTime()) else {
                c.smartFramingInFlight = false
                return
            }

            let pixelBuffer = frame.pixelBuffer

            DispatchQueue.global(qos: .utility).async {
                let analysis = HumanRectanglesFraming.analyze(pixelBuffer: pixelBuffer, config: .init())

                DispatchQueue.main.async { [weak c, weak content] in
                    guard let c, let content else { return }
                    defer { c.smartFramingInFlight = false }
                    guard c.contentFocusRequestID == requestID else { return }

                    // Never update framing mid-transition; defer until completion.
                    let isTransitioning = (content.playerView.activeTransition != nil)

                    if let focus = analysis.contentFocus {
                        c.consecutiveMisses = 0

                        // Smooth anchor to reduce jitter.
                        let newAnchor = focus.anchorNormalized
                        // Portrait->landscape expectation: bias should be primarily vertical; keep X centered.
                        let newAnchorVerticalOnly = CGPoint(x: 0.5, y: newAnchor.y)
                        let smoothed: CGPoint
                        if let last = c.lastFocusAnchor {
                            let alpha: CGFloat = 0.25
                            smoothed = CGPoint(
                                x: last.x * (1 - alpha) + newAnchorVerticalOnly.x * alpha,
                                y: last.y * (1 - alpha) + newAnchorVerticalOnly.y * alpha
                            )
                        } else {
                            smoothed = newAnchorVerticalOnly
                        }
                        c.lastFocusAnchor = smoothed

                        let smoothedFocus = PlayerView.ContentFocus(
                            anchorNormalized: smoothed,
                            targetNDC: focus.targetNDC,
                            boundsNormalized: focus.boundsNormalized,
                            paddingNDC: focus.paddingNDC,
                            overscrollMode: focus.overscrollMode
                        )

                        if isTransitioning {
                            c.pendingContentFocus = smoothedFocus
                        } else {
                            c.pendingContentFocus = nil
                            content.setContentFocus(smoothedFocus)
                        }
                    } else {
                        c.consecutiveMisses += 1
                        // If we miss several times in a row, release back to centered framing.
                        if c.consecutiveMisses >= 3 {
                            c.lastFocusAnchor = nil
                            if isTransitioning {
                                c.pendingContentFocus = nil
                            } else {
                                content.setContentFocus(nil)
                            }
                        }
                    }
                }
            }
        }

        c.smartFramingTimer = timer
        c.smartFramingRequestID = requestID
        timer.resume()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            tearDown(coordinator: coordinator)
        }
    }

    // MARK: - Helpers

    private func compositionIdentity(for clip: HypnogramClip) -> String {
        let pairs: [String] = clip.sources.enumerated().map { index, source in
            let name = source.clip.file.displayName
            let start = source.clip.startTime.seconds
            let dur = source.clip.duration.seconds
            let transformsStr = source.transforms.map { t in
                "\(t.a),\(t.b),\(t.c),\(t.d),\(t.tx),\(t.ty)"
            }.joined(separator: ";")
            return "\(name)|\(start)|\(dur)|\(transformsStr)"
        }
        let durationPart = "dur=\(clip.targetDuration.seconds)"
        let framingPart = "framing=\(sourceFraming.rawValue)"
        return pairs.joined(separator: ";;") + "||" + durationPart + "||" + framingPart
    }

    @MainActor
    private func scheduleStillClipTimer(coordinator c: Coordinator) {
        c.stillClipTimer?.invalidate()
        c.stillClipTimer = nil

        guard c.watchMode, c.lastPauseState != true else { return }
        guard let onClipEnded = c.onClipEnded else { return }

        let seconds = max(0.1, clip.targetDuration.seconds)
        c.stillClipTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            onClipEnded()
        }
    }

    // MARK: - Teardown

    @MainActor
    private static func tearDown(coordinator c: Coordinator) {
        c.stillClipTimer?.invalidate()
        c.stillClipTimer = nil
        c.stopSmartFramingTimer()

        c.removePlaybackEndObservers()
        c.removePlaybackTimeObservers()
        c.isWatchAdvanceInFlight = false

        c.contentView?.stop()
        c.contentView = nil
        c.currentPlayerItem = nil
        c.compositionID = nil
    }
}
