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
        let nextSlot = activeSlot.opposite
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
            // Stop the outgoing player's audio
            let outgoingSource = activeSlot == .a ? sourceA : sourceB
            outgoingSource?.player.pause()
            outgoingSource?.player.replaceCurrentItem(with: nil)

            playerView.cancelTransition()
            playerView.primarySource = nextSource
            activeSlot = nextSlot
            notifyMirrors()
            print("🎬 PlayerContentView: Instant cut (no transition)")
            completion?()
            return
        }

        // Start the shader transition
        guard let currentSource = activeSlot == .a ? sourceA : sourceB else {
            // No current source - just set as primary
            playerView.primarySource = nextSource
            activeSlot = nextSlot
            completion?()
            return
        }

        playerView.primarySource = currentSource
        playerView.transitionDuration = duration
        playerView.onTransitionComplete = { [weak self] in
            guard let self = self else { return }

            // Stop the outgoing player's audio
            let outgoingSource = self.activeSlot == .a ? self.sourceA : self.sourceB
            outgoingSource?.player.pause()
            outgoingSource?.player.replaceCurrentItem(with: nil)

            self.activeSlot = nextSlot
            self.notifyMirrors()
            completion?()
        }
        playerView.startTransition(to: nextSource, type: transitionType, duration: duration)
        notifyMirrors()

        print("🎬 PlayerContentView: Starting \(transitionType.rawValue) transition over \(duration)s")
    }

    /// Stop all playback
    func stop() {
        playerView.cancelTransition()
        playerView.primarySource = nil
        playerView.secondarySource = nil

        sourceA?.player.pause()
        sourceA?.player.replaceCurrentItem(with: nil)

        sourceB?.player.pause()
        sourceB?.player.replaceCurrentItem(with: nil)

        activeSlot = .a
    }

    // MARK: - Audio Control

    /// Set volume on both players
    func setVolume(_ volume: Float) {
        sourceA?.volume = volume
        sourceB?.volume = volume
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
        let mirror = PlayerContentMirrorView(
            sourceA: sourceA,
            sourceB: sourceB,
            activeSlotProvider: { [weak self] in self?.activeSlot ?? .a },
            transitionStateProvider: { [weak self] in
                guard let self = self else { return (nil, nil, 0, 0) }
                return (
                    self.playerView.primarySource,
                    self.playerView.secondarySource,
                    self.playerView.transitionProgress,
                    self.playerView.transitionDuration
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
    private weak var sourceA: AVPlayerFrameSource?
    private weak var sourceB: AVPlayerFrameSource?
    private let activeSlotProvider: () -> PlayerContentView.PlayerSlot
    private let transitionStateProvider: () -> (FrameSource?, FrameSource?, Float, CFTimeInterval)

    init(
        sourceA: AVPlayerFrameSource?,
        sourceB: AVPlayerFrameSource?,
        activeSlotProvider: @escaping () -> PlayerContentView.PlayerSlot,
        transitionStateProvider: @escaping () -> (FrameSource?, FrameSource?, Float, CFTimeInterval)
    ) {
        self.sourceA = sourceA
        self.sourceB = sourceB
        self.activeSlotProvider = activeSlotProvider
        self.transitionStateProvider = transitionStateProvider
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

        // Set initial source
        updateSource()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Update the primary source based on the active slot
    func updateSource() {
        let activeSlot = activeSlotProvider()
        playerView.primarySource = activeSlot == .a ? sourceA : sourceB
    }

    /// Sync transition state from the main content view
    func syncTransitionState() {
        let (primary, secondary, progress, duration) = transitionStateProvider()

        if secondary != nil && progress < 1.0 {
            // Transition is in progress - use the incoming source as primary
            // since we're not rendering the transition blend ourselves
            playerView.primarySource = secondary
            playerView.secondarySource = nil
        } else {
            // No transition or transition complete - use primary
            playerView.primarySource = primary
            playerView.secondarySource = nil
        }
        playerView.transitionDuration = duration
    }

    /// Set the content display mode
    func setContentMode(_ mode: PlayerView.ContentMode) {
        playerView.contentMode = mode
    }
}
