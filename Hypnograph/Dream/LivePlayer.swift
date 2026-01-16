//
//  LivePlayer.swift
//  Hypnograph
//
//  Live player for live output to an external monitor.
//  Uses A/B player crossfading for smooth transitions between hypnograms.
//

import Foundation
import AVFoundation
import AppKit
import Combine
import HypnoCore

/// Live player for clean output to external monitor with smooth crossfades
@MainActor
final class LivePlayer: ObservableObject {

    // MARK: - Configuration

    /// Duration of crossfade between hypnograms (seconds)
    var crossfadeDuration: TimeInterval = 1.5

    /// Per-player settings (aspect ratio, resolution, generation settings)
    @Published var config: PlayerConfiguration



    // MARK: - State

    @Published private(set) var isVisible: Bool = false
    @Published private(set) var isTransitioning: Bool = false
    @Published private(set) var currentRecipeDescription: String = ""
    @Published private(set) var activeSourceCount: Int = 0

    /// Whether we have content loaded and playing
    var hasContent: Bool {
        activeAVPlayer != nil
    }

    /// The currently active AVPlayer (for preview mirroring)
    var activeAVPlayer: AVPlayer? {
        guard let content = contentView else { return nil }
        return activePlayer == .a ? content.playerA.player : content.playerB.player
    }

    // MARK: - Audio

    /// Set volume level for live audio (0.0 = muted, 1.0 = full volume)
    func setVolume(_ volume: Float) {
        currentVolume = volume
        applyVolumeToActivePlayer()
        print("🔊 LivePlayer: Volume = \(volume)")
    }

    /// Set the audio output device for live display
    /// - Parameter deviceUID: The Core Audio device UID, or nil for system default
    func setAudioDevice(_ deviceUID: String?) {
        currentAudioDeviceUID = deviceUID
        applyAudioDeviceToAllPlayers()
        print("🔊 LivePlayer: Audio device = \(deviceUID ?? "System Default")")
    }

    /// Apply volume to the currently active player only (not the fading-out player)
    private func applyVolumeToActivePlayer() {
        guard let content = contentView else {
            print("⚠️ LivePlayer: No contentView for volume")
            return
        }
        let activePlayerView = activePlayer == .a ? content.playerA : content.playerB
        activePlayerView.player?.volume = currentVolume
        print("🔊 LivePlayer: Applied volume \(currentVolume) to player \(activePlayer)")
    }

    /// Apply audio device to all players (so new player during crossfade gets correct device)
    private func applyAudioDeviceToAllPlayers() {
        guard let content = contentView else {
            print("⚠️ LivePlayer: No contentView for audio device")
            return
        }
        content.playerA.player?.audioOutputDeviceUniqueID = currentAudioDeviceUID
        content.playerB.player?.audioOutputDeviceUniqueID = currentAudioDeviceUID
        print("🔊 LivePlayer: Applied device to both players")
    }

    // MARK: - Private

    private var window: LiveWindow?
    private var contentView: LiveContentView?

    /// Current volume level (0.0 to 1.0)
    private var currentVolume: Float = 1.0

    /// Current audio device UID (nil = system default)
    private var currentAudioDeviceUID: String?

    /// Which player is currently active (A or B)
    private var activePlayer: PlayerSlot = .a

    /// Build task for the pending recipe
    private var pendingBuildTask: Task<Void, Never>?

    /// Render engine for building compositions
    private let renderEngine = RenderEngine()

    /// End observers for notification-based looping (matching preview behavior)
    private var endObserverA: Any?
    private var endObserverB: Any?

    /// This display's own EffectManager - independent of preview
    let effectManager = EffectManager()

    /// This display's own effects session - for live mode effects
    let effectsSession: EffectsSession

    /// The current clip being displayed (mutable for live effect changes)
    private var currentClip: HypnogramClip?

    enum PlayerSlot {
        case a, b
        var opposite: PlayerSlot { self == .a ? .b : .a }
    }

    // MARK: - Init

    init(settings: Settings, effectsSession: EffectsSession) {
        self.config = PlayerConfiguration(from: settings)
        self.effectsSession = effectsSession
        setupEffectManager()
        setupEffectsSession()
    }

    private func setupEffectManager() {
        // Wire up the effects session for chain lookups
        effectManager.session = effectsSession

        // Wire up clip provider to return the mutable current clip
        effectManager.clipProvider = { [weak self] in
            self?.currentClip
        }

        // Wire up global effect chain setter
        effectManager.globalEffectChainSetter = { [weak self] chain in
            guard let self = self, var clip = self.currentClip else { return }
            print("🎬 LivePlayer: globalEffectChainSetter - setting chain: \(chain.name ?? "unnamed")")
            clip.effectChain = chain
            self.currentClip = clip
        }

        // Wire up source effect chain setter
        effectManager.sourceEffectChainSetter = { [weak self] (sourceIndex: Int, chain: EffectChain) in
            guard let self = self,
                  var clip = self.currentClip,
                  sourceIndex < clip.sources.count else { return }
            print("🎬 LivePlayer: sourceEffectChainSetter - setting source[\(sourceIndex)] chain: \(chain.name ?? "unnamed")")
            clip.sources[sourceIndex].effectChain = chain
            self.currentClip = clip
        }

        effectManager.blendModeSetter = { [weak self] sourceIndex, blendMode in
            guard let self = self,
                  var clip = self.currentClip,
                  sourceIndex < clip.sources.count else { return }
            clip.sources[sourceIndex].blendMode = blendMode
            self.currentClip = clip
        }
    }

