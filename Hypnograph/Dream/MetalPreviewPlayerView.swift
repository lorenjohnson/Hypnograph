//
//  MetalPreviewPlayerView.swift
//  Hypnograph
//
//  Metal-based preview player using the new Metal playback pipeline.
//  Drop-in replacement for PreviewPlayerView for testing Direction A.
//

import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import HypnoCore

/// Metal-based player view for Dream module layered playback.
/// Uses MetalPlayerController for GPU-accelerated frame display.
struct MetalPreviewPlayerView: NSViewRepresentable {
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

    @MainActor
    class Coordinator {
        var metalController: MetalPlayerController?
        var containerView: NSView?
        var stillClipTimer: Timer?
        var statusObserver: NSKeyValueObservation?
        var compositionID: String?
        var currentTask: Task<Void, Never>?
        var lastPauseState: Bool?
        var lastEffectsCounter: Int?
        var currentPlayerItem: AVPlayerItem?
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

    @MainActor
    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator

        // Always update playRate so closures use current value
        c.playRate = clip.playRate
        c.watchMode = watchMode
        c.onClipEnded = onClipEnded
        c.isAllStillImages = clip.sources.allSatisfy { $0.clip.file.mediaKind == .image }

        guard !clip.sources.isEmpty else {
            // Just pause, don't tear down - sources might be added back immediately
            c.metalController?.pause()
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

        // Use display resolution for preview
        let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: displayResolution.maxDimension)

        let newID = compositionIdentity(for: clip)

        if newID != c.compositionID {
            c.currentTask?.cancel()
            c.compositionID = newID

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
                    // Create or reuse Metal controller
                    let controller: MetalPlayerController
                    if let existing = c.metalController {
                        controller = existing
                    } else {
                        controller = MetalPlayerController()
                        c.metalController = controller
                    }

                    // Set content mode based on aspect ratio
                    let contentMode: MetalPlayerView.ContentMode = aspectRatio.isFillWindow ? .aspectFill : .aspectFit
                    controller.setContentMode(contentMode)

                    // Add Metal view to container if needed
                    let metalView = controller.view
                    if metalView.superview != nsView {
                        metalView.translatesAutoresizingMaskIntoConstraints = false
                        nsView.addSubview(metalView)
                        NSLayoutConstraint.activate([
                            metalView.topAnchor.constraint(equalTo: nsView.topAnchor),
                            metalView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
                            metalView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                            metalView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor)
                        ])
                    }

                    // Use high-quality audio time pitch algorithm
                    playerItem.audioTimePitchAlgorithm = .timeDomain

                    // Configure looping (handled by MetalPlayerController)
                    // For watch mode, we need custom end handling
                    controller.setLooping(!self.watchMode)

                    // Load the player item into Metal controller
                    controller.load(playerItem: playerItem)

                    c.currentPlayerItem = playerItem

                    // Apply volume and audio device immediately
                    controller.volume = self.volume
                    controller.audioOutputDeviceUniqueID = self.audioDeviceUID
                    c.lastVolume = self.volume
                    c.lastAudioDeviceUID = self.audioDeviceUID
                    print("🔊 MetalPreviewPlayerView: Setup - Audio device = \(self.audioDeviceUID ?? "System Default"), volume=\(self.volume)")

                    c.lastPauseState = nil
                    c.lastEffectsCounter = effectsChangeCounter

                    // Wait for player item to be ready before starting playback
                    c.statusObserver?.invalidate()
                    c.statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak controller, weak c] item, _ in
                        guard let controller = controller, let c = c else { return }
                        if item.status == .readyToPlay {
                            c.statusObserver?.invalidate()
                            c.statusObserver = nil

                            Task { @MainActor in
                                if c.isAllStillImages {
                                    // All-still clips don't advance time; keep paused on frame 0
                                    controller.seek(to: .zero)
                                    controller.pause()
                                    if c.lastPauseState != true {
                                        self.scheduleStillClipTimer(coordinator: c)
                                    }
                                } else if c.lastPauseState != true {
                                    controller.play(rate: c.playRate)
                                }
                            }
                        }
                    }

                    if self.isPaused {
                        c.lastPauseState = true
                    } else {
                        c.lastPauseState = false
                    }

                case .failure(let error):
                    error.log(context: "MetalPreviewPlayerView")
                    c.compositionID = nil
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
                    c.metalController?.pause()
                } else {
                    c.metalController?.play(rate: clip.playRate)
                }
                c.lastPauseState = isPaused
            }

            if c.lastEffectsCounter != effectsChangeCounter {
                c.lastEffectsCounter = effectsChangeCounter
                if let controller = c.metalController {
                    if c.isAllStillImages {
                        // Force redraw of still frame at t=0
                        controller.seek(to: .zero)
                    } else if isPaused {
                        // Only force redraw when paused
                        controller.seek(to: controller.currentTime)
                    }
                }
            }
        }

        // Apply volume
        if c.lastVolume != volume {
            c.metalController?.volume = volume
            c.lastVolume = volume
        }

        // Apply audio output device routing
        if c.audioDeviceChanged(to: audioDeviceUID) {
            c.metalController?.audioOutputDeviceUniqueID = audioDeviceUID
            c.lastAudioDeviceUID = audioDeviceUID
            print("🔊 MetalPreviewPlayerView: Audio device = \(audioDeviceUID ?? "System Default")")
        }
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
        c.statusObserver?.invalidate()
        c.statusObserver = nil

        c.stillClipTimer?.invalidate()
        c.stillClipTimer = nil

        c.metalController?.stop()
        c.metalController = nil
        c.currentPlayerItem = nil
        c.compositionID = nil
    }
}
