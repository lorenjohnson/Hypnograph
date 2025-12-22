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
    
    // MARK: - Private

    private var window: PerformanceWindow?
    private var contentView: PerformanceContentView?

    /// Which player is currently active (A or B)
    private var activePlayer: PlayerSlot = .a

    /// Build task for the pending recipe
    private var pendingBuildTask: Task<Void, Never>?

    /// Render engine for building compositions
    private let renderEngine = RenderEngine()

    enum PlayerSlot {
        case a, b
        var opposite: PlayerSlot { self == .a ? .b : .a }
    }
    
    // MARK: - Public API

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

        let content = PerformanceContentView(frame: contentFrame)
        content.autoresizingMask = [.width, .height]
        win.contentView = content

        // Show without activating (don't steal focus)
        win.orderFront(nil)

        window = win
        contentView = content
        isVisible = true
    }
    
    /// Hide the performance display window and reset all state
    func hide() {
        print("🎬 PerformanceDisplay: Closing...")

        // Cancel any pending build
        pendingBuildTask?.cancel()
        pendingBuildTask = nil

        // Remove notification observers
        NotificationCenter.default.removeObserver(self)

        // Stop and clear players
        if let content = contentView {
            content.playerA.player?.pause()
            content.playerA.player?.replaceCurrentItem(with: nil)
            content.playerA.player = nil

            content.playerB.player?.pause()
            content.playerB.player?.replaceCurrentItem(with: nil)
            content.playerB.player = nil
        }

        // Close window
        if let win = window {
            win.orderOut(nil)
            win.close()
        }

        // Reset state
        window = nil
        contentView = nil
        isVisible = false
        isTransitioning = false
        activePlayer = .a
        currentRecipeDescription = ""

        print("🎬 PerformanceDisplay: Closed and reset")
    }

    /// Toggle visibility (also serves as reset if stuck)
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Force reset - closes and immediately reopens
    func reset() {
        print("🎬 PerformanceDisplay: Force reset")
        let wasVisible = isVisible
        hide()
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
        guard isVisible, let content = contentView else {
            print("⚠️ PerformanceDisplay: Not visible, ignoring send")
            return
        }

        // Cancel any pending build
        pendingBuildTask?.cancel()

        self.aspectRatio = aspectRatio
        self.outputResolution = resolution

        let sourceCount = recipe.sources.count
        let modeLabel = mode == .sequence ? "sequence" : "montage"
        currentRecipeDescription = "\(sourceCount) source\(sourceCount == 1 ? "" : "s") (\(modeLabel))"

        print("🎬 PerformanceDisplay: Building \(modeLabel) with \(sourceCount) sources...")

        pendingBuildTask = Task {
            await buildAndTransition(recipe: recipe, content: content, mode: mode)
        }
    }

    // MARK: - Private Methods

    private func buildAndTransition(recipe: HypnogramRecipe, content: PerformanceContentView, mode: DreamMode) async {
        let outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: outputResolution.maxDimension)

        // Build the composition with isolatedPlayback: true
        // This bakes the recipe into the instructions so it has its own RenderHookManager
        // completely independent of the main preview
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
            enableGlobalHooks: true
        )

        let result = await renderEngine.makePlayerItem(
            recipe: recipe,
            strategy: strategy,
            config: config,
            isolatedPlayback: true  // Uses dedicated RenderHookManager, not GlobalRenderHooks
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

        // Determine which player to use next
        let nextSlot = activePlayer.opposite
        let nextPlayerView = nextSlot == .a ? content.playerA : content.playerB
        let currentPlayerView = activePlayer == .a ? content.playerA : content.playerB

        // Setup new player
        let player: AVPlayer
        if let existing = nextPlayerView.player {
            existing.replaceCurrentItem(with: buildResult.playerItem)
            player = existing
        } else {
            player = AVPlayer(playerItem: buildResult.playerItem)
            nextPlayerView.player = player
        }

        // Configure looping
        setupLooping(for: player, item: buildResult.playerItem)

        // Start playback on new player (hidden)
        nextPlayerView.alphaValue = 0
        player.play()

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

        // Add loop observer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
}

