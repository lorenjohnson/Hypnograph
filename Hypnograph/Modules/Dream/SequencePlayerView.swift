//
//  SequencePlayerView.swift
//  Hypnograph
//
//  New architecture for sequence mode:
//  - Each source is handled independently (no giant AVComposition)
//  - Videos: AVPlayer for that clip only
//  - Still images: MetalImageView for direct CIImage display
//  - Navigation: simple index change, no seeking within empty time ranges
//

import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreImage
import HypnoCore
import HypnoEffects
import HypnoRenderer

/// Sequence mode player with proper handling of videos and still images
struct SequencePlayerView: NSViewRepresentable {
    let recipe: HypnogramRecipe
    let aspectRatio: AspectRatio
    let displayResolution: OutputResolution
    @Binding var currentSourceIndex: Int
    let isPaused: Bool
    let effectsChangeCounter: Int
    let effectManager: EffectManager
    /// Volume level (0.0 to 1.0) - use 0 for muted
    let volume: Float
    /// Audio output device UID (nil = system default)
    var audioDeviceUID: String? = nil

    /// Optional callback when source index changes (for syncing Performance Display)
    var onSourceIndexChanged: ((Int) -> Void)?

    class Coordinator: NSObject {
        // Current display mode
        enum DisplayMode {
            case video(AVPlayer)
            case stillImage(MetalImageView)
        }

        var displayMode: DisplayMode?
        var containerView: NSView?
        var playerView: AVPlayerView?
        var metalView: MetalImageView?

        // Timing
        var durationTimer: Timer?
        var currentSourceStartTime: Date?

        // State tracking
        var lastSourceIndex: Int = -1
        var lastPauseState: Bool?
        var lastEffectsCounter: Int?
        var lastVolume: Float?
        var lastRecipeIdentity: String?
        /// Use a sentinel to distinguish "never set" from "set to nil (system default)"
        private static let notSetSentinel = "___NOT_SET___"
        var lastAudioDeviceUID: String? = notSetSentinel

        func audioDeviceChanged(to newUID: String?) -> Bool {
            if lastAudioDeviceUID == Self.notSetSentinel { return true }
            return lastAudioDeviceUID != newUID
        }

        // End observer for video
        var endObserverToken: Any?

        var loadTask: Task<Void, Never>?
        
        deinit {
            cleanup()
        }
        
