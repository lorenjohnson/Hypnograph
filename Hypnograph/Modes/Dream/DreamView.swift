import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Display view for Dream mode montage style.
/// All sources are composited together, looping at targetDuration.
/// Note: Sequence mode now uses SequencePlayerView instead.
struct DreamView: NSViewRepresentable {
    /// The recipe containing all sources and target duration
    let recipe: HypnogramRecipe

    /// Display style (kept for compatibility, but this view is only used for montage)
    let style: DreamStyle

    /// Preview render size
    let outputSize: CGSize

    /// Current source index (for flash solo in montage mode)
    @Binding var currentSourceIndex: Int

    /// Binding to track current playback time
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
        var currentTask: Task<Void, Never>?
        var lastPauseState: Bool?  // Track pause state to avoid redundant play/pause calls
        var lastEffectsCounter: Int?  // Track effects changes to force re-render when paused
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
                // DreamView is now only used for montage mode
                let strategy: CompositionBuilder.TimelineStrategy = .montage(targetDuration: recipe.targetDuration)

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
                        c.lastPauseState = nil  // Reset pause state tracking
                        c.lastEffectsCounter = effectsChangeCounter  // Track current effects state

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

                        // Setup montage observers
                        setupMontageObservers(player: player, item: buildResult.playerItem, coordinator: c)

                        // Seek to previous time
                        player.seek(to: previousTime)

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
                        if c.player == nil {
                            print("⚠️  DreamView: No player available after build failure")
                        } else {
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
                if isPaused, let player = c.player {
                    let currentTime = player.currentTime()
                    let nudgeAmount = CMTime(value: 1, timescale: 600)
                    let nudgedTime = CMTimeAdd(currentTime, nudgeAmount)

                    player.seek(to: nudgedTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] _ in
                        player?.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                }
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
        view.player = nil
    }
}

