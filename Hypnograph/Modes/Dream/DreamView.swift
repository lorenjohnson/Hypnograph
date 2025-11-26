import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Unified display view for Dream mode, supporting both montage and sequence styles.
///
/// - **Montage style**: All sources composited together, looping at targetDuration
/// - **Sequence style**: All sources concatenated in timeline, seek to current source
struct DreamView: NSViewRepresentable {
    /// The recipe containing all sources and target duration
    let recipe: HypnogramRecipe
    
    /// Display style: montage (layered) or sequence (timeline)
    let style: DreamStyle
    
    /// Preview render size
    let outputSize: CGSize

    /// Current source index (used for seeking in sequence style, auto-updated during playback)
    @Binding var currentSourceIndex: Int

    /// Binding to track current playback time (montage style only)
    @Binding var currentSourceTime: CMTime?

    /// Whether playback is paused
    let isPaused: Bool

    /// Counter that increments when effects change (triggers re-render when paused)
    let effectsChangeCounter: Int

    let playRate: Float = 0.8
    
    class Coordinator {
        var player: AVPlayer?
        var timeObserverToken: Any?
        var endObserverToken: Any?
        var compositionID: String?
        var clipStartTimes: [CMTime] = []
        var currentTask: Task<Void, Never>?
        var lastPauseState: Bool?  // Track pause state to avoid redundant play/pause calls
        var lastEffectsCounter: Int?  // Track effects changes to force re-render when paused
        var lastObservedIndex: Int = 0  // Last index observed from playback (for auto-update)
        var lastRequestedIndex: Int = 0  // Last index requested by user (for manual seek)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.player = AVPlayer()
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        let c = context.coordinator

        guard !recipe.sources.isEmpty else {
            Self.tearDown(coordinator: c, view: nsView)
            if currentSourceTime != nil {
                currentSourceTime = nil
            }
            return
        }

        let newID = compositionIdentity(for: recipe, style: style)

