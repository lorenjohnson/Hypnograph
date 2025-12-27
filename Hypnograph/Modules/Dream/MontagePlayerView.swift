import SwiftUI
import AVKit
import AVFoundation
import CoreMedia

/// Player view for Dream module montage style.
/// All sources are composited together, looping at targetDuration.
struct MontagePlayerView: NSViewRepresentable {
    let recipe: HypnogramRecipe
    let aspectRatio: AspectRatio
    let displayResolution: OutputResolution
    @Binding var currentSourceIndex: Int
    @Binding var currentSourceTime: CMTime?
    let isPaused: Bool
    let effectsChangeCounter: Int
    let effectManager: EffectManager
    let isMuted: Bool
    let volume: Float
    var audioRouter: AudioRouter? = nil

    class Coordinator {
        var player: AVPlayer?
        var containerView: NSView?
        var playerView: AVPlayerView?
        var timeObserverToken: Any?
        var endObserverToken: Any?
        var statusObserver: NSKeyValueObservation?
        var compositionID: String?
        var currentTask: Task<Void, Never>?
        var lastPauseState: Bool?
        var lastEffectsCounter: Int?
        var currentPlayerItem: AVPlayerItem?
        var currentVideoComposition: AVVideoComposition?
        var playRate: Float = 0.8
        var lastMutedState: Bool?
        var lastVolume: Float?
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

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator

        // Always update playRate so closures use current value
        c.playRate = recipe.playRate

        guard !recipe.sources.isEmpty else {
            // Just pause, don't tear down - sources might be added back immediately
            c.player?.pause()
            c.currentTask?.cancel()
            c.currentTask = nil
            c.compositionID = nil
            if currentSourceTime != nil {
                currentSourceTime = nil
            }
            return
        }

        // Use display resolution for preview - AVPlayerView handles fitting to view
        let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: displayResolution.maxDimension)

        let newID = compositionIdentity(for: recipe)

