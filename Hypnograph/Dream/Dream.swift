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
import HypnoCore
import HypnoUI

@MainActor
final class Dream: ObservableObject {
    let state: HypnographState
    let renderQueue: RenderEngine.ExportQueue

    @Published var mode: DreamMode = .montage

    private let maxSequenceSources: Int = 20

    // MARK: - Player States (independent decks)

    /// Montage player - blends all sources together
    let montagePlayer: DreamPlayerState

    /// Sequence player - plays sources back-to-back
    let sequencePlayer: DreamPlayerState

    /// Live display - external monitor output (moved from HypnographState)
    let livePlayer: LivePlayer

    /// Subscriptions to forward player state changes to Dream's objectWillChange
    private var playerSubscriptions: Set<AnyCancellable> = []

    /// The active player based on current mode
    var activePlayer: DreamPlayerState {
        mode == .montage ? montagePlayer : sequencePlayer
    }

    /// Live mode: Edit (local preview) vs Live (mirror live display)
    enum LiveMode {
        case edit
        case live
    }

    @Published var liveMode: LiveMode = .edit

    var isLiveMode: Bool { liveMode == .live }

    // MARK: - Audio Output

    /// Audio controller manages device selection and volume for preview/live
    let audioController: DreamAudioController

    /// Convenience accessors for audio state (forwarded from controller)
    var previewAudioDevice: AudioOutputDevice? {
        get { audioController.previewAudioDevice }
        set { audioController.previewAudioDevice = newValue }
    }

    var liveAudioDevice: AudioOutputDevice? {
        get { audioController.liveAudioDevice }
        set { audioController.liveAudioDevice = newValue }
    }

    var previewVolume: Float {
        get { audioController.previewVolume }
        set { audioController.previewVolume = newValue }
    }

    var liveVolume: Float {
        get { audioController.liveVolume }
        set { audioController.liveVolume = newValue }
    }

    var previewAudioDeviceUID: String? { audioController.previewAudioDeviceUID }
    var liveAudioDeviceUID: String? { audioController.liveAudioDeviceUID }

    /// Returns the active EffectManager based on live mode
    /// In live mode, effects go to the live display; in edit mode, to the active player
    var activeEffectManager: EffectManager {
        isLiveMode ? livePlayer.effectManager : activePlayer.effectManager
    }

    /// Returns the active EffectsSession based on live mode
    /// In live mode, uses live display's session; in edit mode, uses the active player's session
    var effectsSession: EffectsSession {
        isLiveMode ? livePlayer.effectsSession : activePlayer.effectsSession
    }

    func toggleLiveMode() {
        liveMode = (liveMode == .edit) ? .live : .edit
        print("🎬 Live Mode: \(liveMode == .live ? "LIVE" : "Edit")")
    }

    // MARK: - Init

