//
//  PlayerContentView.swift
//  Hypnograph
//
//  Content view with A/B player sources for shader-based transitions.
//  Used by both Preview and Live displays.
//

import AppKit
import AVFoundation
import HypnoCore

/// Content view with A/B player sources for shader-based transitions.
/// Used by both Preview and Live displays with a single unified Metal surface.
final class PlayerContentView: NSView {

    // MARK: - Properties

    /// The Metal view for display
    let playerView: PlayerView

    /// Frame source A (for A/B transitions)
    private var sourceA: AVPlayerFrameSource?

    /// Frame source B (for A/B transitions)
    private var sourceB: AVPlayerFrameSource?

    /// Which source is currently active
    private var activeSlot: PlayerSlot = .a

    /// Target output volume for this content view (0.0 to 1.0)
    private var baseVolume: Float = 1.0

    /// Slot that is fading out during an active transition.
    /// During transitions, `activeSlot` is updated immediately to the incoming slot.
    private var outgoingSlotDuringTransition: PlayerSlot?

    /// Active frame source
    var activeFrameSource: AVPlayerFrameSource? {
        activeSlot == .a ? sourceA : sourceB
    }

    /// The currently active AVPlayer (for audio, volume, etc.)
    var activeAVPlayer: AVPlayer? {
        activeFrameSource?.player
    }

    /// Both players (for registering observers on both during transitions)
    var allPlayers: [AVPlayer] {
        [sourceA?.player, sourceB?.player].compactMap { $0 }
    }

    enum PlayerSlot {
        case a, b
        var opposite: PlayerSlot { self == .a ? .b : .a }
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        // Create Metal view
        playerView = PlayerView(frame: frameRect, device: SharedRenderer.metalDevice)

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // Add Metal view as subview
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // Create frame sources with their own AVPlayers
        let playerA = AVPlayer()
        let playerB = AVPlayer()

        sourceA = AVPlayerFrameSource(player: playerA)
        sourceB = AVPlayerFrameSource(player: playerB)

        // Set initial primary source
        playerView.primarySource = sourceA

