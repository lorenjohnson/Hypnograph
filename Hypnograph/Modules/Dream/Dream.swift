//
//  Dream.swift
//  Hypnograph
//
//  Dream feature: video/image composition with montage and sequence modes.
//

import Foundation
import CoreGraphics
import CoreMedia
import Combine
import SwiftUI
import AVFoundation
import AppKit

enum DreamMode: String, Codable {
    case montage
    case sequence
}

@MainActor
final class Dream: ObservableObject {
    let state: HypnographState
    let renderQueue: RenderQueue

    @Published var mode: DreamMode = .montage

    private let maxSequenceSources: Int = 20
    private let initialSequenceSourceCount: Int = 5

    // MARK: - Player States (independent decks)

    /// Montage player - blends all sources together
    let montagePlayer: DreamPlayerState

    /// Sequence player - plays sources back-to-back
    let sequencePlayer: DreamPlayerState

    /// Performance display - external monitor output (moved from HypnographState)
    let performanceDisplay: PerformanceDisplay

    /// Subscriptions to forward player state changes to Dream's objectWillChange
    private var playerSubscriptions: Set<AnyCancellable> = []

    /// The active player based on current mode
    var activePlayer: DreamPlayerState {
        mode == .montage ? montagePlayer : sequencePlayer
    }

    /// Performance mode: Edit (local preview) vs Live (mirror performance display)
    enum PerformanceMode {
        case edit
        case live
    }

    @Published var performanceMode: PerformanceMode = .edit

    var isLiveMode: Bool { performanceMode == .live }

    // MARK: - Audio Output
    // NOTE: Audio device routing is disabled pending AVAudioEngine implementation.
    // These properties are kept for UI but not connected to players.
    // Both Preview and Performance currently use system default audio output.

    /// Selected audio output device for Preview player (nil = None/muted)
    /// NOTE: Not currently functional - see above
    @Published var previewAudioDevice: AudioOutputDevice? = nil

    /// Selected audio output device for Performance player (nil = None/muted)
    /// NOTE: Not currently functional - see above
    @Published var performanceAudioDevice: AudioOutputDevice? = nil

    /// Volume level for Preview audio (0.0 to 1.0)
    @Published var previewVolume: Float = 1.0

    /// Volume level for Performance audio (0.0 to 1.0)
    @Published var performanceVolume: Float = 1.0

    /// Returns the active EffectManager based on performance mode
    /// In live mode, effects go to the performance display; in edit mode, to the active player
    var activeEffectManager: EffectManager {
        isLiveMode ? performanceDisplay.effectManager : activePlayer.effectManager
    }

    func togglePerformanceMode() {
        performanceMode = (performanceMode == .edit) ? .live : .edit
        print("🎬 Performance Mode: \(performanceMode == .live ? "LIVE" : "Edit")")
    }

    // MARK: - Init

