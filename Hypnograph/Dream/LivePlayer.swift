//
//  LivePlayer.swift
//  Hypnograph
//
//  Live player for live output to an external monitor.
//  Uses Metal-based A/B player with shader transitions between hypnograms.
//

import Foundation
import AVFoundation
import AppKit
import Combine
import HypnoCore

/// Live player for clean output to external monitor with smooth transitions
@MainActor
final class LivePlayer: ObservableObject {

    // MARK: - Configuration

    /// Duration of transitions between hypnograms (seconds)
    var crossfadeDuration: TimeInterval = 1.5

    /// Transition type for shader-based transitions
    var transitionType: TransitionRenderer.TransitionType = .crossfade

    /// Per-player settings (aspect ratio, resolution, generation settings)
    @Published var config: PlayerConfiguration

    /// Global source framing behavior (Fill vs Fit)
    private var sourceFraming: SourceFraming



    // MARK: - State

    @Published private(set) var isVisible: Bool = false
    @Published private(set) var isTransitioning: Bool = false
    @Published private(set) var currentRecipeDescription: String = ""
    @Published private(set) var activeLayerCount: Int = 0
    @Published private(set) var hasContent: Bool = false

    /// The currently active AVPlayer (for preview mirroring)
    var activeAVPlayer: AVPlayer? {
        return contentView?.activeAVPlayer
    }

    /// Create a mirror view for the in-app Live preview
    /// The mirror shares the same frame sources as the main content view,
    /// so both windows show identical content simultaneously
    func createMirrorView() -> PlayerContentMirrorView? {
        ensureContentView()
        return contentView?.createMirrorView()
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
        contentView?.setVolume(currentVolume)
        print("🔊 LivePlayer: Applied volume \(currentVolume)")
    }

    /// Apply audio device to all players (so new player during crossfade gets correct device)
    private func applyAudioDeviceToAllPlayers() {
        contentView?.setAudioOutputDevice(currentAudioDeviceUID)
        print("🔊 LivePlayer: Applied audio device")
    }

    // MARK: - Private

    private var window: LiveWindow?
    private var contentView: PlayerContentView?

    /// Current volume level (0.0 to 1.0)
    private var currentVolume: Float = 1.0

    /// Current audio device UID (nil = system default)
    private var currentAudioDeviceUID: String?

    /// Build task for the pending recipe
    private var pendingBuildTask: Task<Void, Never>?

    /// Render engine for building compositions
    private let renderEngine = RenderEngine()

    /// End observer for notification-based looping
    private var endObserver: Any?

    /// This display's own EffectManager - independent of preview
    let effectManager = EffectManager()

    /// This display's own effects session - for live mode effects
    let effectsSession: EffectsSession

    /// The current clip being displayed (mutable for live effect changes)
    private var currentClip: Hypnogram?
    /// Snapshot of the currently rendered clip used to freeze outgoing transitions.
    private var lastRenderedClip: Hypnogram?

    // MARK: - Init

    init(settings: Settings, effectsSession: EffectsSession) {
        self.config = PlayerConfiguration(from: settings)
        self.sourceFraming = settings.sourceFraming
        self.crossfadeDuration = settings.transitionDuration
        self.transitionType = settings.transitionStyle
        self.effectsSession = effectsSession
        setupEffectManager()
        setupEffectsSession()
    }

    func setSourceFraming(_ newValue: SourceFraming) {
        guard sourceFraming != newValue else { return }
        sourceFraming = newValue

        guard currentClip != nil, contentView != nil else { return }

        pendingBuildTask?.cancel()
        pendingBuildTask = Task {
            await buildAndTransitionMetal()
        }
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
                  sourceIndex < clip.layers.count else { return }
            print("🎬 LivePlayer: sourceEffectChainSetter - setting source[\(sourceIndex)] chain: \(chain.name ?? "unnamed")")
            clip.layers[sourceIndex].effectChain = chain
            self.currentClip = clip
        }