    init(state: HypnographState, renderQueue: RenderEngine.ExportQueue) {
        self.state = state
        self.renderQueue = renderQueue

        // Create independent player states with mode-specific effects files and configs
        self.montagePlayer = DreamPlayerState(config: state.settings.montagePlayerConfig, effectsFilename: "montage-effects.json")
        self.sequencePlayer = DreamPlayerState(config: state.settings.sequencePlayerConfig, effectsFilename: "sequence-effects.json")
        self.livePlayer = LivePlayer(settings: state.settings, effectsFilename: "live-effects.json")

        // Create audio controller (handles device selection, volume, persistence)
        self.audioController = DreamAudioController(settingsStore: state.settingsStore, livePlayer: livePlayer)

        // Forward player state changes to Dream's objectWillChange for SwiftUI reactivity
        montagePlayer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &playerSubscriptions)
        sequencePlayer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &playerSubscriptions)

        // Forward audio controller changes for SwiftUI reactivity
        audioController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &playerSubscriptions)

        // Forward settings changes (e.g., watch mode toggle) for SwiftUI reactivity
        state.settingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &playerSubscriptions)

        // Sync player config changes back to settings
        montagePlayer.$config
            .dropFirst() // Skip initial value
            .sink { [weak self] config in
                guard let self = self else { return }
                self.state.settingsStore.update { $0.montagePlayerConfig = config }
            }
            .store(in: &playerSubscriptions)

        sequencePlayer.$config
            .dropFirst() // Skip initial value
            .sink { [weak self] config in
                guard let self = self else { return }
                self.state.settingsStore.update { $0.sequencePlayerConfig = config }
            }
            .store(in: &playerSubscriptions)

        // Set up watch timer callback to respect current mode
        state.onWatchTimerFired = { [weak self] in
            self?.new()
        }

        // Restore last recipes for each mode if available
        restorePersistedRecipes()

        // Save recipe when app terminates
        setupRecipePersistence()
    }

    // MARK: - Recipe Persistence

    /// Set up persistence to save recipe when app terminates
    private func setupRecipePersistence() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveCurrentRecipe()
            }
        }
    }

    /// Save recipes for both modes to their respective configs
    func saveCurrentRecipe() {
        // Save montage recipe if it has sources
        var montageRecipe = montagePlayer.recipe
        montageRecipe.mode = .montage
        montageRecipe.effectsLibrarySnapshot = montagePlayer.effectsSession.chains
        if !montageRecipe.sources.isEmpty {
            state.settingsStore.update { $0.montagePlayerConfig.lastRecipe = montageRecipe }
            print("📦 Saved montage recipe with \(montageRecipe.sources.count) sources")
        }

        // Save sequence recipe if it has sources
        var sequenceRecipe = sequencePlayer.recipe
        sequenceRecipe.mode = .sequence
        // Sequence uses its own duration calculation
        let totalDuration = sequencePlayer.sources.map { $0.clip.duration }.reduce(.zero, +)
        if totalDuration.seconds > 0 {
            sequenceRecipe.targetDuration = totalDuration
        }
        sequenceRecipe.effectsLibrarySnapshot = sequencePlayer.effectsSession.chains
        if !sequenceRecipe.sources.isEmpty {
            state.settingsStore.update { $0.sequencePlayerConfig.lastRecipe = sequenceRecipe }
            print("📦 Saved sequence recipe with \(sequenceRecipe.sources.count) sources")
        }

        // Force immediate synchronous save for app termination
        state.settingsStore.save(synchronous: true)
    }

    /// Restore persisted recipes for both modes
    private func restorePersistedRecipes() {
        var restoredMode: DreamMode? = nil

        // Restore montage recipe
        if let montageRecipe = state.settings.montagePlayerConfig.lastRecipe {
            var recipe = montageRecipe
            recipe.ensureEffectChainNames()
            montagePlayer.setRecipe(recipe)
            montagePlayer.currentSourceIndex = -1
            montagePlayer.effectManager.clearFrameBuffer()
            EffectChainLibraryActions.importChainsFromRecipe(recipe, into: montagePlayer.effectsSession)
            montagePlayer.notifyRecipeChanged()
            print("📦 Restored montage recipe with \(recipe.sources.count) sources")
            restoredMode = .montage
        }

        // Restore sequence recipe
        if let sequenceRecipe = state.settings.sequencePlayerConfig.lastRecipe {
            var recipe = sequenceRecipe
            recipe.ensureEffectChainNames()
            sequencePlayer.setRecipe(recipe)
            sequencePlayer.currentSourceIndex = -1
            sequencePlayer.effectManager.clearFrameBuffer()
            EffectChainLibraryActions.importChainsFromRecipe(recipe, into: sequencePlayer.effectsSession)
            sequencePlayer.notifyRecipeChanged()
            print("📦 Restored sequence recipe with \(recipe.sources.count) sources")
            // Only set mode to sequence if we didn't already restore montage
            if restoredMode == nil {
                restoredMode = .sequence
            }
        }

        // Set mode based on what was restored, defaulting to montage
        if let restoredMode = restoredMode {
            mode = restoredMode
        } else {
            // No saved recipes, generate new content for montage mode
            mode = .montage
            generateNewHypnogram(for: montagePlayer)
        }
    }

    /// Build export settings on-demand with current player config
    private func exportSettings(for mode: DreamMode) -> (outputSize: CGSize, timeline: RenderEngine.Timeline) {
        let outputSize = renderSize(
            aspectRatio: activePlayer.config.aspectRatio,
            maxDimension: activePlayer.config.playerResolution.maxDimension
        )
        let timeline: RenderEngine.Timeline = (mode == .montage)
            ? .montage(targetDuration: activePlayer.recipe.targetDuration)
            : .sequence
        return (outputSize, timeline)
    }

    // MARK: - Shared helpers

    private var sourceCount: Int { activePlayer.activeSourceCount }

    private var currentDisplayIndex: Int {
        sourceCount > 0 ? activePlayer.currentSourceIndex + 1 : 0
    }

    func sequenceTotalDuration() -> CMTime {
        activePlayer.sources.map { $0.clip.duration }.reduce(.zero, +)
    }

    // MARK: - Hypnogram Generation

    /// Generate a new random hypnogram for the given player
    private func generateNewHypnogram(for player: DreamPlayerState) {
        player.resetForNextHypnogram(preserveGlobalEffect: true)

        let total = max(1, player.config.maxSourcesForNew)
        let minCount = min(2, total)
        let count = Int.random(in: minCount...total)

        for i in 0..<max(1, count) {
            guard let clip = state.library.randomClip(clipLength: player.recipe.targetDuration.seconds) else {
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
        let clipLength = length ?? player.recipe.targetDuration.seconds
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

    /// Toggle between montage and sequence (used by PlayerSettingsView buttons)
    func toggleMode() {
        state.noteUserInteraction()
        mode = (mode == .montage) ? .sequence : .montage
    }

    /// Cycle through all three modes: Montage → Sequence → Live → Montage
    func cycleMode() {
        state.noteUserInteraction()
        if isLiveMode {
            // Live → Montage (exit live mode)
            liveMode = .edit
            mode = .montage
        } else if mode == .montage {
            // Montage → Sequence
            mode = .sequence
        } else {
            // Sequence → Live
            liveMode = .live
        }
    }

    // MARK: - Source Navigation (sequence sync)
    // Note: Flash solo is now handled by NSEvent key hold detection in HypnographAppDelegate

    func nextSource() {
        activePlayer.nextSource()
        syncLivePlayerIfSequence()
    }

    func previousSource() {
        activePlayer.previousSource()
        syncLivePlayerIfSequence()
    }

    func selectSource(index: Int) {
        activePlayer.selectSource(index)
        syncLivePlayerIfSequence()
    }

    /// Sync Live Display to current source when in sequence mode
    private func syncLivePlayerIfSequence() {
        guard mode == .sequence else { return }
        livePlayer.seekToSource(index: activePlayer.currentSourceIndex)
    }

    // MARK: - Effects

    /// Cycle effect for current layer (global when -1, source when 0+)
    func cycleEffect(direction: Int = 1) {
        state.noteUserInteraction()
        activeEffectManager.cycleEffect(for: activePlayer.currentSourceIndex, direction: direction)

        // Show flash message when effects panel is not open
        if !state.windowState.isVisible("effectsEditor") {
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
        if !state.windowState.isVisible("effectsEditor") {
            let layerLabel = activePlayer.currentSourceIndex == -1 ? "Global" : "Source \(activePlayer.currentSourceIndex + 1)"
            AppNotifications.show("\(layerLabel): None", flash: true, duration: 1.5)
        }
    }

    // MARK: - Settings helpers

    func setAspectRatio(_ ratio: AspectRatio) {
        activePlayer.config.aspectRatio = ratio
        // Config changes are auto-saved via $config subscription
        // Notify Dream to update menus
        objectWillChange.send()
    }

    func setOutputResolution(_ resolution: OutputResolution) {
        activePlayer.config.playerResolution = resolution
        // Also update in settings for persistence
        state.settingsStore.update { $0.outputResolution = resolution }
        // Notify Dream to update menus
        objectWillChange.send()
    }

    // MARK: - Display

    func makeDisplayView() -> AnyView {
        // In Live mode, mirror the Live Display player instead of local preview
        if isLiveMode {
            return AnyView(
                LivePlayerScreen(livePlayer: livePlayer)
                    .id("dream-live-\(livePlayer.config.viewID)")
            )
        }

        if mode == .sequence, activePlayer.sources.isEmpty {
            newRandomSequence()
        }

        let recipe = makeDisplayRecipe()
        let player = activePlayer

        switch mode {
        case .montage:
            return AnyView(
                MontagePlayerView(
                    recipe: recipe,
                    aspectRatio: player.config.aspectRatio,
                    displayResolution: player.config.playerResolution,
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
                    volume: previewVolume,
                    audioDeviceUID: previewAudioDeviceUID
                )
                .id("dream-montage-\(player.config.viewID)-\(recipe.playRate)")
            )

        case .sequence:
            // Only provide completion handler when Watch mode is ON
            // When Watch is off, sequence loops indefinitely (nil callback)
            let watchIsOn = state.settings.watch
            let completionHandler: (() -> Void)? = watchIsOn ? { [weak self] in
                self?.newRandomSequence()
            } : nil

            return AnyView(
                SequencePlayerView(
                    recipe: recipe,
                    aspectRatio: player.config.aspectRatio,
                    displayResolution: player.config.playerResolution,
                    currentSourceIndex: Binding(
                        get: { player.currentSourceIndex },
                        set: { player.currentSourceIndex = $0 }
                    ),
                    isPaused: player.isPaused,
                    effectsChangeCounter: player.effectsChangeCounter,
                    effectManager: player.effectManager,
                    volume: previewVolume,
                    audioDeviceUID: previewAudioDeviceUID,
                    onSourceIndexChanged: { [weak self] newIndex in
                        // Sync Live Display when auto-advancing in sequence mode
                        self?.livePlayer.seekToSource(index: newIndex)
                    },
                    onSequenceCompleted: completionHandler
                )
                .id("dream-sequence-\(player.sources.count)-\(player.config.viewID)-\(recipe.playRate)-\(watchIsOn)")
            )
        }
    }

    /// The live recipe from the active player - use for direct access/mutation
    var currentRecipe: HypnogramRecipe {
        get { activePlayer.recipe }
        set { activePlayer.recipe = newValue }
    }

    /// Build a recipe snapshot for display/export (sets mode, timestamp, effects library snapshot)
    func makeDisplayRecipe() -> HypnogramRecipe {
        // Use the recipe from activePlayer, adjust target duration based on mode
        var recipe = activePlayer.recipe
        recipe.mode = mode  // Store current mode in recipe
        recipe.createdAt = Date()  // Set creation timestamp
        recipe.effectsLibrarySnapshot = effectsSession.chains  // Snapshot the entire effects library
        switch mode {
        case .montage:
            // targetDuration is already on the recipe
            break
        case .sequence:
            // For sequence mode, use total clip duration if available
            let total = sequenceTotalDuration()
            if total.seconds > 0 {
                recipe.targetDuration = total
            }
        }
        return recipe
    }

    // MARK: - Lifecycle

    func new() {
        // In Live mode, generate directly for live display without changing edit state
        if isLiveMode {
            newForLivePlayer()
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

    /// Generate a new random recipe and send directly to live display
    /// Does NOT modify the edit state
    private func newForLivePlayer() {
        // Clear live display's frame buffer
        livePlayer.effectManager.clearFrameBuffer()

        // Generate a standalone recipe
        let recipe = generateRandomRecipe()

        // Send directly to live display
        livePlayer.send(
            recipe: recipe,
            config: activePlayer.config,
            mode: mode
        )
    }

    /// Generate a random recipe without modifying state (for live display)
    /// Preserves the current effect chain from the active player
    private func generateRandomRecipe() -> HypnogramRecipe {
        var sources: [HypnogramSource] = []
        let total = max(1, activePlayer.config.maxSourcesForNew)
        let minCount = min(2, total)
        let count = Int.random(in: minCount...total)

        for i in 0..<max(1, count) {
            guard let clip = state.library.randomClip(clipLength: activePlayer.recipe.targetDuration.seconds) else {
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
            targetDuration: activePlayer.recipe.targetDuration,
            effectChain: effectChain
        )
    }

    /// Send current hypnogram to live display
    func sendToLivePlayer() {
        livePlayer.send(
            recipe: activePlayer.recipe,
            config: activePlayer.config,
            mode: mode
        )
    }

    func toggleHUD() {
        state.windowState.toggle("hud")
    }

    func togglePause() {
        activePlayer.togglePause()
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
        guard let clip = state.library.randomClip(clipLength: activePlayer.recipe.targetDuration.seconds) else { return }
        activePlayer.sources[idx].clip = clip
    }

    /// Save current hypnogram: snapshot with embedded recipe (.hypno file)
    /// This is the main save action (S / Cmd-S)
    func save() {
        // Grab the current frame from the frame buffer (which stores the fully composited frame)
        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            print("Dream: no current frame available for save")
            return
        }

        print("Dream: saving hypnogram...")

        // Convert CIImage to CGImage with proper color space
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace) else {
            print("Dream: failed to convert CIImage to CGImage")
            return
        }

        // Get the current recipe with effects library snapshot
        let recipe = makeDisplayRecipe().copyForExport()

        // Save as .hypno file (PNG with embedded recipe)
        if let savedURL = RecipeStore.save(recipe, snapshot: cgImage) {
            print("✅ Dream: Hypnogram saved to \(savedURL.path)")
            AppNotifications.show("Hypnogram saved", flash: true)

            // Also save to Apple Photos if write access is available
            if ApplePhotos.shared.status.canWrite {
                Task {
                    let success = await ApplePhotos.shared.saveImage(at: savedURL)
                    if success {
                        print("✅ Dream: Hypnogram added to Apple Photos")
                    }
                }
            }
        } else {
            print("Dream: failed to save hypnogram")
            AppNotifications.show("Failed to save", flash: true)
        }
    }

    /// Render and save the hypnogram as a video file (enqueue to render queue)
    /// This is the legacy save behavior - available in menu without hotkey
    func renderAndSaveVideo() {
        guard !activePlayer.recipe.sources.isEmpty else {
            print("Dream[\(mode.rawValue)]: no sources to render.")
            return
        }

        // Deep copy recipe with fresh effect instances to avoid sharing state with preview
        var renderRecipe = activePlayer.recipe.copyForExport()
        switch mode {
        case .montage:
            // targetDuration is already on the recipe
            break
        case .sequence:
            // For sequence mode, use total clip duration if available
            let total = sequenceTotalDuration()
            if total.seconds > 0 {
                renderRecipe.targetDuration = total
            }
        }

        // Create renderer with current settings (aspect ratio + resolution)
        let settings = exportSettings(for: mode)

        print("Dream[\(mode.rawValue)]: enqueueing recipe with \(renderRecipe.sources.count) source(s), duration: \(renderRecipe.targetDuration.seconds)s")

        // Enqueue immediately (don't defer - the renderer handles async internally)
        renderQueue.enqueue(
            recipe: renderRecipe,
            outputFolder: state.settings.outputURL,
            outputSize: settings.outputSize,
            timeline: settings.timeline
        )

        AppNotifications.show("Rendering video...", flash: true)

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

    /// Save hypnogram to a specific location (with file picker)
    func saveAs() {
        // Grab the current frame from the frame buffer
        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            print("Dream: no current frame available for save")
            return
        }

        // Convert CIImage to CGImage
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace) else {
            print("Dream: failed to convert CIImage to CGImage")
            return
        }

        let recipe = makeDisplayRecipe().copyForExport()
        RecipeFileActions.saveAs(recipe: recipe, snapshot: cgImage) {
            AppNotifications.show("Hypnogram saved", flash: true)
        }
    }

    /// Open a .hypno or .hypnogram recipe file
    func openRecipe() {
        RecipeFileActions.openRecipe(
            onLoaded: { [weak self] recipe in
                self?.loadRecipe(recipe)
                AppNotifications.show("Recipe loaded", flash: true)
            },
            onFailure: {
                AppNotifications.show("Failed to load recipe", flash: true)
            }
        )
    }

    /// Load a recipe into the current player
    func loadRecipe(_ recipe: HypnogramRecipe) {
        // Ensure effect chains have names (required for library matching)
        var mutableRecipe = recipe
        mutableRecipe.ensureEffectChainNames()

        // Switch to the mode the recipe was saved in
        mode = mutableRecipe.mode

        activePlayer.setRecipe(mutableRecipe)
        // Default to Global layer (-1) so effects editor shows global effects first
        activePlayer.currentSourceIndex = -1

        // Clear frame buffer for clean slate
        activePlayer.effectManager.clearFrameBuffer()

        // Import effect chains used in the recipe into the session
        // (adds missing chains, replaces same-named chains with recipe versions)
        EffectChainLibraryActions.importChainsFromRecipe(mutableRecipe, into: effectsSession)

        // Notify player to reload
        activePlayer.notifyRecipeChanged()
    }

    /// Favorite the current hypnogram (save to store as favorite)
    func favoriteCurrentHypnogram() {
        guard !activePlayer.recipe.sources.isEmpty else {
            print("Dream: no sources to favorite")
            return
        }

        // Grab current frame for snapshot
        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            print("Dream: no current frame available for favorite")
            return
        }

        // Convert CIImage to CGImage
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace) else {
            print("Dream: failed to convert CIImage to CGImage for favorite")
            return
        }

        if let entry = HypnogramStore.shared.add(
            recipe: activePlayer.recipe,
            snapshot: cgImage,
            isFavorite: true
        ) {
            AppNotifications.show("Added to favorites: \(entry.name)", flash: true)
        }
    }

    // MARK: - Montage blend modes

    private func blendModeForSourceIndex(_ idx: Int) -> String {
        guard idx >= 0, idx < activePlayer.sources.count else { return BlendMode.sourceOver }
        return activePlayer.sources[idx].blendMode ?? (idx == 0 ? BlendMode.sourceOver : BlendMode.defaultMontage)
    }

    func currentBlendModeDisplayName() -> String {
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
            ? livePlayer.activeSourceCount
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
        // Use maxSourcesForNew from player config, clamped to maxSequenceSources
        let maxFromConfig = max(1, sequencePlayer.config.maxSourcesForNew)
        let desiredCount = min(maxFromConfig, maxSequenceSources)
        // Generate random count between 2 and desiredCount (or just desiredCount if small)
        let minCount = min(2, desiredCount)
        let count = Int.random(in: minCount...desiredCount)
        for _ in 0..<count {
            let length = Double.random(in: 2.0...15.0)
            addSourceToPlayer(sequencePlayer, length: length)
        }
        sequencePlayer.currentSourceIndex = 0
        print("DreamMode[sequence]: generated sequence with \(sequencePlayer.sources.count) sources (max: \(maxFromConfig)), total duration: \(sequenceTotalDuration().seconds)s")
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

}

// Keep indices positive when wrapping.
private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    guard modulus > 0 else { return 0 }
    let r = value % modulus
    return r >= 0 ? r : r + modulus
}