    private func setupEffectsSession() {
        // Step 2 (MVR): template updates should not overwrite CURRENT (recipe) by name.
        // Templates are applied explicitly; editing CURRENT flows through EffectManager recipe mutation APIs.
        effectsSession.onChainUpdated = nil
        effectsSession.onReloaded = nil
    }

    // MARK: - Public API

    /// Ensure content view exists for playback (without showing window)
    private func ensureContentView() {
        guard contentView == nil else { return }

        // Create content view at a reasonable default size
        let contentFrame = NSRect(origin: .zero, size: NSSize(width: 1920, height: 1080))
        let content = LiveContentView(frame: contentFrame)
        content.autoresizingMask = [.width, .height]
        contentView = content

        print("🎬 LivePlayer: Created content view (no window)")
    }

    /// Show the live display window
    /// - Automatically uses windowed mode on primary screen, fullscreen on external monitors
    /// - Parameter screen: Target screen (nil = auto-select external or primary)
    func show(on screen: NSScreen? = nil) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        // Prefer external monitor, fall back to primary
        let screens = NSScreen.screens
        let targetScreen: NSScreen
        let hasExternalMonitor: Bool

        if let screen = screen {
            targetScreen = screen
            hasExternalMonitor = screen != NSScreen.main
        } else if screens.count > 1 {
            // Use external monitor (not the main screen)
            targetScreen = screens.first(where: { $0 != NSScreen.main }) ?? screens.last!
            hasExternalMonitor = true
        } else {
            targetScreen = screens[0]
            hasExternalMonitor = false
        }

        let win: LiveWindow
        let contentFrame: NSRect

