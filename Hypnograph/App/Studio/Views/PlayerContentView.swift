//
//  PlayerContentView.swift
//  Hypnograph
//
//  Content view with A/B player sources for shader-based transitions.
//  Used by both in-app and Live displays.
//

import AppKit
import AVFoundation
import HypnoCore

/// Content view with A/B player sources for shader-based transitions.
/// Used by both in-app and Live displays with a single unified Metal surface.
final class PlayerContentView: NSView {

    // MARK: - Properties

    /// The Metal view for display
    let playerView: HypnoCore.RendererView

    /// Frame source A (for A/B transitions)
    private var sourceA: AVPlayerFrameSource?

    /// Frame source B (for A/B transitions)
    private var sourceB: AVPlayerFrameSource?

    /// Which source is currently active
    private var activeSlot: PlayerSlot = .a

    /// Strong references for per-slot effect managers used by compositor instructions.
    /// Needed because RenderInstruction stores a weak manager reference.
    private var effectManagerA: EffectManager?
    private var effectManagerB: EffectManager?

    /// Target output volume for this content view (0.0 to 1.0)
    private var baseVolume: Float = 1.0

    /// Slot that is fading out during an active transition.
    /// During transitions, `activeSlot` is updated immediately to the incoming slot.
    private var outgoingSlotDuringTransition: PlayerSlot?

    /// Monotonically increasing token used to ignore stale transition callbacks.
    /// This prevents an older transition completion from pausing/replacing items
    /// during a newer transition (e.g., when transitions are triggered rapidly).
    private var transitionToken: UInt64 = 0

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

    private func source(for slot: PlayerSlot) -> AVPlayerFrameSource? {
        slot == .a ? sourceA : sourceB
    }

    private func setEffectManager(_ manager: EffectManager?, for slot: PlayerSlot) {
        switch slot {
        case .a: effectManagerA = manager
        case .b: effectManagerB = manager
        }
    }