        if newID != c.compositionID {
            c.currentTask?.cancel()
            c.compositionID = newID

            // Clear old player item references to allow memory to be freed
            c.currentPlayerItem?.videoComposition = nil
            c.currentPlayerItem = nil
            c.currentVideoComposition = nil

            c.currentTask = Task {
                let engine = RenderEngine()
                let strategy: CompositionBuilder.TimelineStrategy = .montage(targetDuration: recipe.targetDuration)
                let config = RenderEngine.Config(
                    outputSize: outputSize,
                    frameRate: 30,
                    enableGlobalEffects: true
                )

                let result = await engine.makePlayerItem(
                    recipe: recipe,
                    strategy: strategy,
                    config: config,
                    effectManager: effectManager
                )

                guard !Task.isCancelled else {
                    await MainActor.run {
                        if c.compositionID == newID { c.compositionID = nil }
                    }
                    return
                }

                await MainActor.run {
                    guard c.compositionID == newID else { return }

                    switch result {
                    case .success(let buildResult):
                        // Create or reuse player view
                        let playerView: AVPlayerView
                        if let existing = c.playerView {
                            playerView = existing
                        } else {
                            playerView = AVPlayerView()
                            playerView.controlsStyle = .none
                            // Use .resizeAspect since compositor already did aspectFill to outputSize
                            // Using .resizeAspectFill here would double-crop
                            playerView.videoGravity = .resizeAspect
                            playerView.translatesAutoresizingMaskIntoConstraints = false
                            c.playerView = playerView
                        }

                        // Add to container if needed
                        if playerView.superview != nsView {
                            nsView.addSubview(playerView)
                            NSLayoutConstraint.activate([
                                playerView.topAnchor.constraint(equalTo: nsView.topAnchor),
                                playerView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
                                playerView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                                playerView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor)
                            ])
                        }

                        // TODO: Audio routing to specific device will be implemented later
                        // For now, audio plays through system default when not muted

                        let player: AVPlayer
                        if let existing = c.player {
                            player = existing
                            player.replaceCurrentItem(with: buildResult.playerItem)
                        } else {
                            player = AVPlayer(playerItem: buildResult.playerItem)
                            c.player = player
                        }

                        c.currentPlayerItem = buildResult.playerItem
                        c.currentVideoComposition = buildResult.playerItem.videoComposition
                        playerView.player = player

                        // Apply mute and volume immediately, before playback starts.
                        // This is necessary because player setup runs in an async Task that
                        // completes after updateNSView() returns. SwiftUI won't call updateNSView
                        // again until a binding changes, so the mute/volume logic at the end of
                        // updateNSView would miss the window before playImmediately() is called.
                        player.isMuted = self.isMuted
                        player.volume = self.volume
                        c.lastMutedState = self.isMuted
                        c.lastVolume = self.volume

                        c.lastPauseState = nil
                        c.lastEffectsCounter = effectsChangeCounter

                        self.setupMontageObservers(player: player, item: buildResult.playerItem, coordinator: c)

                        // Wait for player item to be ready before starting playback
                        c.statusObserver?.invalidate()
                        c.statusObserver = buildResult.playerItem.observe(\.status, options: [.initial, .new]) { [weak player, weak c] item, _ in
                            guard let player = player, let c = c else { return }
                            if item.status == .readyToPlay {
                                c.statusObserver?.invalidate()
                                c.statusObserver = nil
                                if c.lastPauseState != true {
                                    player.playImmediately(atRate: c.playRate)
                                }
                            }
                        }

                        if self.isPaused {
                            c.lastPauseState = true
                        } else {
                            c.lastPauseState = false
                        }

                    case .failure(let error):
                        error.log(context: "MontagePlayerView")
                        c.compositionID = nil
                        if currentSourceTime != nil {
                            currentSourceTime = nil
                        }
                    }
                }
            }
        } else {
            if c.lastPauseState != isPaused {
                if isPaused {
                    c.player?.pause()
                } else {
                    c.player?.playImmediately(atRate: recipe.playRate)
                }
                c.lastPauseState = isPaused
            }

            if c.lastEffectsCounter != effectsChangeCounter {
                c.lastEffectsCounter = effectsChangeCounter
                // Only force redraw when paused - while playing, compositor picks up changes naturally
                if isPaused, let player = c.player {
                    let currentTime = player.currentTime()
                    player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }

        // Apply mute state
        // TODO: When audio routing is implemented, route to specific device
        // For now, just mute/unmute based on whether an audio device is selected
        if c.lastMutedState != isMuted {
            c.player?.isMuted = isMuted
            c.lastMutedState = isMuted
            print("🔊 MontagePlayerView: Player muted = \(isMuted)")
        }

        // Apply volume
        if c.lastVolume != volume {
            c.player?.volume = volume
            c.lastVolume = volume
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        tearDown(coordinator: coordinator)
    }
    
    // MARK: - Helpers

    private func compositionIdentity(for recipe: HypnogramRecipe) -> String {
        // Blend modes are dynamic (managed by EffectManager), but transforms are baked
        let pairs: [String] = recipe.sources.enumerated().map { index, source in
            let name = source.clip.file.displayName
            let start = source.clip.startTime.seconds
            let dur = source.clip.duration.seconds
            // Include all transforms in identity string
            let transformsStr = source.transforms.map { t in
                "\(t.a),\(t.b),\(t.c),\(t.d),\(t.tx),\(t.ty)"
            }.joined(separator: ";")
            return "\(name)|\(start)|\(dur)|\(transformsStr)"
        }
        let durationPart = "dur=\(recipe.targetDuration.seconds)"
        return pairs.joined(separator: ";;") + "||" + durationPart + "||montage"
    }

    // MARK: - Observer setup

    private func setupMontageObservers(
        player: AVPlayer,
        item: AVPlayerItem,
        coordinator c: Coordinator
    ) {
        // Remove previous observers first (same player, new item)
        if let token = c.timeObserverToken {
            player.removeTimeObserver(token)
            c.timeObserverToken = nil
        }
        if let token = c.endObserverToken {
            NotificationCenter.default.removeObserver(token)
            c.endObserverToken = nil
        }

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
                p.playImmediately(atRate: c.playRate)
            }
        }
    }

    // MARK: - Teardown

    private static func tearDown(coordinator c: Coordinator) {
        c.statusObserver?.invalidate()
        c.statusObserver = nil

        if let token = c.timeObserverToken, let player = c.player {
            player.removeTimeObserver(token)
        }
        c.timeObserverToken = nil

        if let token = c.endObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        c.endObserverToken = nil

        c.player?.pause()
        c.playerView?.player = nil
        c.player = nil
        c.currentPlayerItem = nil
        c.compositionID = nil
    }
}