        if newID != c.compositionID || c.player == nil {
            // Cancel any pending build
            c.currentTask?.cancel()

            // Build player item asynchronously using RenderEngine
            c.currentTask = Task {
                let engine = RenderEngine()
                let strategy: CompositionBuilder.TimelineStrategy = (style == .montage)
                    ? .montage(targetDuration: recipe.targetDuration)
                    : .sequence

                let config = RenderEngine.Config(
                    outputSize: outputSize,
                    frameRate: 30,
                    enableGlobalHooks: true
                )

                let result = await engine.makePlayerItem(
                    recipe: recipe,
                    strategy: strategy,
                    config: config
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    switch result {
                    case .success(let buildResult):
                        let previousTime = c.player?.currentTime() ?? .zero
                        let player: AVPlayer
                        if let existing = c.player {
                            player = existing
                            player.replaceCurrentItem(with: buildResult.playerItem)
                        } else {
                            player = AVPlayer(playerItem: buildResult.playerItem)
                            c.player = player
                        }

                        nsView.player = player
                        c.compositionID = newID
                        c.clipStartTimes = buildResult.clipStartTimes
                        c.lastPauseState = nil  // Reset pause state tracking
                        c.lastEffectsCounter = effectsChangeCounter  // Track current effects state
                        c.lastObservedIndex = 0
                        c.lastRequestedIndex = currentSourceIndex

                        // Sync blend modes from recipe to manager for dynamic rendering
                        // Use silent=true to avoid triggering re-render during initialization
                        if let manager = GlobalRenderHooks.manager {
                            let blendModes = self.resolvedBlendModes(from: recipe)
                            for (index, mode) in blendModes.enumerated() {
                                manager.setBlendMode(mode, for: index, silent: true)
                            }
                        }

                        // Remove previous observers
                        if let token = c.timeObserverToken {
                            player.removeTimeObserver(token)
                            c.timeObserverToken = nil
                        }
                        if let token = c.endObserverToken {
                            NotificationCenter.default.removeObserver(token)
                            c.endObserverToken = nil
                        }

                        // Setup observers based on style
                        switch style {
                        case .montage:
                            setupMontageObservers(player: player, item: buildResult.playerItem, coordinator: c)
                        case .sequence:
                            setupSequenceObservers(player: player, item: buildResult.playerItem, coordinator: c)
                        }

                        // For sequence mode, seek to the current source
                        if style == .sequence, currentSourceIndex < buildResult.clipStartTimes.count {
                            let seekTime = buildResult.clipStartTimes[currentSourceIndex]
                            player.seek(to: seekTime)
                            c.lastRequestedIndex = currentSourceIndex
                            c.lastObservedIndex = currentSourceIndex
                        } else {
                            player.seek(to: previousTime)
                        }

                        // Respect pause state
                        if isPaused {
                            player.pause()
                        } else {
                            player.playImmediately(atRate: playRate)
                        }
                        c.lastPauseState = isPaused

                    case .failure(let error):
                        error.log(context: "DreamView")
                        // Don't tear down completely - keep existing player if available
                        // This allows recovery without full restart
                        if c.player == nil {
                            // No player exists, create a black placeholder
                            print("⚠️  DreamView: No player available after build failure, creating placeholder")
                        } else {
                            // Keep existing player running - user can try again
                            print("⚠️  DreamView: Build failed but keeping existing player")
                        }
                        if currentSourceTime != nil {
                            currentSourceTime = nil
                        }
                    }
                }
            }
        } else {
            // Handle pause state changes without rebuilding composition
            if c.lastPauseState != isPaused {
                if isPaused {
                    c.player?.pause()
                } else {
                    c.player?.playImmediately(atRate: playRate)
                }
                c.lastPauseState = isPaused
            }

            // Handle effects/blend mode changes while paused - force re-render of current frame
            if c.lastEffectsCounter != effectsChangeCounter {
                c.lastEffectsCounter = effectsChangeCounter

                // If paused, seek to force frame re-render
                // We need to seek to a slightly different time, then back, to force AVFoundation
                // to actually request a new frame (seeking to the same time is a no-op)
                if isPaused, let player = c.player {
                    let currentTime = player.currentTime()
                    let nudgeAmount = CMTime(value: 1, timescale: 600) // ~0.0017 seconds
                    let nudgedTime = CMTimeAdd(currentTime, nudgeAmount)

                    // Seek forward slightly, then back to original time
                    player.seek(to: nudgedTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] _ in
                        player?.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                }
            }

            // In sequence style, seek when user manually changes source
            // User navigation always seeks, even during playback
            if style == .sequence,
               currentSourceIndex != c.lastRequestedIndex,
               currentSourceIndex < c.clipStartTimes.count {
                let seekTime = c.clipStartTimes[currentSourceIndex]
                c.player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [self] finished in
                    if finished {
                        // Continue playing at current rate (respects pause state)
                        if !self.isPaused {
                            c.player?.playImmediately(atRate: self.playRate)
                        }
                    }
                }
                c.lastRequestedIndex = currentSourceIndex
                c.lastObservedIndex = currentSourceIndex
            }
        }
    }
    
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        tearDown(coordinator: coordinator, view: nsView)
    }
    
    // MARK: - Helpers
    
    private func compositionIdentity(for recipe: HypnogramRecipe, style: DreamStyle) -> String {
        // Blend modes are now dynamic (managed by RenderHookManager), so don't include them in identity
        let pairs: [String] = recipe.sources.enumerated().map { index, source in
            let url = source.clip.file.url.path
            let start = source.clip.startTime.seconds
            let dur = source.clip.duration.seconds
            return "\(url)|\(start)|\(dur)"
        }
        let durationPart = "dur=\(recipe.targetDuration.seconds)"
        let stylePart = "style=\(style.rawValue)"
        return pairs.joined(separator: ";;") + "||" + durationPart + "||" + stylePart
    }
    
    private func resolvedBlendModes(from recipe: HypnogramRecipe) -> [String] {
        let count = recipe.sources.count
        let modeData = recipe.mode?.sourceData ?? []

        return (0..<count).map { idx in
            if idx == 0 { return kBlendModeSourceOver }
            let stored = (idx < modeData.count) ? modeData[idx]["blendMode"] : nil
            return stored ?? kBlendModeDefaultMontage
        }
    }

    // MARK: - Observer setup

    private func setupMontageObservers(
        player: AVPlayer,
        item: AVPlayerItem,
        coordinator c: Coordinator
    ) {
        // Track playback time for montage
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        c.timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            // Only update if the time actually changed to avoid triggering unnecessary publishes
            if self.currentSourceTime != time {
                self.currentSourceTime = time
            }
        }

        // Loop at end - respect pause state
        c.endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player, weak c] _ in
            guard let p = player, let c = c else { return }
            p.seek(to: .zero)
            // Only play if not paused
            if c.lastPauseState != true {
                p.playImmediately(atRate: 0.8)
            }
        }
    }

    private func setupSequenceObservers(
        player: AVPlayer,
        item: AVPlayerItem,
        coordinator c: Coordinator
    ) {
        // Track playback time to update currentSourceIndex as clips play
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        c.timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak c] time in
            guard let c = c, !c.clipStartTimes.isEmpty else { return }

            // Find which clip is currently playing based on time
            var playingIndex = 0
            for (index, startTime) in c.clipStartTimes.enumerated() {
                if time >= startTime {
                    playingIndex = index
                } else {
                    break
                }
            }

            // Update observed index if it changed
            if c.lastObservedIndex != playingIndex {
                c.lastObservedIndex = playingIndex

                // Only update currentSourceIndex if user hasn't manually navigated elsewhere
                // This allows the HUD to track playback automatically, but manual navigation takes precedence
                if self.currentSourceIndex == c.lastRequestedIndex {
                    self.currentSourceIndex = playingIndex
                    c.lastRequestedIndex = playingIndex
                }
            }
        }

        // Loop sequence mode at end - respect pause state
        c.endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player, weak c] _ in
            guard let p = player, let c = c else { return }
            p.seek(to: .zero)
            // Reset to first clip when looping
            c.lastObservedIndex = 0
            c.lastRequestedIndex = 0
            self.currentSourceIndex = 0
            // Only play if not paused
            if c.lastPauseState != true {
                p.playImmediately(atRate: 0.8)
            }
        }
    }

    // MARK: - Teardown

    private static func tearDown(coordinator c: Coordinator, view: AVPlayerView) {
        if let token = c.timeObserverToken, let player = c.player {
            player.removeTimeObserver(token)
        }
        c.timeObserverToken = nil

        if let token = c.endObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        c.endObserverToken = nil

        c.player?.pause()
        c.player = nil
        c.compositionID = nil
        c.clipStartTimes = []
        c.lastObservedIndex = 0
        c.lastRequestedIndex = 0
        view.player = nil
    }
}

