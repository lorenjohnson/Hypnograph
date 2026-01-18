import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import HypnoCore

/// Player view for Dream module layered playback.
/// All sources are composited together, looping at targetDuration.
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

    class Coordinator {
        var player: AVPlayer?
        var containerView: NSView?
        var playerView: AVPlayerView?
        var timeObserverToken: Any?
        var endObserverToken: Any?
        var stillClipTimer: Timer?
        var statusObserver: NSKeyValueObservation?
        var compositionID: String?
        var currentTask: Task<Void, Never>?
        var lastPauseState: Bool?
        var lastEffectsCounter: Int?
        var currentPlayerItem: AVPlayerItem?
        var currentVideoComposition: AVVideoComposition?
        var playRate: Float = 0.8
        var lastVolume: Float?
        var watchMode: Bool = false
        var onClipEnded: (() -> Void)?
        var isAllStillImages: Bool = false
        /// Use a sentinel to distinguish "never set" from "set to nil (system default)"
        private static let notSetSentinel = "___NOT_SET___"
        var lastAudioDeviceUID: String? = notSetSentinel

        func audioDeviceChanged(to newUID: String?) -> Bool {
            if lastAudioDeviceUID == Self.notSetSentinel { return true }
            return lastAudioDeviceUID != newUID
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

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator

        // Always update playRate so closures use current value
        c.playRate = clip.playRate
        c.watchMode = watchMode
        c.onClipEnded = onClipEnded
        c.isAllStillImages = clip.sources.allSatisfy { $0.clip.file.mediaKind == .image }

        guard !clip.sources.isEmpty else {
            // Just pause, don't tear down - sources might be added back immediately
            c.player?.pause()
            c.currentTask?.cancel()
            c.currentTask = nil
            c.compositionID = nil
            if currentSourceTime != nil {
                currentSourceTime = nil
            }
            c.stillClipTimer?.invalidate()
            c.stillClipTimer = nil
            return
        }

        // Use display resolution for preview - AVPlayerView handles fitting to view
        let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: displayResolution.maxDimension)

        let newID = compositionIdentity(for: clip)

        if newID != c.compositionID {
            c.currentTask?.cancel()
            c.compositionID = newID

            // Clear old player item references to allow memory to be freed
            c.currentPlayerItem?.videoComposition = nil
            c.currentPlayerItem = nil
            c.currentVideoComposition = nil

            c.currentTask = Task {
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
                    await MainActor.run {
                        if c.compositionID == newID { c.compositionID = nil }
                    }
                    return
                }

                await MainActor.run {
                    guard c.compositionID == newID else { return }

                    switch result {
                    case .success(let playerItem):
                        // Create or reuse player view
                        let playerView: AVPlayerView
                        if let existing = c.playerView {
                            playerView = existing
                        } else {
                            playerView = AVPlayerView()
                            playerView.controlsStyle = .none
                            playerView.translatesAutoresizingMaskIntoConstraints = false
                            c.playerView = playerView
                        }
                        // Set gravity based on aspect ratio mode
                        // fillWindow uses .resizeAspectFill to scale content to fill the view
                        // Other ratios use .resizeAspect since compositor already sized to that ratio
                        playerView.videoGravity = aspectRatio.isFillWindow ? .resizeAspectFill : .resizeAspect

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

                        let player: AVPlayer
                        if let existing = c.player {
                            player = existing
                            player.replaceCurrentItem(with: playerItem)
                        } else {
                            player = AVPlayer(playerItem: playerItem)
                            c.player = player
                        }

                        c.currentPlayerItem = playerItem
                        c.currentVideoComposition = playerItem.videoComposition
                        playerView.player = player

                        // Use high-quality audio time pitch algorithm for non-1.0 playback rates
                        playerItem.audioTimePitchAlgorithm = .timeDomain

                        // Apply volume and audio device immediately, before playback starts.
                        // This is necessary because player setup runs in an async Task that
                        // completes after updateNSView() returns. SwiftUI won't call updateNSView
                        // again until a binding changes, so the audio settings logic at the end of
                        // updateNSView would miss the window before playImmediately() is called.
                        // Note: muting is done via volume=0, not player.isMuted
                        player.volume = self.volume
                        player.audioOutputDeviceUniqueID = self.audioDeviceUID
                        c.lastVolume = self.volume
                        c.lastAudioDeviceUID = self.audioDeviceUID
                        print("🔊 PreviewPlayerView: Setup - Audio device = \(self.audioDeviceUID ?? "System Default"), volume=\(self.volume)")

                        c.lastPauseState = nil
                        c.lastEffectsCounter = effectsChangeCounter

                        self.setupMontageObservers(player: player, item: playerItem, coordinator: c)

                        // Wait for player item to be ready before starting playback
                        c.statusObserver?.invalidate()
                        c.statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak player, weak c] item, _ in
                            guard let player = player, let c = c else { return }
                            if item.status == .readyToPlay {
                                c.statusObserver?.invalidate()
                                c.statusObserver = nil
                                if c.isAllStillImages {
                                    // All-still clips don't advance time via AVPlayer; keep it paused on frame 0.
                                    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                                    player.pause()
                                    if c.lastPauseState != true {
                                        self.scheduleStillClipTimer(coordinator: c)
                                    }
                                } else if c.lastPauseState != true {
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
                        error.log(context: "PreviewPlayerView")
                        c.compositionID = nil
                        if currentSourceTime != nil {
                            currentSourceTime = nil
                        }
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
                    c.player?.pause()
                } else {
                    c.player?.playImmediately(atRate: clip.playRate)
                }
                c.lastPauseState = isPaused
            }

            if c.lastEffectsCounter != effectsChangeCounter {
                c.lastEffectsCounter = effectsChangeCounter
                if let player = c.player {
                    if c.isAllStillImages {
                        // Force redraw of still frame at t=0
                        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    } else if isPaused {
                        // Only force redraw when paused - while playing, compositor picks up changes naturally
                        let currentTime = player.currentTime()
                        player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                }
            }
        }

        // Apply volume (muting is done via volume=0)
        if c.lastVolume != volume {
            c.player?.volume = volume
            c.lastVolume = volume
        }

        // Apply audio output device routing
        if c.audioDeviceChanged(to: audioDeviceUID) {
            c.player?.audioOutputDeviceUniqueID = audioDeviceUID
            c.lastAudioDeviceUID = audioDeviceUID
            print("🔊 PreviewPlayerView: Audio device = \(audioDeviceUID ?? "System Default")")
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        tearDown(coordinator: coordinator)
    }
    
    // MARK: - Helpers

    private func compositionIdentity(for clip: HypnogramClip) -> String {
        // Blend modes are dynamic (managed by EffectManager), but transforms are baked
        let pairs: [String] = clip.sources.enumerated().map { index, source in
            let name = source.clip.file.displayName
            let start = source.clip.startTime.seconds
            let dur = source.clip.duration.seconds
            // Include all transforms in identity string
            let transformsStr = source.transforms.map { t in
                "\(t.a),\(t.b),\(t.c),\(t.d),\(t.tx),\(t.ty)"
            }.joined(separator: ";")
            return "\(name)|\(start)|\(dur)|\(transformsStr)"
        }
        let durationPart = "dur=\(clip.targetDuration.seconds)"
        let framingPart = "framing=\(sourceFraming.rawValue)"
        return pairs.joined(separator: ";;") + "||" + durationPart + "||" + framingPart
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
        c.stillClipTimer?.invalidate()
        c.stillClipTimer = nil

        // Track playback time
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

        if c.isAllStillImages {
            // AVPlayer ends immediately for all-still compositions; use a timer for watch-mode advancement.
            scheduleStillClipTimer(coordinator: c)
        } else {
            // Loop at end - respect pause state
            c.endObserverToken = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player, weak c] _ in
                guard let p = player, let c = c else { return }
                if c.watchMode, let onClipEnded = c.onClipEnded {
                    onClipEnded()
                    return
                }
                p.seek(to: .zero)
                // Only play if not paused
                if c.lastPauseState != true {
                    p.playImmediately(atRate: c.playRate)
                }
            }
        }
    }

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

        c.stillClipTimer?.invalidate()
        c.stillClipTimer = nil

        c.player?.pause()
        c.playerView?.player = nil
        c.player = nil
        c.currentPlayerItem = nil
        c.compositionID = nil
    }
}
