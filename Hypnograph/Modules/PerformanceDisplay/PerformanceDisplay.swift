//
//  PerformanceDisplay.swift
//  Hypnograph
//
//  A self-contained module for clean video output to an external monitor.
//  Uses A/B player crossfading for smooth transitions between hypnograms.
//

import Foundation
import AVFoundation
import AppKit
import Combine

/// Performance display for clean output to external monitor with smooth crossfades
@MainActor
final class PerformanceDisplay: ObservableObject {

    // MARK: - Configuration

    /// Duration of crossfade between hypnograms (seconds)
    var crossfadeDuration: TimeInterval = 1.5

    /// Aspect ratio for rendering
    var aspectRatio: AspectRatio = .ratio16x9

    /// Output resolution
    var outputResolution: OutputResolution = .p1080



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

    /// Set mute state on both players (A and B)
    /// Uses volume control for more reliable audio switching
    func setMuted(_ muted: Bool) {
        isMuted = muted
        let targetVolume: Float = muted ? 0.0 : currentVolume
        print("🔊 PerformanceDisplay: setMuted(\(muted)) → volume \(targetVolume)")

        // Apply immediately if on main thread, otherwise dispatch
        if Thread.isMainThread {
            applyVolume(targetVolume)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.applyVolume(self.isMuted ? 0.0 : self.currentVolume)
            }
        }
    }

    private func applyVolume(_ volume: Float) {
        guard let content = contentView else {
            print("🔊 PerformanceDisplay: No content view, volume will apply on player creation")
            return
        }
        if let playerA = content.playerA.player {
            playerA.volume = volume
            print("🔊 PerformanceDisplay: Player A volume = \(volume)")
        }
        if let playerB = content.playerB.player {
            playerB.volume = volume
            print("🔊 PerformanceDisplay: Player B volume = \(volume)")
        }
    }

    // MARK: - Audio Routing

    /// Audio router for routing to specific device
    var audioRouter: AudioRouter?

    /// Set the audio router for device-specific routing
    /// Also applies the audio mix to the currently playing content
    func setAudioRouter(_ router: AudioRouter?) {
        self.audioRouter = router

        // Apply audio routing to current player item if content is already playing
        if let router = router, router.isActive {
            applyAudioRoutingToCurrentPlayer()
        }
    }

    /// Apply audio routing to the currently active player
    private func applyAudioRoutingToCurrentPlayer() {
        guard let router = audioRouter, router.isActive else { return }
        guard let content = contentView else { return }

        let currentPlayerView = activePlayer == .a ? content.playerA : content.playerB
        guard let player = currentPlayerView.player,
              let currentItem = player.currentItem else { return }

        // Use async version since the item is already playing and tracks may need loading
        Task {
            if let audioMix = await router.createAudioMixAsync(for: currentItem) {
                await MainActor.run {
                    currentItem.audioMix = audioMix
                    print("🔊 PerformanceDisplay: Applied audio routing to current player")
                }
            }
        }
    }

    /// Set volume level for performance audio
    func setVolume(_ volume: Float) {
        currentVolume = volume
        if !isMuted {
            applyVolume(volume)
        }
    }

    // MARK: - Private

    private var window: PerformanceWindow?
    private var contentView: PerformanceContentView?

    /// Current mute state (applied to new players)
    /// Defaults to true since default audioSource is .preview (performance muted)
    private var isMuted: Bool = true

    /// Current volume level (0.0 to 1.0)
    private var currentVolume: Float = 1.0

    /// Which player is currently active (A or B)
    private var activePlayer: PlayerSlot = .a

    /// Build task for the pending recipe
    private var pendingBuildTask: Task<Void, Never>?

    /// Render engine for building compositions
    private let renderEngine = RenderEngine()

    /// This display's own EffectManager - independent of preview
    let effectManager = EffectManager()

    /// The current recipe being displayed (mutable for live effect changes)
    private var currentRecipe: HypnogramRecipe?

    /// Current mode (montage or sequence)
    private var currentMode: DreamMode = .montage

    /// Clip start times for sequence mode seeking
    private var clipStartTimes: [CMTime] = []

    /// Still images by source index (for sequence mode with still images)
    private var stillImagesBySourceIndex: [Int: CIImage] = [:]

    enum PlayerSlot {
        case a, b
        var opposite: PlayerSlot { self == .a ? .b : .a }
    }

    // MARK: - Init

    init() {
        setupEffectManager()
    }

    private func setupEffectManager() {
        // Wire up recipe provider to return the mutable current recipe
        effectManager.recipeProvider = { [weak self] in
            self?.currentRecipe
        }

        // Wire up global effect chain setter
        effectManager.globalEffectChainSetter = { [weak self] chain in
            guard let self = self, var recipe = self.currentRecipe else { return }
            print("🎬 PerformanceDisplay: globalEffectChainSetter - setting chain: \(chain.name ?? "unnamed")")
            recipe.effectChain = chain
            self.currentRecipe = recipe
        }

        // Wire up source effect chain setter
        effectManager.sourceEffectChainSetter = { [weak self] (sourceIndex: Int, chain: EffectChain) in
            guard let self = self,
                  var recipe = self.currentRecipe,
                  sourceIndex < recipe.sources.count else { return }
            print("🎬 PerformanceDisplay: sourceEffectChainSetter - setting source[\(sourceIndex)] chain: \(chain.name ?? "unnamed")")
            recipe.sources[sourceIndex].effectChain = chain
            self.currentRecipe = recipe
        }
    }
    
    // MARK: - Public API

    /// Ensure content view exists for playback (without showing window)
    private func ensureContentView() {
        guard contentView == nil else { return }

        // Create content view at a reasonable default size
        let contentFrame = NSRect(origin: .zero, size: NSSize(width: 1920, height: 1080))
        let content = PerformanceContentView(frame: contentFrame)
        content.autoresizingMask = [.width, .height]
        contentView = content

        print("🎬 PerformanceDisplay: Created content view (no window)")
    }

    /// Show the performance display window
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

        let win: PerformanceWindow
        let contentFrame: NSRect

        if hasExternalMonitor {
            // External monitor: fullscreen borderless
            let frame = targetScreen.frame
            contentFrame = NSRect(origin: .zero, size: frame.size)

            win = PerformanceWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: targetScreen
            )
            win.configureForPerformance()
            win.level = .normal
            win.isOpaque = true
            win.isReleasedWhenClosed = false
            win.collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary]
            win.setFrame(frame, display: true)

            print("🎬 PerformanceDisplay: Fullscreen on \(targetScreen.localizedName)")
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

            win = PerformanceWindow(
                contentRect: windowFrame,
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false,
                screen: targetScreen
            )
            win.title = "Performance Display"
            win.level = .modalPanel  // Float above fullscreen main window
            win.backgroundColor = .black
            win.isOpaque = true
            win.isReleasedWhenClosed = false
            win.minSize = NSSize(width: 480, height: 270)
            win.contentAspectRatio = NSSize(width: 16, height: 9)
            win.hidesOnDeactivate = false

            print("🎬 PerformanceDisplay: Windowed mode (single monitor)")
        }

        // Reuse existing content view if available, otherwise create new one
        let content: PerformanceContentView
        if let existingContent = contentView {
            content = existingContent
            content.frame = contentFrame
        } else {
            content = PerformanceContentView(frame: contentFrame)
            content.autoresizingMask = [.width, .height]
            contentView = content
        }
        win.contentView = content

        // Show without activating (don't steal focus)
        win.orderFront(nil)

        window = win
        isVisible = true
    }
    
    /// Hide the performance display window (keeps content/players running for preview)
    func hide() {
        guard window != nil else { return }

        print("🎬 PerformanceDisplay: Hiding window...")

        // Close window but keep content view and players
        if let win = window {
            win.orderOut(nil)
            win.close()
        }

        window = nil
        isVisible = false

        print("🎬 PerformanceDisplay: Window hidden (playback continues)")
    }

    /// Stop playback and reset all state
    func stop() {
        print("🎬 PerformanceDisplay: Stopping...")

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
        currentRecipe = nil

        print("🎬 PerformanceDisplay: Stopped and reset")
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
        print("🎬 PerformanceDisplay: Force reset")
        let wasVisible = isVisible
        stop()
        if wasVisible {
            // Small delay to ensure cleanup completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.show()
            }
        }
    }
    
    /// Send a recipe to the performance display
    /// Builds the composition asynchronously, then crossfades to it
    /// - Parameters:
    ///   - recipe: The hypnogram recipe to display
    ///   - aspectRatio: Aspect ratio for rendering
    ///   - resolution: Output resolution
    ///   - mode: Dream mode (montage or sequence)
    func send(recipe: HypnogramRecipe, aspectRatio: AspectRatio, resolution: OutputResolution, mode: DreamMode = .montage) {
        // Ensure we have a content view for playback
        ensureContentView()

        guard let content = contentView else {
            print("⚠️ PerformanceDisplay: No content view, ignoring send")
            return
        }

        // Only show window if there's an external monitor
        if !isVisible && NSScreen.screens.count > 1 {
            show()
        }

        // Cancel any pending build
        pendingBuildTask?.cancel()

        self.aspectRatio = aspectRatio
        self.outputResolution = resolution

        // Store the recipe for live effect modifications
        self.currentRecipe = recipe

        let sourceCount = recipe.sources.count
        activeSourceCount = sourceCount
        let modeLabel = mode == .sequence ? "sequence" : "montage"
        currentRecipeDescription = "\(sourceCount) source\(sourceCount == 1 ? "" : "s") (\(modeLabel))"

        print("🎬 PerformanceDisplay: Building \(modeLabel) with \(sourceCount) sources...")

        // Store the mode for sequence seeking
        self.currentMode = mode

        pendingBuildTask = Task {
            await buildAndTransition(content: content, mode: mode)
        }
    }

    // MARK: - Sequence Mode Sync

    /// Seek to a specific source index in sequence mode
    /// Call this when the main preview navigates to a different source
    /// - Parameter index: The source index to seek to
    func seekToSource(index: Int) {
        // Only works in sequence mode with valid clip start times
        guard currentMode == .sequence,
              index >= 0,
              index < clipStartTimes.count,
              let player = activeAVPlayer else {
            return
        }

        let targetTime = clipStartTimes[index]
        let rate = currentRecipe?.playRate ?? 0.8
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            // Ensure playback continues after seek at recipe's play rate
            player.playImmediately(atRate: rate)
        }
    }

    // MARK: - Private Methods

    private func buildAndTransition(content: PerformanceContentView, mode: DreamMode) async {
        guard let recipe = currentRecipe else { return }
        let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: outputResolution.maxDimension)

        // Build composition using PerformanceDisplay's own EffectManager
        // This makes effects completely independent of the main preview
        let strategy: CompositionBuilder.TimelineStrategy
        switch mode {
        case .montage:
            strategy = .montage(targetDuration: recipe.targetDuration)
        case .sequence:
            strategy = .sequence
        }
        let config = RenderEngine.Config(
            outputSize: outputSize,
            frameRate: 30,
            enableGlobalEffects: true
        )

        let result = await renderEngine.makePlayerItem(
            recipe: recipe,
            strategy: strategy,
            config: config,
            effectManager: effectManager  // Use PerformanceDisplay's own EffectManager
        )

        guard !Task.isCancelled else {
            print("🎬 PerformanceDisplay: Build cancelled")
            return
        }

        switch result {
        case .success(let buildResult):
            await performCrossfade(
                to: buildResult,
                content: content
            )

        case .failure(let error):
            print("🔴 PerformanceDisplay: Build failed - \(error)")
        }
    }

    private func performCrossfade(
        to buildResult: RenderEngine.PlayerItemResult,
        content: PerformanceContentView
    ) async {
        isTransitioning = true

        // Store clip start times for sequence mode seeking
        self.clipStartTimes = buildResult.clipStartTimes
        self.stillImagesBySourceIndex = buildResult.stillImagesBySourceIndex

        // Determine which player to use next
        let nextSlot = activePlayer.opposite
        let nextPlayerView = nextSlot == .a ? content.playerA : content.playerB
        let currentPlayerView = activePlayer == .a ? content.playerA : content.playerB

        // Apply audio routing if router is active
        if let router = audioRouter, router.isActive {
            if let audioMix = router.createAudioMix(for: buildResult.playerItem) {
                buildResult.playerItem.audioMix = audioMix
            }
        }

        // Setup new player
        let player: AVPlayer
        if let existing = nextPlayerView.player {
            existing.replaceCurrentItem(with: buildResult.playerItem)
            player = existing
        } else {
            player = AVPlayer(playerItem: buildResult.playerItem)
            nextPlayerView.player = player
        }

        // Configure looping and volume (use volume for reliable audio control)
        setupLooping(for: player, item: buildResult.playerItem)
        player.volume = isMuted ? 0.0 : 1.0
        print("🔊 PerformanceDisplay: New player volume = \(player.volume)")

        // Start playback on new player (hidden) at recipe's play rate
        nextPlayerView.alphaValue = 0
        player.playImmediately(atRate: currentRecipe?.playRate ?? 0.8)

        // Give it a moment to start rendering
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Crossfade animation
        let duration = crossfadeDuration

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            nextPlayerView.animator().alphaValue = 1.0
            currentPlayerView.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            guard let self = self else { return }

            // Stop old player
            currentPlayerView.player?.pause()

            // Update active slot
            self.activePlayer = nextSlot
            self.isTransitioning = false

            // Ensure volume is correct on now-active player
            let targetVolume: Float = self.isMuted ? 0.0 : 1.0
            self.activeAVPlayer?.volume = targetVolume
            print("🔊 PerformanceDisplay: After crossfade, active player volume = \(targetVolume)")

            print("✅ PerformanceDisplay: Crossfade complete")
        }

        print("🎬 PerformanceDisplay: Crossfading over \(duration)s")
    }

    private func setupLooping(for player: AVPlayer, item: AVPlayerItem) {
        // Remove any existing observer
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        // Capture playRate from current recipe
        let playRate = currentRecipe?.playRate ?? 0.8

        // Add loop observer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.playImmediately(atRate: playRate)
        }
    }
}