    init(state: HypnographState, renderQueue: RenderQueue) {
        self.state = state
        self.renderQueue = renderQueue

        // Create independent player states
        self.montagePlayer = DreamPlayerState(settings: state.settings)
        self.sequencePlayer = DreamPlayerState(settings: state.settings)
        self.performanceDisplay = PerformanceDisplay()

        // Forward player state changes to Dream's objectWillChange for SwiftUI reactivity
        montagePlayer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &playerSubscriptions)
        sequencePlayer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &playerSubscriptions)

        // Set up watch timer callback to respect current mode
        state.onWatchTimerFired = { [weak self] in
            self?.new()
        }

        // Generate initial content for montage player
        generateNewHypnogram(for: montagePlayer)

        // NOTE: Audio device routing subscriptions removed pending AVAudioEngine implementation
        // Performance volume still applied to performance display
        $performanceVolume
            .sink { [weak self] volume in
                self?.performanceDisplay.setVolume(volume)
            }
            .store(in: &playerSubscriptions)
    }

    /// Create a renderer on-demand with current settings (aspect ratio + resolution)
    private func makeRenderer(for mode: DreamMode) -> HypnogramRenderer {
        let outputSize = renderSize(
            aspectRatio: activePlayer.aspectRatio,
            maxDimension: activePlayer.outputResolution.maxDimension
        )
        let strategy: CompositionBuilder.TimelineStrategy = (mode == .montage)
            ? .montage(targetDuration: activePlayer.targetDuration)
            : .sequence
        return HypnogramRenderer(
            outputURL: state.settings.outputURL,
            outputSize: outputSize,
            strategy: strategy
        )
    }

    // MARK: - Shared helpers

    private var sourceCount: Int { activePlayer.activeSourceCount }

    private var currentDisplayIndex: Int {
        sourceCount > 0 ? activePlayer.currentSourceIndex + 1 : 0
    }

    private func sequenceTotalDuration() -> CMTime {
        activePlayer.sources.map { $0.clip.duration }.reduce(.zero, +)
    }

    // MARK: - Hypnogram Generation

    /// Generate a new random hypnogram for the given player
    private func generateNewHypnogram(for player: DreamPlayerState) {
        player.resetForNextHypnogram(preserveGlobalEffect: true)

        let total = max(1, player.maxSourcesForNew)
        let minCount = min(2, total)
        let count = Int.random(in: minCount...total)

        for i in 0..<max(1, count) {
            guard let clip = state.library.randomClip(clipLength: player.targetDuration.seconds) else {
                continue
            }
            let blendMode = (i == 0) ? BlendMode.sourceOver : BlendMode.random()
            let source = HypnogramSource(clip: clip, blendMode: blendMode)
            player.sources.append(source)
        }

        player.effectManager.invalidateBlendAnalysis()
        player.effectManager.onEffectChanged?()
    }

    /// Add a source to the given player
    private func addSourceToPlayer(_ player: DreamPlayerState, length: Double? = nil) {
        // Use default clip length if not provided
        let clipLength = length ?? player.targetDuration.seconds
        guard let clip = state.library.randomClip(clipLength: clipLength) else { return }
        let blendMode = player.sources.isEmpty ? BlendMode.sourceOver : BlendMode.random()
        let source = HypnogramSource(clip: clip, blendMode: blendMode)
        player.sources.append(source)
        player.currentSourceIndex = player.sources.count - 1
    }

    private func preferredClipLength() -> Double? {
        switch mode {
        case .montage:
            return nil
        case .sequence:
            return Double.random(in: 2.0...15.0)
        }
    }

    // MARK: - Mode

    func toggleMode() {
        state.noteUserInteraction()
        mode = (mode == .montage) ? .sequence : .montage
    }

    // MARK: - Source Navigation (with flash solo in montage mode, sequence sync)

    private var flashSoloTimer: Timer?

    func nextSource() {
        activePlayer.nextSource()
        triggerFlashSoloIfNeeded()
        syncPerformanceDisplayIfSequence()
    }

    func previousSource() {
        activePlayer.previousSource()
        triggerFlashSoloIfNeeded()
        syncPerformanceDisplayIfSequence()
    }

    func selectSource(index: Int) {
        activePlayer.selectSource(index)
        triggerFlashSoloIfNeeded()
        syncPerformanceDisplayIfSequence()
    }

    private func triggerFlashSoloIfNeeded() {
        // Only flash solo in montage mode and if setting is enabled
        guard mode == .montage else { return }

        // Cancel any existing timer
        flashSoloTimer?.invalidate()

        // Set flash solo to current source
        activePlayer.effectManager.setFlashSolo(activePlayer.currentSourceIndex)

        // Clear after delay
        flashSoloTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.activePlayer.effectManager.setFlashSolo(nil)
        }
    }

    /// Sync Performance Display to current source when in sequence mode
    private func syncPerformanceDisplayIfSequence() {
        guard mode == .sequence else { return }
        performanceDisplay.seekToSource(index: activePlayer.currentSourceIndex)
    }

    // MARK: - Effects

    /// Cycle effect for current layer (global when -1, source when 0+)
    func cycleEffect(direction: Int = 1) {
        state.noteUserInteraction()
        activeEffectManager.cycleEffect(for: activePlayer.currentSourceIndex, direction: direction)

        // Show flash message when effects panel is not open
        if !state.windowState.isVisible(.effectsEditor) {
            let effectName = activeEffectManager.effectName(for: activePlayer.currentSourceIndex)
            let layerLabel = activePlayer.currentSourceIndex == -1 ? "Global" : "Source \(activePlayer.currentSourceIndex + 1)"
            AppNotifications.show("\(layerLabel): \(effectName)", flash: true, duration: 1.5)
        }
    }

    /// Clear effect for current layer only
    func clearCurrentLayerEffect() {
        state.noteUserInteraction()
        activeEffectManager.clearEffect(for: activePlayer.currentSourceIndex)

        // Show flash message when effects panel is not open
        if !state.windowState.isVisible(.effectsEditor) {
            let layerLabel = activePlayer.currentSourceIndex == -1 ? "Global" : "Source \(activePlayer.currentSourceIndex + 1)"
            AppNotifications.show("\(layerLabel): None", flash: true, duration: 1.5)
        }
    }

    // MARK: - HUD

    func hudItems() -> [HUDItem] {
        var items: [HUDItem] = []

        // Header
        items.append(.text("Hypnograph", order: 10, font: .headline))
        let modeLabel = (mode == .montage ? "Montage" : "Sequence")
        items.append(.text("Dream: \(modeLabel)", order: 11, font: .subheadline))
        items.append(.padding(8, order: 15))

        // Queue status
        if renderQueue.activeJobs > 0 {
            items.append(.text("Queue: \(renderQueue.activeJobs)", order: 20, font: .subheadline))
        } else {
            items.append(.text("Queue: 0", order: 20, font: .caption))
        }
        items.append(.padding(8, order: 21))

        // Layer info (Global or Source X of Y)
        items.append(.text(activePlayer.editingLayerDisplay, order: 22))
        items.append(.text("Effect (E): \(activeEffectManager.effectName(for: activePlayer.currentSourceIndex))", order: 23))

        // Source-specific info (only when on a source layer, not global)
        if !activePlayer.isOnGlobalLayer {
            switch mode {
            case .montage:
                items.append(.text("Blend mode (M): \(currentBlendModeDisplayName())", order: 26))
            case .sequence:
                let totalSecs = sequenceTotalDuration().seconds
                items.append(.text(String(format: "Duration: %.1fs", totalSecs), order: 26))
                if let clip = activePlayer.currentClip {
                    items.append(.text("Clip: \(String(format: "%.1fs", clip.duration.seconds))", order: 27))
                }
            }

            // Favorite status
            if let source = activePlayer.currentSource?.clip.file.source,
               FavoriteStore.shared.isFavorited(source) {
                items.append(.text("★ Favorite", order: 29))
            }
        }

        items.append(.padding(16, order: 39))

        // Keyboard hints
        items.append(.text("Shortcuts", order: 40, font: .subheadline))
        items.append(.text("R = Rotate | . = New clip | M = Blend", order: 41))
        items.append(.text("E = Effects | 0 = Global | 1-9 = Source", order: 42))
        items.append(.text("←/→ = Navigate | C = Clear | ⌃⇧C = Clear all", order: 43))
        items.append(.text("N = New | ⇧N = Add source | S = Snapshot", order: 44))
        items.append(.text("` = Toggle Montage/Sequence", order: 45))
        items.append(.text("⇧F/X/D = Favorite/Exclude/Delete", order: 46))

        return items
    }

    // MARK: - Menus

    /// Whether a text field is being edited - disables single-key shortcuts
    private var isTyping: Bool { state.isTyping }

    @ViewBuilder
    func compositionMenu() -> some View {
        Button("Toggle Mode (Montage/Sequence)") { [self] in
            toggleMode()
        }
        .keyboardShortcut("`", modifiers: [])
        .disabled(isTyping)

        Divider()

        Button("Cycle Effect Forward") { [self] in
            cycleEffect(direction: 1)
        }
        .keyboardShortcut("e", modifiers: [.command])

        Button("Cycle Effect Backward") { [self] in
            cycleEffect(direction: -1)
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Add Source") { [self] in
            addSource()
        }
        .keyboardShortcut("n", modifiers: [.shift])

        // Only use arrow shortcuts when effects editor is closed (otherwise they adjust params)
        if !state.windowState.isVisible(.effectsEditor) {
            Button("> Next Source") { [self] in
                nextSource()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(isTyping)

            Button("< Previous Source") { [self] in
                previousSource()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(isTyping)
        } else {
            Button("> Next Source") { [self] in
                nextSource()
            }

            Button("< Previous Source") { [self] in
                previousSource()
            }
        }

        ForEach(0..<9, id: \.self) { [self] idx in
            Button("Select Source \(idx + 1)") {
                selectSource(index: idx)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            .disabled(isTyping)
        }

        Button("Select Global Layer") { [self] in
            activePlayer.selectGlobalLayer()
        }
        .keyboardShortcut("0", modifiers: [])
        .disabled(isTyping)

        Divider()

        Button("Clear Current Layer Effect") { [self] in
            clearCurrentLayerEffect()
        }
        .keyboardShortcut("c", modifiers: [])
        .disabled(isTyping)

        Button("Clear All Effects") { [self] in
            clearAllEffects()
        }
        .keyboardShortcut("c", modifiers: [.control, .shift])

        Divider()

        Button("New Hypnogram") { [self] in
            new()
        }
        .keyboardShortcut("n", modifiers: [])
        .disabled(isTyping)

        Divider()

        Button("Save") { [self] in
            save()
        }
        .keyboardShortcut("s", modifiers: [.command])

        Button("Save Snapshot") { [self] in
            saveSnapshot()
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Button("Favorite Hypnogram") { [self] in
            favoriteCurrentHypnogram()
        }
        .keyboardShortcut("f", modifiers: [.command])

        Divider()

        // Aspect Ratio
        Section("Aspect Ratio") {
            ForEach(AspectRatio.menuPresets, id: \.displayString) { ratio in
                Toggle(ratio.menuLabel, isOn: Binding(
                    get: { [self] in activePlayer.aspectRatio == ratio },
                    set: { [self] in if $0 { setAspectRatio(ratio) } }
                ))
            }
        }

        // Output Resolution
        Section("Output Resolution") {
            ForEach(OutputResolution.allCases, id: \.self) { resolution in
                Toggle(resolution.displayName, isOn: Binding(
                    get: { [self] in activePlayer.outputResolution == resolution },
                    set: { [self] in if $0 { setOutputResolution(resolution) } }
                ))
            }
        }
    }

    // MARK: - Settings helpers

    func setAspectRatio(_ ratio: AspectRatio) {
        activePlayer.aspectRatio = ratio
        // Also update in settings for persistence
        state.settings.aspectRatio = ratio
        state.saveSettings()
        // Notify Dream to update menus
        objectWillChange.send()
    }

    func setOutputResolution(_ resolution: OutputResolution) {
        activePlayer.outputResolution = resolution
        // Also update in settings for persistence
        state.settings.outputResolution = resolution
        state.saveSettings()
        // Notify Dream to update menus
        objectWillChange.send()
    }

    @ViewBuilder
    func sourceMenu() -> some View {
        Button("Cycle Blend Mode") { [self] in
            cycleBlendMode()
        }
        .keyboardShortcut("m", modifiers: [])
        .disabled(isTyping)

        Divider()

        Button("New Random Clip") { [self] in
            newRandomClip()
        }
        .keyboardShortcut(".", modifiers: [])
        .disabled(isTyping)

        Divider()

        Button("Delete") { [self] in
            deleteCurrentSource()
        }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(isTyping)

        Button("Add to Exclude List") { [self] in
            excludeCurrentSource()
        }
        .keyboardShortcut("x", modifiers: [.shift])

        Button("Mark for Deletion") { [self] in
            markCurrentSourceForDeletion()
        }
        .keyboardShortcut("d", modifiers: [.shift])

        Button("Toggle Favorite") { [self] in
            toggleCurrentSourceFavorite()
        }
        .keyboardShortcut("f", modifiers: [.shift])
    }

    // MARK: - Display

    func makeDisplayView() -> AnyView {
        // In Live mode, mirror the Performance Display player instead of local preview
        if isLiveMode {
            return AnyView(
                LiveModePlayerView(performanceDisplay: performanceDisplay)
            )
        }

        if mode == .sequence, activePlayer.sources.isEmpty {
            newRandomSequence()
        }

        let recipe = makeDisplayRecipe()
        let player = activePlayer

        // Preview is muted if no audio device selected OR volume is 0
        // Preview uses volume control - muted when volume is 0
        let previewMuted = previewVolume == 0

        switch mode {
        case .montage:
            return AnyView(
                MontagePlayerView(
                    recipe: recipe,
                    aspectRatio: player.aspectRatio,
                    displayResolution: player.outputResolution,
                    currentSourceIndex: Binding(
                        get: { player.currentSourceIndex },
                        set: { player.currentSourceIndex = $0 }
                    ),
                    currentSourceTime: Binding(
                        get: { player.currentClipTimeOffset },
                        set: { player.currentClipTimeOffset = $0 }
                    ),
                    isPaused: player.isPaused,
                    effectsChangeCounter: player.effectsChangeCounter,
                    effectManager: player.effectManager,
                    isMuted: previewMuted,
                    volume: previewVolume
                )
                .id("dream-montage-\(player.aspectRatio.displayString)-\(player.outputResolution.rawValue)-\(player.targetDuration.seconds)-\(recipe.playRate)")
            )

        case .sequence:
            return AnyView(
                SequencePlayerView(
                    recipe: recipe,
                    aspectRatio: player.aspectRatio,
                    displayResolution: player.outputResolution,
                    currentSourceIndex: Binding(
                        get: { player.currentSourceIndex },
                        set: { player.currentSourceIndex = $0 }
                    ),
                    isPaused: player.isPaused,
                    effectsChangeCounter: player.effectsChangeCounter,
                    effectManager: player.effectManager,
                    isMuted: previewMuted,
                    volume: previewVolume,
                    onSourceIndexChanged: { [weak self] newIndex in
                        // Sync Performance Display when auto-advancing in sequence mode
                        self?.performanceDisplay.seekToSource(index: newIndex)
                    }
                )
                .id("dream-sequence-\(player.sources.count)-\(player.aspectRatio.displayString)-\(player.outputResolution.rawValue)-\(recipe.playRate)")
            )
        }
    }

    /// Get the current recipe for display (with proper duration set)
    var currentRecipe: HypnogramRecipe {
        makeDisplayRecipe()
    }

    private func makeDisplayRecipe() -> HypnogramRecipe {
        // Use the recipe from activePlayer, adjust target duration based on mode
        var recipe = activePlayer.recipe
        switch mode {
        case .montage:
            recipe.targetDuration = activePlayer.targetDuration
        case .sequence:
            let total = sequenceTotalDuration()
            recipe.targetDuration = total.seconds > 0 ? total : activePlayer.targetDuration
        }
        return recipe
    }

    // MARK: - Lifecycle

    func new() {
        // In Live mode, generate directly for performance display without changing edit state
        if isLiveMode {
            newForPerformanceDisplay()
            return
        }

        // Clear frame buffer to prevent memory bloat from stored CIImages
        activePlayer.effectManager.clearFrameBuffer()

        // Clear image cache if it's getting large to prevent memory bloat
        let cacheSize = StillImageCache.cacheSize()
        if cacheSize.ciImages > 30 || cacheSize.cgImages > 30 {
            StillImageCache.clear()
        }

        switch mode {
        case .montage:
            generateNewHypnogram(for: montagePlayer)
        case .sequence:
            newRandomSequence()
        }
    }

    /// Generate a new random recipe and send directly to performance display
    /// Does NOT modify the edit state
    private func newForPerformanceDisplay() {
        // Clear performance display's frame buffer
        performanceDisplay.effectManager.clearFrameBuffer()

        // Generate a standalone recipe
        let recipe = generateRandomRecipe()

        // Send directly to performance display
        performanceDisplay.send(
            recipe: recipe,
            aspectRatio: activePlayer.aspectRatio,
            resolution: activePlayer.outputResolution,
            mode: mode
        )
    }

    /// Generate a random recipe without modifying state (for performance display)
    /// Preserves the current effect chain from the active player
    private func generateRandomRecipe() -> HypnogramRecipe {
        var sources: [HypnogramSource] = []
        let total = max(1, activePlayer.maxSourcesForNew)
        let minCount = min(2, total)
        let count = Int.random(in: minCount...total)

        for i in 0..<max(1, count) {
            guard let clip = state.library.randomClip(clipLength: activePlayer.targetDuration.seconds) else {
                continue
            }
            // First source uses SourceOver, rest get random blend modes
            let blendMode = (i == 0) ? BlendMode.sourceOver : BlendMode.random()
            let source = HypnogramSource(clip: clip, blendMode: blendMode)
            sources.append(source)
        }

        // Copy effect chain from active player so new recipes inherit current effects
        let effectChain = activePlayer.recipe.effectChain.copy()

        return HypnogramRecipe(
            sources: sources,
            targetDuration: activePlayer.targetDuration,
            effectChain: effectChain
        )
    }

    /// Send current hypnogram to performance display
    func sendToPerformanceDisplay() {
        performanceDisplay.send(
            recipe: activePlayer.recipe,
            aspectRatio: activePlayer.aspectRatio,
            resolution: activePlayer.outputResolution,
            mode: mode
        )
    }

    func toggleHUD() {
        state.windowState.toggle(.hud)
    }

    func togglePause() {
        activePlayer.togglePause()
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        // Also update player states with new settings
        montagePlayer.targetDuration = state.settings.outputDuration
        montagePlayer.maxSourcesForNew = state.settings.maxSourcesForNew
        sequencePlayer.targetDuration = state.settings.outputDuration
        sequencePlayer.maxSourcesForNew = state.settings.maxSourcesForNew
        if mode == .sequence {
            newRandomSequence()
        }
    }

    // Override addSource to use appropriate length for sequence mode
    func addSource() {
        let length = preferredClipLength()
        addSourceToPlayer(activePlayer, length: length)
    }

    func newRandomClip() {
        replaceClipForCurrentSource()
    }

    func deleteCurrentSource() {
        let idx = activePlayer.currentSourceIndex
        guard idx >= 0, idx < activePlayer.sources.count else { return }
        activePlayer.sources.remove(at: idx)
        // Adjust currentSourceIndex
        if activePlayer.sources.isEmpty {
            activePlayer.currentSourceIndex = 0
        } else if idx >= activePlayer.sources.count {
            activePlayer.currentSourceIndex = activePlayer.sources.count - 1
        }
    }

    /// Replace the clip for current source with a new random one
    private func replaceClipForCurrentSource() {
        let idx = activePlayer.currentSourceIndex
        guard idx >= 0, idx < activePlayer.sources.count else { return }
        guard let clip = state.library.randomClip(clipLength: activePlayer.targetDuration.seconds) else { return }
        activePlayer.sources[idx].clip = clip
    }

    /// Save a snapshot of the current frame from the frame buffer
    func saveSnapshot() {
        // Grab the current frame from the frame buffer (which stores the fully composited frame)
        guard let currentFrame = activePlayer.effectManager.frameBuffer.currentFrame else {
            print("DreamMode: no current frame available for snapshot")
            return
        }

        print("DreamMode: saving snapshot of current frame...")

        // Convert CIImage to CGImage with proper color space
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace) else {
            print("DreamMode: failed to convert CIImage to CGImage")
            return
        }

        // Ensure snapshots folder exists
        let snapshotsURL = state.settings.snapshotsURL
        do {
            try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("DreamMode: failed to create snapshots folder: \(error)")
            return
        }

        // Save to file in snapshots folder
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "hypnograph-snapshot-\(timestamp).png"
        let outputURL = snapshotsURL.appendingPathComponent(filename)

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, kUTTypePNG, 1, nil) else {
            print("DreamMode: failed to create image destination")
            return
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        if CGImageDestinationFinalize(destination) {
            print("✅ DreamMode: Snapshot saved to \(outputURL.path)")
            AppNotifications.show("Snapshot saved", flash: true)

            // Also save to Apple Photos if write access is available
            if ApplePhotos.shared.status.canWrite {
                Task {
                    let success = await ApplePhotos.shared.saveImage(at: outputURL)
                    if success {
                        print("✅ DreamMode: Snapshot added to Apple Photos")
                    }
                }
            }
        } else {
            print("DreamMode: failed to save snapshot")
        }
    }

    func save() {
        guard !activePlayer.recipe.sources.isEmpty else {
            print("Dream[\(mode.rawValue)]: no sources to save.")
            return
        }

        // Deep copy recipe with fresh effect instances to avoid sharing state with preview
        var renderRecipe = activePlayer.recipe.copyForExport()
        switch mode {
        case .montage:
            renderRecipe.targetDuration = activePlayer.targetDuration
        case .sequence:
            let total = sequenceTotalDuration()
            renderRecipe.targetDuration = total.seconds > 0 ? total : activePlayer.targetDuration
        }

        // Create renderer with current settings (aspect ratio + resolution)
        let renderer = makeRenderer(for: mode)

        print("Dream[\(mode.rawValue)]: enqueueing recipe with \(renderRecipe.sources.count) source(s), duration: \(renderRecipe.targetDuration.seconds)s")

        // Enqueue immediately (don't defer - the renderer handles async internally)
        renderQueue.enqueue(renderer: renderer, recipe: renderRecipe)

        // Reset for next hypnogram
        // Defer this to avoid modifying @Published during button action
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch self.mode {
            case .montage:
                self.generateNewHypnogram(for: self.montagePlayer)
            case .sequence:
                self.newRandomSequence()
            }
        }
    }

    /// Save recipe to .hypnogram file (with file picker)
    func saveRecipe() {
        guard !activePlayer.recipe.sources.isEmpty else {
            print("Dream: no sources to save recipe")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: RecipeStore.fileExtension)!]
        panel.nameFieldStringValue = "hypnogram-\(formattedTimestamp()).\(RecipeStore.fileExtension)"
        panel.directoryURL = RecipeStore.recipesDirectory

        panel.begin { [self] response in
            guard response == .OK, let url = panel.url else { return }

            if RecipeStore.save(activePlayer.recipe, to: url) != nil {
                AppNotifications.show("Recipe saved", flash: true)
            }
        }
    }

    /// Open a .hypnogram recipe file
    func openRecipe() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: RecipeStore.fileExtension)!]
        panel.directoryURL = RecipeStore.recipesDirectory
        panel.allowsMultipleSelection = false

        panel.begin { [self] response in
            guard response == .OK, let url = panel.url else { return }

            guard let recipe = RecipeStore.load(from: url) else {
                AppNotifications.show("Failed to load recipe", flash: true)
                return
            }

            loadRecipe(recipe)
            AppNotifications.show("Recipe loaded", flash: true)
        }
    }

    /// Load a recipe into the current player
    func loadRecipe(_ recipe: HypnogramRecipe) {
        activePlayer.setRecipe(recipe)
        activePlayer.currentSourceIndex = recipe.sources.isEmpty ? -1 : 0

        // Clear frame buffer for clean slate
        activePlayer.effectManager.clearFrameBuffer()

        // Import effect chains from recipe into library so they're available for editing
        EffectChainLibraryActions.importChainsFromRecipe(recipe)

        // Notify player to reload
        activePlayer.notifyRecipeChanged()
    }

    /// Favorite the current hypnogram (save to store as favorite)
    func favoriteCurrentHypnogram() {
        guard !activePlayer.recipe.sources.isEmpty else {
            print("Dream: no sources to favorite")
            return
        }

        // Grab current frame for thumbnail
        let thumbnailImage = activePlayer.effectManager.frameBuffer.currentFrame

        if let entry = HypnogramStore.shared.add(
            recipe: activePlayer.recipe,
            isFavorite: true,
            thumbnailImage: thumbnailImage
        ) {
            AppNotifications.show("Added to favorites: \(entry.name)", flash: true)
        }
    }

    private func formattedTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }

    // MARK: - Montage blend modes

    private func blendModeForSourceIndex(_ idx: Int) -> String {
        guard idx >= 0, idx < activePlayer.sources.count else { return BlendMode.sourceOver }
        return activePlayer.sources[idx].blendMode ?? (idx == 0 ? BlendMode.sourceOver : BlendMode.defaultMontage)
    }

    private func currentBlendModeDisplayName() -> String {
        blendModeForSourceIndex(activePlayer.currentSourceIndex)
            .replacingOccurrences(of: "CI", with: "")
            .replacingOccurrences(of: "BlendMode", with: "")
    }

    func cycleBlendMode(at index: Int? = nil) {
        state.noteUserInteraction()

        let idx = index ?? activePlayer.currentSourceIndex
        guard idx > 0, idx < activePlayer.sources.count else { return } // bottom layer stays SourceOver

        // Cycle blend mode - this writes directly to sources via the setter closure
        activePlayer.effectManager.cycleBlendMode(for: idx)
    }



    // MARK: - Effects

    /// Clear all effects AND reset blend modes to Screen (default)
    func clearAllEffects() {
        state.noteUserInteraction()
        activeEffectManager.clearEffect(for: -1)  // Global

        // Get source count from appropriate context
        let sourceCount = isLiveMode
            ? performanceDisplay.activeSourceCount
            : activePlayer.activeSourceCount

        for i in 0..<sourceCount {
            activeEffectManager.clearEffect(for: i)
            // Reset blend mode on source (keep first one as SourceOver) - only in Edit mode
            if !isLiveMode && i > 0 && i < activePlayer.sources.count {
                activePlayer.sources[i].blendMode = BlendMode.defaultMontage
            }
        }
    }

    // MARK: - Sequence helpers

    private func newRandomSequence() {
        sequencePlayer.resetForNextHypnogram(preserveGlobalEffect: true)
        let desiredCount = min(initialSequenceSourceCount, maxSequenceSources)
        for _ in 0..<desiredCount {
            let length = Double.random(in: 2.0...15.0)
            addSourceToPlayer(sequencePlayer, length: length)
        }
        sequencePlayer.currentSourceIndex = 0
        print("DreamMode[sequence]: generated sequence with \(sequencePlayer.sources.count) sources, total duration: \(sequenceTotalDuration().seconds)s")
    }

    // MARK: - Source Management Helpers

    /// Exclude current source from library
    func excludeCurrentSource() {
        let idx = activePlayer.currentSourceIndex
        guard idx >= 0, idx < activePlayer.sources.count else { return }
        let file = activePlayer.sources[idx].clip.file
        state.library.exclude(file: file)
        replaceClipForCurrentSource()
        AppNotifications.show("Added to exclusion list", flash: true)
    }

    /// Mark current source for deletion
    func markCurrentSourceForDeletion() {
        let idx = activePlayer.currentSourceIndex
        guard idx >= 0, idx < activePlayer.sources.count else { return }
        let file = activePlayer.sources[idx].clip.file
        state.library.markForDeletion(file: file)
        replaceClipForCurrentSource()
        AppNotifications.show("Marked for deletion", flash: true)
    }

    /// Toggle favorite status for current source
    func toggleCurrentSourceFavorite() {
        let idx = activePlayer.currentSourceIndex
        guard idx >= 0, idx < activePlayer.sources.count else { return }
        let mediaSource = activePlayer.sources[idx].clip.file.source
        FavoriteStore.shared.toggle(mediaSource)
        let isFav = FavoriteStore.shared.isFavorited(mediaSource)
        AppNotifications.show(isFav ? "★ Added to favorites" : "Removed from favorites", flash: true)
    }
}

// Keep indices positive when wrapping.
private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    guard modulus > 0 else { return 0 }
    let r = value % modulus
    return r >= 0 ? r : r + modulus
}