        if hasExternalMonitor {
            // External monitor: fullscreen borderless
            let frame = targetScreen.frame
            contentFrame = NSRect(origin: .zero, size: frame.size)

            win = LiveWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: targetScreen
            )
            win.configureForLive()
            win.level = .normal
            win.isOpaque = true
            win.isReleasedWhenClosed = false
            win.collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary]
            win.setFrame(frame, display: true)

            print("🎬 LivePlayer: Fullscreen on \(targetScreen.localizedName)")
        } else {
            // Single monitor: resizable floating window
            let windowSize = NSSize(width: 960, height: 540)  // 16:9
            let windowFrame = NSRect(
                x: targetScreen.frame.maxX - windowSize.width - 40,
                y: targetScreen.frame.maxY - windowSize.height - 80,
                width: windowSize.width,
                height: windowSize.height
            )
            contentFrame = NSRect(origin: .zero, size: windowSize)

            win = LiveWindow(
                contentRect: windowFrame,
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false,
                screen: targetScreen
            )
            win.title = "Live Display"
            win.level = .modalPanel  // Float above fullscreen main window
            win.backgroundColor = .black
            win.isOpaque = true
            win.isReleasedWhenClosed = false
            win.minSize = NSSize(width: 480, height: 270)
            win.contentAspectRatio = NSSize(width: 16, height: 9)
            win.hidesOnDeactivate = false

            print("🎬 LivePlayer: Windowed mode (single monitor)")
        }

        // Reuse existing content view if available, otherwise create new one
        let content: LiveContentView
        if let existingContent = contentView {
            content = existingContent
            content.frame = contentFrame
        } else {
            content = LiveContentView(frame: contentFrame)
            content.autoresizingMask = [.width, .height]
            contentView = content
        }
        win.contentView = content

        // Show without activating (don't steal focus)
        win.orderFront(nil)

        window = win
        isVisible = true
    }
    
    /// Hide the live display window (keeps content/players running for preview)
    func hide() {
        guard window != nil else { return }

        print("🎬 LivePlayer: Hiding window...")

        // Close window but keep content view and players
        if let win = window {
            win.orderOut(nil)
            win.close()
        }

        window = nil
        isVisible = false

        print("🎬 LivePlayer: Window hidden (playback continues)")
    }

    /// Stop playback and reset all state
    func stop() {
        print("🎬 LivePlayer: Stopping...")

        // Cancel any pending build
        pendingBuildTask?.cancel()
        pendingBuildTask = nil

        // Remove notification observers
        NotificationCenter.default.removeObserver(self)

        // Hide window first
        hide()

        // Stop and clear players
        if let content = contentView {
            content.playerA.player?.pause()
            content.playerA.player?.replaceCurrentItem(with: nil)
            content.playerA.player = nil

            content.playerB.player?.pause()
            content.playerB.player?.replaceCurrentItem(with: nil)
            content.playerB.player = nil
        }

        // Reset state
        contentView = nil
        isTransitioning = false
        activePlayer = .a
        currentRecipeDescription = ""
        activeSourceCount = 0
        currentClip = nil

        print("🎬 LivePlayer: Stopped and reset")
    }

    /// Toggle visibility (also serves as reset if stuck)
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Force reset - stops everything and optionally reopens
    func reset() {
        print("🎬 LivePlayer: Force reset")
        let wasVisible = isVisible
        stop()
        if wasVisible {
            // Small delay to ensure cleanup completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.show()
            }
        }
    }
    
    /// Send a recipe to the live display
    /// Builds the composition asynchronously, then crossfades to it
    /// - Parameters:
    ///   - clip: The hypnogram clip to display
    ///   - config: Player configuration (aspect ratio, resolution, etc.)
    func send(clip: HypnogramClip, config: PlayerConfiguration) {
        // Ensure we have a content view for playback
        ensureContentView()

        guard let content = contentView else {
            print("⚠️ LivePlayer: No content view, ignoring send")
            return
        }

        // Only show window if there's an external monitor
        if !isVisible && NSScreen.screens.count > 1 {
            show()
        }

        // Cancel any pending build
        pendingBuildTask?.cancel()

        // Update config from the recipe being sent
        self.config = config

        // Store the clip for live effect modifications
        self.currentClip = clip

        let sourceCount = clip.sources.count
        activeSourceCount = sourceCount
        currentRecipeDescription = "\(sourceCount) layer\(sourceCount == 1 ? "" : "s")"

        print("🎬 LivePlayer: Building live display with \(sourceCount) layers...")

        pendingBuildTask = Task {
            await buildAndTransition(content: content)
        }
    }

    // MARK: - Private Methods

    private func buildAndTransition(content: LiveContentView) async {
        guard let clip = currentClip else { return }
        let outputSize = renderSize(aspectRatio: config.aspectRatio, maxDimension: config.playerResolution.maxDimension)

        // Build composition using LivePlayer's own EffectManager
        // This makes effects completely independent of the main preview
        let config = RenderEngine.Config(
            outputSize: outputSize,
            frameRate: 30,
            enableEffects: true
        )

        let result = await renderEngine.makePlayerItem(
            clip: clip,
            config: config,
            effectManager: effectManager  // Use LivePlayer's own EffectManager
        )

        guard !Task.isCancelled else {
            print("🎬 LivePlayer: Build cancelled")
            return
        }

        switch result {
        case .success(let playerItem):
            await performCrossfade(
                to: playerItem,
                content: content
            )

        case .failure(let error):
            print("🔴 LivePlayer: Build failed - \(error)")
        }
    }

    private func performCrossfade(
        to playerItem: AVPlayerItem,
        content: LiveContentView
    ) async {
        isTransitioning = true

        // Determine which player to use next
        let nextSlot = activePlayer.opposite
        let nextPlayerView = nextSlot == .a ? content.playerA : content.playerB
        let currentPlayerView = activePlayer == .a ? content.playerA : content.playerB

        playerItem.audioTimePitchAlgorithm = .timeDomain

        // Setup player - simple AVPlayer like preview
        let player: AVPlayer
        if let existing = nextPlayerView.player {
            existing.replaceCurrentItem(with: playerItem)
            player = existing
        } else {
            player = AVPlayer(playerItem: playerItem)
            nextPlayerView.player = player
        }

        // Setup notification-based looping (same as preview)
        let isAllStillImages = currentClip?.sources.allSatisfy { $0.clip.file.mediaKind == .image } ?? false
        if !isAllStillImages {
            setupLooping(for: player, item: playerItem, slot: nextSlot)
        }

        // Mute old player immediately before starting new one
        currentPlayerView.player?.volume = 0.0

        // Start new player with correct volume and audio device
        player.volume = currentVolume
        player.audioOutputDeviceUniqueID = currentAudioDeviceUID
        nextPlayerView.alphaValue = 0
        if isAllStillImages {
            await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.pause()
        } else {
            player.playImmediately(atRate: currentClip?.playRate ?? 0.8)
        }

        // Visual crossfade
        let duration = crossfadeDuration

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            nextPlayerView.animator().alphaValue = 1.0
            currentPlayerView.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            guard let self = self else { return }

            // Stop old player completely and release composition
            currentPlayerView.player?.pause()
            currentPlayerView.player?.replaceCurrentItem(with: nil)

            // Update active slot
            self.activePlayer = nextSlot
            self.isTransitioning = false

            print("✅ LivePlayer: Crossfade complete")
        }

        print("🎬 LivePlayer: Crossfading over \(duration)s")
    }

    /// Setup notification-based looping for a player (same approach as preview)
    private func setupLooping(for player: AVPlayer, item: AVPlayerItem, slot: PlayerSlot) {
        // Remove old observer for this slot
        if slot == .a, let observer = endObserverA {
            NotificationCenter.default.removeObserver(observer)
            endObserverA = nil
        } else if slot == .b, let observer = endObserverB {
            NotificationCenter.default.removeObserver(observer)
            endObserverB = nil
        }

        // Add new observer
        let playRate = currentClip?.playRate ?? 0.8
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.playImmediately(atRate: playRate)
        }

        // Store observer reference
        if slot == .a {
            endObserverA = observer
        } else {
            endObserverB = observer
        }
    }
}