        func cleanup() {
            durationTimer?.invalidate()
            durationTimer = nil

            if let token = endObserverToken {
                NotificationCenter.default.removeObserver(token)
                endObserverToken = nil
            }

            if case .video(let player) = displayMode {
                player.pause()
            }

            loadTask?.cancel()
            loadTask = nil
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

        guard !recipe.sources.isEmpty else {
            c.cleanup()
            return
        }

        // Check if recipe changed significantly - clear image cache to prevent memory bloat
        let recipeIdentity = recipeIdentity(for: recipe)
        if c.lastRecipeIdentity != recipeIdentity {
            // Recipe changed - clear cached images that may no longer be needed
            let cacheSize = StillImageCache.cacheSize()
            if cacheSize.ciImages > 20 || cacheSize.cgImages > 20 {
                StillImageCache.clear()
            }
            c.lastRecipeIdentity = recipeIdentity
            c.lastSourceIndex = -1  // Force source reload
        }

        // Clamp index to valid range
        let validIndex = min(max(0, currentSourceIndex), recipe.sources.count - 1)

        // Check if we need to switch sources
        let needsSourceSwitch = validIndex != c.lastSourceIndex

        if needsSourceSwitch {
            switchToSource(index: validIndex, coordinator: c, container: nsView)
            c.lastSourceIndex = validIndex
            c.lastPauseState = nil  // Reset to apply pause state after switch
        }
        
        // Handle pause state changes
        if c.lastPauseState != isPaused {
            applyPauseState(coordinator: c)
            c.lastPauseState = isPaused
        }
        
        // Handle effects changes while paused
        if c.lastEffectsCounter != effectsChangeCounter {
            c.lastEffectsCounter = effectsChangeCounter
            if isPaused {
                forceRedraw(coordinator: c)
            }
        }

        // Apply volume to video player (muting is done via volume=0)
        if c.lastVolume != volume {
            if case .video(let player) = c.displayMode {
                player.volume = volume
            }
            c.lastVolume = volume
        }

        // Apply audio output device routing
        if c.audioDeviceChanged(to: audioDeviceUID) {
            if case .video(let player) = c.displayMode {
                player.audioOutputDeviceUniqueID = audioDeviceUID
            }
            c.lastAudioDeviceUID = audioDeviceUID
            print("🔊 SequencePlayerView: Audio device = \(audioDeviceUID ?? "System Default")")
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.cleanup()
    }
    
    // MARK: - Source Switching
    
    private func switchToSource(index: Int, coordinator c: Coordinator, container: NSView) {
        // Clean up previous source
        c.durationTimer?.invalidate()
        c.durationTimer = nil
        
        if let token = c.endObserverToken {
            NotificationCenter.default.removeObserver(token)
            c.endObserverToken = nil
        }
        
        let source = recipe.sources[index]
        let isStillImage = source.clip.file.mediaKind == .image
        
        if isStillImage {
            setupStillImage(source: source, index: index, coordinator: c, container: container)
        } else {
            setupVideo(source: source, index: index, coordinator: c, container: container)
        }
    }
    
    private func setupStillImage(source: HypnogramSource, index: Int, coordinator c: Coordinator, container: NSView) {
        print("🖼️ SequencePlayer: Switching to still image at index \(index)")

        // Remove video view if present
        c.playerView?.removeFromSuperview()
        c.playerView = nil

        // Create or reuse metal view
        let metalView: MetalImageView
        if let existing = c.metalView {
            metalView = existing
        } else {
            metalView = MetalImageView(frame: container.bounds)
            metalView.translatesAutoresizingMaskIntoConstraints = false
            c.metalView = metalView
        }

        // Add to container if not already
        if metalView.superview != container {
            container.addSubview(metalView)
            NSLayoutConstraint.activate([
                metalView.topAnchor.constraint(equalTo: container.topAnchor),
                metalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                metalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                metalView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        }

        // Load and display the image (async for Photos support)
        Task { @MainActor in
            guard let ciImage = await source.clip.file.loadImage() else {
                print("❌ SequencePlayer: Failed to load still image at index \(index)")
                return
            }

            // Pre-fill frame buffer for temporal effects
            self.effectManager.preloadFrameBuffer(from: ciImage)

            // Compose user transforms array into single transform
            let userTransform = source.transforms.reduce(CGAffineTransform.identity) { $0.concatenating($1) }
            metalView.display(
                image: ciImage,
                sourceIndex: index,
                aspectRatio: aspectRatio,
                transform: userTransform,
                enableEffects: true,
                effectManager: self.effectManager
            )

            // Start animation for time-based effects
            if !isPaused {
                metalView.startAnimation()
            }

            c.displayMode = .stillImage(metalView)

            // Setup duration timer for auto-advance
            if !isPaused {
                self.setupDurationTimer(duration: source.clip.duration, coordinator: c)
            }
        }
    }

    private func setupVideo(source: HypnogramSource, index: Int, coordinator c: Coordinator, container: NSView) {
        print("🎬 SequencePlayer: Switching to video at index \(index)")

        // Stop metal view animation
        c.metalView?.stopAnimation()
        c.metalView?.removeFromSuperview()

        // Create or reuse player view
        let playerView: AVPlayerView
        if let existing = c.playerView {
            playerView = existing
        } else {
            playerView = AVPlayerView()
            playerView.controlsStyle = .none
            // Use .resizeAspect since compositor already did aspectFill to renderSize
            playerView.videoGravity = .resizeAspect
            playerView.translatesAutoresizingMaskIntoConstraints = false
            c.playerView = playerView
        }

        // Add to container if not already
        if playerView.superview != container {
            container.addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: container.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        }

        // Build player item via RenderEngine (uses custom compositor internally)
        c.loadTask?.cancel()
        c.loadTask = Task {
            guard let asset = await source.clip.file.loadAsset() else {
                print("❌ SequencePlayer: Failed to load asset")
                return
            }

            guard !Task.isCancelled else { return }

            // Pre-roll frame buffer for temporal effects
            await self.effectManager.preloadFrameBuffer(from: asset, startTime: .zero)

            guard !Task.isCancelled else { return }

            let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: displayResolution.maxDimension)
            let engine = RenderEngine()
            let result = await engine.makePlayerItemForSource(
                source,
                sourceIndex: index,
                outputSize: outputSize,
                frameRate: 30,
                enableEffects: true,
                effectManager: self.effectManager
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                switch result {
                case .success(let playerItem):
                    let player: AVPlayer
                    if let existingPlayer = playerView.player {
                        existingPlayer.replaceCurrentItem(with: playerItem)
                        player = existingPlayer
                    } else {
                        player = AVPlayer(playerItem: playerItem)
                        playerView.player = player
                    }

                    c.displayMode = .video(player)

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
                    print("🔊 SequencePlayerView: Setup - Audio device = \(self.audioDeviceUID ?? "System Default"), volume=\(self.volume)")

                    // Setup end observer for clip duration
                    self.setupClipEndObserver(player: player, clipEndTime: source.clip.duration, coordinator: c)

                    // Apply pause state
                    if self.isPaused {
                        player.pause()
                    } else {
                        player.playImmediately(atRate: self.recipe.playRate)
                    }

                case .failure(let error):
                    print("❌ SequencePlayer: Failed to build player item: \(error)")
                }
            }
        }
    }

    // MARK: - Timing

    private func setupDurationTimer(duration: CMTime, coordinator c: Coordinator) {
        c.currentSourceStartTime = Date()
        c.durationTimer?.invalidate()

        c.durationTimer = Timer.scheduledTimer(withTimeInterval: duration.seconds, repeats: false) { [self] _ in
            advanceToNextSource(coordinator: c)
        }
    }

    private func setupClipEndObserver(player: AVPlayer, clipEndTime: CMTime, coordinator c: Coordinator) {
        // Use boundary time observer to detect when clip reaches its end
        let times = [NSValue(time: clipEndTime)]
        c.endObserverToken = player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [self] in
            advanceToNextSource(coordinator: c)
        }
    }

    private func advanceToNextSource(coordinator c: Coordinator) {
        let nextIndex = currentSourceIndex + 1
        let targetIndex: Int
        if nextIndex < recipe.sources.count {
            targetIndex = nextIndex
        } else {
            // Loop back to first source
            targetIndex = 0
        }

        DispatchQueue.main.async {
            self.currentSourceIndex = targetIndex
            // Notify callback for Performance Display sync
            self.onSourceIndexChanged?(targetIndex)
        }
    }

    // MARK: - Pause/Play

    private func applyPauseState(coordinator c: Coordinator) {
        switch c.displayMode {
        case .video(let player):
            if isPaused {
                player.pause()
            } else {
                player.playImmediately(atRate: recipe.playRate)
            }

        case .stillImage(let metalView):
            if isPaused {
                metalView.stopAnimation()
                c.durationTimer?.invalidate()
                c.durationTimer = nil
            } else {
                metalView.startAnimation()
                // Resume timer with remaining time
                if let startTime = c.currentSourceStartTime {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let source = recipe.sources[currentSourceIndex]
                    let remaining = source.clip.duration.seconds - elapsed
                    if remaining > 0 {
                        setupDurationTimer(
                            duration: CMTime(seconds: remaining, preferredTimescale: 600),
                            coordinator: c
                        )
                    }
                }
            }

        case .none:
            break
        }
    }

    // MARK: - Effects Redraw

    private func forceRedraw(coordinator c: Coordinator) {
        switch c.displayMode {
        case .video(let player):
            // Nudge seek to force re-render
            let currentTime = player.currentTime()
            let nudge = CMTime(value: 1, timescale: 600)
            player.seek(to: CMTimeAdd(currentTime, nudge), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }

        case .stillImage(let metalView):
            // Just request a redraw
            metalView.setNeedsDisplay(metalView.bounds)

        case .none:
            break
        }
    }

    /// Generate a simple identity string to detect recipe changes
    private func recipeIdentity(for recipe: HypnogramRecipe) -> String {
        let pairs = recipe.sources.map { source in
            // Include all transforms in identity string
            let transformsStr = source.transforms.map { t in
                "\(t.a),\(t.b),\(t.c),\(t.d),\(t.tx),\(t.ty)"
            }.joined(separator: ";")
            return "\(source.clip.file.displayName)|\(transformsStr)"
        }
        return "\(recipe.sources.count)|\(pairs.joined(separator: ","))"
    }
}
