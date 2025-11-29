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

/// Sequence mode player with proper handling of videos and still images
struct SequencePlayerView: NSViewRepresentable {
    let recipe: HypnogramRecipe
    let aspectRatio: AspectRatio
    @Binding var currentSourceIndex: Int
    let isPaused: Bool
    let effectsChangeCounter: Int
    let playRate: Float
    
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
        var lastRecipeIdentity: String?

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

        // Load and display the image
        if let ciImage = StillImageCache.ciImage(for: source.clip.file.url) {
            // Compose user transforms array into single transform
            let userTransform = source.transforms.reduce(CGAffineTransform.identity) { $0.concatenating($1) }
            metalView.display(
                image: ciImage,
                sourceIndex: index,
                aspectRatio: aspectRatio,
                transform: userTransform,
                enableEffects: true
            )

            // Start animation for time-based effects
            if !isPaused {
                metalView.startAnimation()
            }

            c.displayMode = .stillImage(metalView)

            // Setup duration timer for auto-advance
            if !isPaused {
                setupDurationTimer(duration: source.clip.duration, coordinator: c)
            }
        } else {
            print("❌ SequencePlayer: Failed to load still image at index \(index)")
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

        // Create player item with video composition for effects
        let asset = AVURLAsset(url: source.clip.file.url)

        // Build video composition with our custom compositor
        c.loadTask?.cancel()
        c.loadTask = Task {
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                print("❌ SequencePlayer: No video track in asset")
                return
            }

            let preferredTransform = try? await videoTrack.load(.preferredTransform)
            let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first

            guard !Task.isCancelled else { return }

            await MainActor.run {
                // Compose metadata transform with user transforms array
                let metadataTransform = preferredTransform ?? .identity
                let userTransform = source.transforms.reduce(CGAffineTransform.identity) { $0.concatenating($1) }
                let composedTransform = metadataTransform.concatenating(userTransform)

                // Create composition for single clip
                let composition = AVMutableComposition()
                guard let compVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    print("❌ SequencePlayer: Failed to create composition track")
                    return
                }

                // Insert the video clip portion
                let clipTimeRange = CMTimeRange(start: source.clip.startTime, duration: source.clip.duration)
                do {
                    try compVideoTrack.insertTimeRange(clipTimeRange, of: videoTrack, at: .zero)
                } catch {
                    print("❌ SequencePlayer: Failed to insert video time range: \(error)")
                    return
                }

                // Insert audio track if present
                if let audioTrack = audioTrack {
                    if let compAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) {
                        do {
                            try compAudioTrack.insertTimeRange(clipTimeRange, of: audioTrack, at: .zero)
                        } catch {
                            print("⚠️ SequencePlayer: Failed to insert audio time range: \(error)")
                            // Continue without audio
                        }
                    }
                }

                // Create video composition with our compositor
                // Use reference size for aspect ratio - AVPlayerView handles fitting to view
                let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: 1080)

                let videoComposition = AVMutableVideoComposition()
                videoComposition.renderSize = outputSize
                videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
                videoComposition.customVideoCompositorClass = FrameCompositor.self

                // Create instruction for the entire clip
                let instruction = RenderInstruction(
                    timeRange: CMTimeRange(start: .zero, duration: source.clip.duration),
                    layerTrackIDs: [compVideoTrack.trackID],
                    blendModes: [kBlendModeSourceOver],
                    transforms: [composedTransform],
                    sourceIndices: [index],
                    enableEffects: true,
                    stillImages: [nil]
                )
                videoComposition.instructions = [instruction]

                // Create player item with composition
                let playerItem = AVPlayerItem(asset: composition)
                playerItem.videoComposition = videoComposition

                let player: AVPlayer
                if let existingPlayer = playerView.player {
                    existingPlayer.replaceCurrentItem(with: playerItem)
                    player = existingPlayer
                } else {
                    player = AVPlayer(playerItem: playerItem)
                    playerView.player = player
                }

                c.displayMode = .video(player)

                // Setup end observer for clip duration
                self.setupClipEndObserver(player: player, clipEndTime: source.clip.duration, coordinator: c)

                // Apply pause state
                if self.isPaused {
                    player.pause()
                } else {
                    player.playImmediately(atRate: self.playRate)
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
        if nextIndex < recipe.sources.count {
            // Advance to next source
            DispatchQueue.main.async {
                self.currentSourceIndex = nextIndex
            }
        } else {
            // Loop back to first source
            DispatchQueue.main.async {
                self.currentSourceIndex = 0
            }
        }
    }

    // MARK: - Pause/Play

    private func applyPauseState(coordinator c: Coordinator) {
        switch c.displayMode {
        case .video(let player):
            if isPaused {
                player.pause()
            } else {
                player.playImmediately(atRate: playRate)
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
            return "\(source.clip.file.url.lastPathComponent)|\(transformsStr)"
        }
        return "\(recipe.sources.count)|\(pairs.joined(separator: ","))"
    }
}