        effectManager.blendModeSetter = { [weak self] sourceIndex, blendMode in
            guard let self = self,
                  var clip = self.currentClip,
                  sourceIndex < clip.layers.count else { return }
            clip.layers[sourceIndex].blendMode = blendMode
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

        let playerContent = PlayerContentView(frame: contentFrame)
        playerContent.autoresizingMask = [.width, .height]
        contentView = playerContent

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
        let playerContent: PlayerContentView
        if let existingContent = contentView {
            playerContent = existingContent
            playerContent.frame = contentFrame
        } else {
            playerContent = PlayerContentView(frame: contentFrame)
            playerContent.autoresizingMask = [.width, .height]
            contentView = playerContent
        }
        win.contentView = playerContent

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

    /// Stop playback and reset all state (also hides window)
    func stop() {
        print("🎬 LivePlayer: Stopping...")

        // Cancel any pending build
        pendingBuildTask?.cancel()
        pendingBuildTask = nil

        // Remove notification observers
        NotificationCenter.default.removeObserver(self)

        // Hide window first
        hide()

        // Clear content
        clearContent()

        print("🎬 LivePlayer: Stopped and reset")
    }

    /// Clear all content without affecting window visibility
    private func clearContent() {
        // Stop and clear players
        contentView?.stop()

        // Reset state
        contentView = nil
        isTransitioning = false
        currentRecipeDescription = ""
        activeLayerCount = 0
        currentClip = nil
        lastRenderedClip = nil
        hasContent = false
    }

    /// Toggle visibility (also serves as reset if stuck)
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Clear content without affecting window visibility
    func reset() {
        print("🎬 LivePlayer: Clearing content...")

        // Cancel any pending build
        pendingBuildTask?.cancel()
        pendingBuildTask = nil

        // Remove notification observers
        NotificationCenter.default.removeObserver(self)

        // Clear content but don't touch window
        clearContent()

        print("🎬 LivePlayer: Content cleared")
    }
    
    /// Send a recipe to the live display
    /// Builds the composition asynchronously, then crossfades to it
    /// - Parameters:
    ///   - clip: The hypnogram clip to display
    ///   - config: Player configuration (aspect ratio, resolution, etc.)
    func send(clip: Hypnogram, config: PlayerConfiguration) {
        // Ensure we have a content view for playback
        ensureContentView()

        guard contentView != nil else {
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

        let sourceCount = clip.layers.count
        activeLayerCount = sourceCount
        currentRecipeDescription = "\(sourceCount) layer\(sourceCount == 1 ? "" : "s")"

        print("🎬 LivePlayer: Building live display with \(sourceCount) layers...")

        pendingBuildTask = Task {
            await buildAndTransitionMetal()
        }
    }

    // MARK: - Private Methods

    /// Build and transition using Metal shader transitions
    private func buildAndTransitionMetal() async {
        guard let clip = currentClip, let metalContent = contentView else { return }
        let outputSize = renderSize(aspectRatio: config.aspectRatio, maxDimension: config.playerResolution.maxDimension)

        if hasContent, let outgoingClip = lastRenderedClip {
            let frozenManager = effectManager.makeTransitionSnapshotManager(
                frozenClip: outgoingClip,
                preserveTemporalState: true
            )
            metalContent.freezeActiveSlotEffects(using: frozenManager)
        }

        // Build composition using LivePlayer's own EffectManager
        let config = RenderEngine.Config(
            outputSize: outputSize,
            frameRate: 30,
            enableEffects: true,
            sourceFraming: sourceFraming
        )

        let result = await renderEngine.makePlayerItem(
            clip: clip,
            config: config,
            effectManager: effectManager
        )

        guard !Task.isCancelled else {
            print("🎬 LivePlayer: Build cancelled")
            return
        }

        switch result {
        case .success(let playerItem):
            isTransitioning = true

            // Configure player item
            playerItem.audioTimePitchAlgorithm = .timeDomain

            // Setup looping for video content
            let isAllStillImages = clip.layers.allSatisfy { $0.mediaClip.file.mediaKind == .image }
            if !isAllStillImages {
                setupLooping(for: playerItem, playRate: clip.playRate)
            }

            // Apply audio settings
            metalContent.setVolume(currentVolume)
            metalContent.setAudioOutputDevice(currentAudioDeviceUID)

            // Determine play rate (nil for still images = don't auto-start)
            let playRate: Float? = isAllStillImages ? nil : clip.playRate

            // Start shader transition with playback
            metalContent.loadAndTransition(
                playerItem: playerItem,
                transitionType: transitionType,
                duration: crossfadeDuration,
                playRate: playRate,
                incomingEffectManager: effectManager
            ) { [weak self] in
                guard let self = self else { return }
                self.isTransitioning = false
                print("✅ LivePlayer: Metal transition complete")
            }

            hasContent = true
            lastRenderedClip = clip
            print("🎬 LivePlayer: Starting Metal \(transitionType.rawValue) transition over \(crossfadeDuration)s")

        case .failure(let error):
            print("🔴 LivePlayer: Build failed - \(error)")
        }
    }

    /// Setup looping for Metal player
    private func setupLooping(for playerItem: AVPlayerItem, playRate: Float) {
        // Remove old end observer
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }

        // Add new observer
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let player = self.contentView?.activeAVPlayer else { return }
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                    guard finished else { return }
                    player.playImmediately(atRate: playRate)
                }
            }
        }
    }
}