        // Default: only the active slot should be audible.
        applyAudioMix(progress: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Playback Control

    /// Load a player item into the inactive slot and start transition
    /// - Parameters:
    ///   - playerItem: The player item to load
    ///   - transitionType: Type of transition to use
    ///   - duration: Duration of the transition
    ///   - playRate: Playback rate for the new clip (nil = don't auto-start)
    ///   - completion: Called when transition completes
    func loadAndTransition(
        playerItem: AVPlayerItem,
        transitionType: TransitionRenderer.TransitionType = .crossfade,
        duration: TimeInterval = 1.5,
        playRate: Float? = nil,
        completion: (() -> Void)? = nil
    ) {
        let outgoingSlot = activeSlot
        let nextSlot = outgoingSlot.opposite
        let nextSource = nextSlot == .a ? sourceA : sourceB

        guard let nextSource = nextSource else {
            print("⚠️ PlayerContentView: Missing frame source")
            return
        }

        // Configure the next source with the player item
        nextSource.configure(with: playerItem)

        // Start playback if rate is specified
        if let rate = playRate {
            nextSource.player.playImmediately(atRate: rate)
        }

        // Handle instant cut (no transition)
        if transitionType == .none {
            outgoingSlotDuringTransition = nil
            playerView.onTransitionProgress = nil

            // Stop the outgoing player's audio
            let outgoingSource = outgoingSlot == .a ? sourceA : sourceB
            outgoingSource?.player.pause()
            outgoingSource?.player.replaceCurrentItem(with: nil)

            playerView.cancelTransition()
            playerView.primarySource = nextSource
            activeSlot = nextSlot
            applyAudioMix(progress: nil)
            notifyMirrors()
            print("🎬 PlayerContentView: Instant cut (no transition)")
            completion?()
            return
        }

        // Start the shader transition
        guard let currentSource = outgoingSlot == .a ? sourceA : sourceB else {
            // No current source - just set as primary
            playerView.primarySource = nextSource
            activeSlot = nextSlot
            applyAudioMix(progress: nil)
            completion?()
            return
        }

        outgoingSlotDuringTransition = outgoingSlot
        activeSlot = nextSlot

        // Audio: fade out outgoing while fading in incoming.
        var didNotifyMirrorsForTransitionStart = false
        playerView.onTransitionProgress = { [weak self] progress in
            guard let self else { return }
            self.applyAudioMix(progress: progress)
            if !didNotifyMirrorsForTransitionStart {
                didNotifyMirrorsForTransitionStart = true
                self.notifyMirrors()
            }
        }

        // Ensure both players are actually running during the transition (visual "both clips playing").
        if let rate = playRate {
            currentSource.player.playImmediately(atRate: rate)
        }

        playerView.primarySource = currentSource
        playerView.transitionDuration = duration
        playerView.onTransitionComplete = { [weak self] in
            guard let self = self else { return }

            // Stop the outgoing player's audio
            if let outgoingSlot = self.outgoingSlotDuringTransition {
                let outgoingSource = outgoingSlot == .a ? self.sourceA : self.sourceB
                outgoingSource?.player.pause()
                outgoingSource?.player.replaceCurrentItem(with: nil)
            }

            self.outgoingSlotDuringTransition = nil
            self.playerView.onTransitionProgress = nil
            self.applyAudioMix(progress: nil)
            self.notifyMirrors()
            completion?()
        }
        playerView.startTransition(to: nextSource, type: transitionType, duration: duration)
        applyAudioMix(progress: 0)

        print("🎬 PlayerContentView: Starting \(transitionType.rawValue) transition over \(duration)s")
    }

    /// Stop all playback
    func stop() {
        playerView.cancelTransition()
        playerView.primarySource = nil
        playerView.secondarySource = nil
        playerView.onTransitionProgress = nil
        outgoingSlotDuringTransition = nil

        sourceA?.player.pause()
        sourceA?.player.replaceCurrentItem(with: nil)

        sourceB?.player.pause()
        sourceB?.player.replaceCurrentItem(with: nil)

        activeSlot = .a
    }

    // MARK: - Audio Control

    /// Set volume on both players
    func setVolume(_ volume: Float) {
        baseVolume = volume
        applyAudioMix(progress: playerView.activeTransition != nil ? playerView.transitionProgress : nil)
    }

    /// Set mute on both players
    func setMuted(_ muted: Bool) {
        sourceA?.isMuted = muted
        sourceB?.isMuted = muted
    }

    /// Set audio output device on both players
    func setAudioOutputDevice(_ deviceUID: String?) {
        sourceA?.audioOutputDeviceUniqueID = deviceUID
        sourceB?.audioOutputDeviceUniqueID = deviceUID
    }

    private func applyAudioMix(progress: Float?) {
        let clampedBase = max(0, min(baseVolume, 1))

        // No transition: only the active slot should be audible.
        guard let outgoingSlot = outgoingSlotDuringTransition, let progress else {
            if activeSlot == .a {
                sourceA?.volume = clampedBase
                sourceB?.volume = 0
            } else {
                sourceA?.volume = 0
                sourceB?.volume = clampedBase
            }
            return
        }

        let t = max(0, min(progress, 1))
        let incomingSlot = activeSlot

        let outgoingVolume = clampedBase * (1 - t)
        let incomingVolume = clampedBase * t

        func setVolume(_ volume: Float, for slot: PlayerSlot) {
            switch slot {
            case .a: sourceA?.volume = volume
            case .b: sourceB?.volume = volume
            }
        }

        setVolume(outgoingVolume, for: outgoingSlot)
        setVolume(incomingVolume, for: incomingSlot)
    }

    // MARK: - Content Mode

    /// Set the content display mode
    func setContentMode(_ mode: PlayerView.ContentMode) {
        playerView.contentMode = mode
    }

    // MARK: - Mirror View Support

    /// Registered mirror views that should sync with this content view
    private var mirrorViews: [WeakMirrorRef] = []

    private struct WeakMirrorRef {
        weak var view: PlayerContentMirrorView?
    }

    /// Create a mirror view that displays the same content
    /// The mirror shares the same frame sources, so it shows identical content
    func createMirrorView() -> PlayerContentMirrorView {
        guard let sourceA, let sourceB else {
            return PlayerContentMirrorView(
                playerA: AVPlayer(),
                playerB: AVPlayer(),
                transitionStateProvider: { (.a, nil, nil, 0, 0) }
            )
        }

        let mirror = PlayerContentMirrorView(
            playerA: sourceA.player,
            playerB: sourceB.player,
            transitionStateProvider: { [weak self] in
                guard let self else { return (.a, nil, nil, 0, 0) }
                let outgoingSlot = self.outgoingSlotDuringTransition ?? self.activeSlot
                return (
                    outgoingSlot,
                    self.playerView.activeTransition,
                    self.playerView.transitionStartTime,
                    self.playerView.transitionDuration,
                    self.playerView.transitionSeed
                )
            }
        )
        mirrorViews.append(WeakMirrorRef(view: mirror))
        // Clean up dead refs
        mirrorViews.removeAll { $0.view == nil }
        return mirror
    }

    /// Notify all mirrors to update their transition state
    private func notifyMirrors() {
        mirrorViews.removeAll { $0.view == nil }
        for ref in mirrorViews {
            ref.view?.syncTransitionState()
        }
    }
}

// MARK: - Mirror View

/// A lightweight view that mirrors another PlayerContentView's content
/// Shares the same frame sources but has its own Metal rendering surface
final class PlayerContentMirrorView: NSView {

    private let playerView: PlayerView
    private let sourceA: AVPlayerFrameSource
    private let sourceB: AVPlayerFrameSource
    private let transitionStateProvider: () -> (PlayerContentView.PlayerSlot, TransitionRenderer.TransitionType?, CFTimeInterval?, CFTimeInterval, UInt32)

    init(
        playerA: AVPlayer,
        playerB: AVPlayer,
        transitionStateProvider: @escaping () -> (PlayerContentView.PlayerSlot, TransitionRenderer.TransitionType?, CFTimeInterval?, CFTimeInterval, UInt32)
    ) {
        self.transitionStateProvider = transitionStateProvider
        self.sourceA = AVPlayerFrameSource(player: playerA)
        self.sourceB = AVPlayerFrameSource(player: playerB)
        self.playerView = PlayerView(frame: .zero, device: SharedRenderer.metalDevice)

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // Mirror should follow, not mutate, transition state.
        playerView.autoCompleteTransitions = false

        // Set initial state
        syncTransitionState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Sync transition state from the main content view
    func syncTransitionState() {
        let (activeSlot, transitionType, startTime, duration, seed) = transitionStateProvider()

        let outgoing = activeSlot == .a ? sourceA : sourceB
        let incoming = activeSlot == .a ? sourceB : sourceA

        playerView.primarySource = outgoing

        if let transitionType, let startTime {
            playerView.setTransitionState(
                secondarySource: incoming,
                type: transitionType,
                startTime: startTime,
                duration: duration,
                seed: seed
            )
        } else {
            playerView.cancelTransition()
        }
    }

    /// Set the content display mode
    func setContentMode(_ mode: PlayerView.ContentMode) {
        playerView.contentMode = mode
    }
}