    private func clearSlot(_ slot: PlayerSlot) {
        let slotSource = source(for: slot)
        slotSource?.player.pause()
        slotSource?.player.replaceCurrentItem(with: nil)
        setEffectManager(nil, for: slot)
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        // Create Metal view
        playerView = HypnoCore.RendererView(frame: frameRect, device: SharedRenderer.metalDevice)

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

        // Avoid the default "pause at end" behavior which can cause a visible/audio
        // hitch when looping near clip boundaries (especially during transitions).
        playerA.actionAtItemEnd = .none
        playerB.actionAtItemEnd = .none

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
        incomingEffectManager: EffectManager? = nil,
        onIncomingFramePresented: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        transitionToken &+= 1
        let token = transitionToken

        let outgoingSlot = activeSlot
        let nextSlot = outgoingSlot.opposite
        let nextSource = source(for: nextSlot)

        guard let nextSource = nextSource else {
            print("⚠️ PlayerContentView: Missing frame source")
            return
        }

        // Configure the next source with the player item
        if let incomingEffectManager {
            applyEffectManager(incomingEffectManager, to: playerItem)
        }
        setEffectManager(incomingEffectManager, for: nextSlot)
        nextSource.configure(with: playerItem)

        // Start playback if rate is specified
        if let rate = playRate {
            nextSource.player.playImmediately(atRate: rate)
        }

        // Handle instant cut (no transition)
        if transitionType == .none {
            outgoingSlotDuringTransition = outgoingSlot
            activeSlot = nextSlot
            playerView.onNextFramePresented = nil
            playerView.onFirstTransitionFramePresented = onIncomingFramePresented
            playerView.onTransitionProgress = { [weak self] progress in
                self?.applyAudioMix(progress: progress)
            }
            playerView.onTransitionComplete = { [weak self] in
                guard let self else { return }
                self.clearSlot(outgoingSlot)
                self.outgoingSlotDuringTransition = nil
                self.playerView.onTransitionProgress = nil
                self.applyAudioMix(progress: nil)
                self.notifyMirrors()
            }
            // Use an effectively-instant crossfade internally so the renderer keeps the
            // outgoing source visible until the incoming source has actually produced a frame.
            playerView.startTransition(to: nextSource, type: .crossfade, duration: 0.0001)
            applyAudioMix(progress: 0)
            notifyMirrors()
            print("🎬 PlayerContentView: Instant cut (no transition)")
            completion?()
            return
        }

        // Start the shader transition
        guard let currentSource = source(for: outgoingSlot) else {
            // No current source - just set as primary
            playerView.primarySource = nextSource
            activeSlot = nextSlot
            playerView.onNextFramePresented = onIncomingFramePresented
            playerView.onFirstTransitionFramePresented = nil
            applyAudioMix(progress: nil)
            completion?()
            return
        }

        outgoingSlotDuringTransition = outgoingSlot
        activeSlot = nextSlot
        playerView.onNextFramePresented = nil
        playerView.onFirstTransitionFramePresented = onIncomingFramePresented

        // Audio: fade out outgoing while fading in incoming.
        var didNotifyMirrorsForTransitionStart = false
        playerView.onTransitionProgress = { [weak self] progress in
            guard let self else { return }
            guard self.transitionToken == token else { return }
            self.applyAudioMix(progress: progress)
            if !didNotifyMirrorsForTransitionStart {
                didNotifyMirrorsForTransitionStart = true
                self.notifyMirrors()
            }
        }

        // Ensure both players are actually running during the transition (visual "both clips playing").
        if let rate = playRate {
            // Don't force-loop the outgoing clip if it's at end; freezing on the last
            // frame is preferable to visibly restarting mid-transition.
            currentSource.player.playImmediately(atRate: rate)
        }

        playerView.primarySource = currentSource
        playerView.transitionDuration = duration
        playerView.onTransitionComplete = { [weak self] in
            guard let self = self else { return }
            guard self.transitionToken == token else { return }

            // Stop the outgoing player's audio
            if let outgoingSlot = self.outgoingSlotDuringTransition {
                self.clearSlot(outgoingSlot)
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

    /// Rebind the currently visible slot to a frozen effect manager.
    /// Used before transitioning to a new clip so the outgoing clip keeps its own
    /// effect context while the incoming clip renders with the new context.
    func freezeActiveSlotEffects(using manager: EffectManager) {
        setEffectManager(manager, for: activeSlot)
        applyEffectManager(manager, to: activeAVPlayer?.currentItem)
    }

    /// Run a one-shot callback after the next non-empty frame is presented.
    func notifyOnNextPresentedFrame(_ callback: (() -> Void)?) {
        playerView.onNextFramePresented = callback
    }

    private func applyEffectManager(_ manager: EffectManager, to playerItem: AVPlayerItem?) {
        guard let playerItem else { return }
        _ = RenderEngine.rebindEffectManager(manager, on: playerItem)
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
        effectManagerA = nil
        effectManagerB = nil
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
    func setContentMode(_ mode: HypnoCore.RendererView.ContentMode) {
        playerView.contentMode = mode
    }

    /// Force the active frame source to refresh at a specific time.
    /// Uses a non-clearing seek so paused effect edits repaint without transient black frames.
    func refreshActiveFrame(at time: CMTime) {
        if let activeFrameSource {
            activeFrameSource.refresh(at: time)
        } else {
            activeAVPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    /// Set a content-aware focus point (e.g. human head) used to offset aspect-fill framing.
    /// Pass `nil` to clear and return to centered framing.
    func setContentFocus(_ focus: HypnoCore.RendererView.ContentFocus?) {
        playerView.contentFocus = focus
        mirrorViews.removeAll { $0.view == nil }
        for ref in mirrorViews {
            ref.view?.setContentFocus(focus)
        }
    }

    // MARK: - Mirror View Support

    /// Registered mirror views that should sync with this content view
    private var mirrorViews: [WeakMirrorRef] = []

    private struct WeakMirrorRef {
        weak var view: PlayerContentMirrorView?
    }

    /// Create a mirror view that displays the same content
    /// The mirror shares the same `FrameSource` instances, so it shows identical content
    /// without attaching a second AVPlayerItemVideoOutput to the same AVPlayer.
    func createMirrorView() -> PlayerContentMirrorView {
        guard let sourceA, let sourceB else {
            return PlayerContentMirrorView(
                sourceA: AVPlayerFrameSource(player: AVPlayer()),
                sourceB: AVPlayerFrameSource(player: AVPlayer()),
                transitionStateProvider: { (.a, nil, nil, 0, 0) }
            )
        }

        let mirror = PlayerContentMirrorView(
            sourceA: sourceA,
            sourceB: sourceB,
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

    private let playerView: HypnoCore.RendererView
    private let sourceA: FrameSource
    private let sourceB: FrameSource
    private let transitionStateProvider: () -> (PlayerContentView.PlayerSlot, TransitionRenderer.TransitionType?, CFTimeInterval?, CFTimeInterval, UInt32)

    init(
        sourceA: FrameSource,
        sourceB: FrameSource,
        transitionStateProvider: @escaping () -> (PlayerContentView.PlayerSlot, TransitionRenderer.TransitionType?, CFTimeInterval?, CFTimeInterval, UInt32)
    ) {
        self.transitionStateProvider = transitionStateProvider
        self.sourceA = sourceA
        self.sourceB = sourceB
        self.playerView = HypnoCore.RendererView(frame: .zero, device: SharedRenderer.metalDevice)

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
    func setContentMode(_ mode: HypnoCore.RendererView.ContentMode) {
        playerView.contentMode = mode
    }

    func setContentFocus(_ focus: HypnoCore.RendererView.ContentFocus?) {
        playerView.contentFocus = focus
    }
}
