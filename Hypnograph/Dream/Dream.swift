//
//  Dream.swift
//  Hypnograph
//
//  Dream feature: video/image composition with a single preview path.
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

    /// Global templates store (shared across preview + live)
    let effectsLibrarySession: EffectsSession

    /// Global RECENT effects store (shared across preview + live)
    let recentEffectsStore: RecentEffectChainsStore

    // MARK: - Player States

    /// Preview deck - a layered clip
    let player: DreamPlayerState

    /// Live display - external monitor output (moved from HypnographState)
    let livePlayer: LivePlayer

    /// Subscriptions to forward player state changes to Dream's objectWillChange
    private var playerSubscriptions: Set<AnyCancellable> = []

    /// The active preview player (always the preview deck)
    var activePlayer: DreamPlayerState { player }

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
    /// In Step 4 (MVR), templates are global across modes.
    var effectsSession: EffectsSession {
        effectsLibrarySession
    }

    func toggleLiveMode() {
        liveMode = (liveMode == .edit) ? .live : .edit
        print("🎬 Live Mode: \(liveMode == .live ? "LIVE" : "Edit")")
    }

    // MARK: - Init

    init(state: HypnographState, renderQueue: RenderEngine.ExportQueue) {
        self.state = state
        self.renderQueue = renderQueue

        // Step 4 (MVR): one canonical library store across modes (no migration).
        // This points all template browsing/apply to the same file going forward.
        self.effectsLibrarySession = EffectsSession(filename: "effects-library.json")
        self.recentEffectsStore = RecentEffectChainsStore()

        // Create the preview player state (single deck) + live display
        self.player = DreamPlayerState(config: state.settings.playerConfig, effectsSession: effectsLibrarySession)
        self.livePlayer = LivePlayer(settings: state.settings, effectsSession: effectsLibrarySession)

        // Wire RECENT store into all effect managers
        player.effectManager.recentStore = recentEffectsStore
        livePlayer.effectManager.recentStore = recentEffectsStore

        // Create audio controller (handles device selection, volume, persistence)
        self.audioController = DreamAudioController(settingsStore: state.settingsStore, livePlayer: livePlayer)

        // Forward player state changes to Dream's objectWillChange for SwiftUI reactivity
        player.objectWillChange
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
        player.$config
            .dropFirst() // Skip initial value
            .sink { [weak self] config in
                guard let self = self else { return }
                self.state.settingsStore.update { $0.playerConfig = config }
            }
            .store(in: &playerSubscriptions)

        // Set up watch timer callback
        state.onWatchTimerFired = { [weak self] in
            self?.new()
        }

        // Restore last recipe if available
        restorePersistedRecipe()

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

    /// Save the current recipe for persistence
    func saveCurrentRecipe() {
        var recipe = player.recipe
        recipe.effectsLibrarySnapshot = effectsSession.chains
        if !recipe.sources.isEmpty {
            state.settingsStore.update { $0.playerConfig.lastRecipe = recipe }
            print("📦 Saved recipe with \(recipe.sources.count) layer(s)")
        }

        // Force immediate synchronous save for app termination
        state.settingsStore.save(synchronous: true)
    }

    /// Restore persisted recipe (preview deck)
    private func restorePersistedRecipe() {
        if let persisted = state.settings.playerConfig.lastRecipe {
            var recipe = persisted
            recipe.ensureEffectChainNames()
            player.setRecipe(recipe)
            player.currentSourceIndex = -1
            player.effectManager.clearFrameBuffer()
            EffectChainLibraryActions.importChainsFromRecipe(recipe, into: player.effectsSession)
            player.notifyRecipeChanged()
            print("📦 Restored recipe with \(recipe.sources.count) layer(s)")
        } else {
            generateNewHypnogram(for: player)
        }
    }

    /// Build export settings on-demand with current player config
    private func exportSettings() -> CGSize {
        let outputSize = renderSize(
            aspectRatio: activePlayer.config.aspectRatio,
            maxDimension: activePlayer.config.playerResolution.maxDimension
        )
        return outputSize
    }

    // MARK: - Shared helpers

    private var sourceCount: Int { activePlayer.activeSourceCount }

    private var currentDisplayIndex: Int {
        sourceCount > 0 ? activePlayer.currentSourceIndex + 1 : 0
    }

    // MARK: - Hypnogram Generation

    /// Generate a new random hypnogram for the given player
    private func generateNewHypnogram(for player: DreamPlayerState) {
        player.resetForNextHypnogram(preserveGlobalEffect: true)

        let clipLengthMin = max(0.1, state.settings.clipLengthMinSeconds)
        let clipLengthMax = max(clipLengthMin, state.settings.clipLengthMaxSeconds)
        let clipLengthSeconds = Double.random(in: clipLengthMin...clipLengthMax)
        player.targetDuration = CMTime(seconds: clipLengthSeconds, preferredTimescale: 600)

        let total = max(1, player.config.maxLayers)
        let minCount = min(2, total)
        let count = Int.random(in: minCount...total)

        for i in 0..<max(1, count) {
            guard let clip = state.library.randomClip(clipLength: player.recipe.targetDuration.seconds) else {
                continue
            }
            let blendMode = (i == 0) ? BlendMode.sourceOver : BlendMode.defaultMontage
            let source = HypnogramSource(clip: clip, blendMode: blendMode)
            player.sources.append(source)
        }

        player.effectManager.invalidateBlendAnalysis()
        player.effectManager.onEffectChanged?()

        // Keep settings in sync so watch interval reflects the current clip length.
        // (This will be replaced by clip-tape persistence in Phase 2.)
        var persisted = player.recipe
        persisted.effectsLibrarySnapshot = effectsSession.chains
        state.settingsStore.update { $0.playerConfig.lastRecipe = persisted }
    }

    /// Add a source to the given player
    private func addSourceToPlayer(_ player: DreamPlayerState, length: Double? = nil) {
        // Use default clip length if not provided
        let clipLength = length ?? player.recipe.targetDuration.seconds
        guard let clip = state.library.randomClip(clipLength: clipLength) else { return }
        let blendMode = player.sources.isEmpty ? BlendMode.sourceOver : BlendMode.defaultMontage
        let source = HypnogramSource(clip: clip, blendMode: blendMode)
        player.sources.append(source)
        player.currentSourceIndex = player.sources.count - 1
    }

    // MARK: - Layer Navigation
    // Note: Flash solo is handled by NSEvent key hold detection in HypnographAppDelegate

    func nextSource() {
        activePlayer.nextSource()
    }

    func previousSource() {
        activePlayer.previousSource()
    }

    func selectSource(index: Int) {
        activePlayer.selectSource(index)
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
        if isLiveMode {
            return AnyView(
                LivePlayerScreen(livePlayer: livePlayer)
                    .id("dream-live-\(livePlayer.config.viewID)")
            )
        }

        if activePlayer.sources.isEmpty {
            generateNewHypnogram(for: activePlayer)
        }

        let recipe = makeDisplayRecipe()
        let player = activePlayer

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
            .id("dream-preview-\(player.config.viewID)-\(recipe.playRate)")
        )
    }

    /// The live recipe from the active player - use for direct access/mutation
    var currentRecipe: HypnogramRecipe {
        get { activePlayer.recipe }
        set { activePlayer.recipe = newValue }
    }

    /// Build a recipe snapshot for display/export (sets mode, timestamp, effects library snapshot)
    func makeDisplayRecipe() -> HypnogramRecipe {
        var recipe = activePlayer.recipe
        recipe.createdAt = Date()  // Set creation timestamp
        recipe.effectsLibrarySnapshot = effectsSession.chains  // Snapshot the entire effects library
        return recipe
    }

    // MARK: - Lifecycle

    func new() {
        // Clear frame buffer to prevent memory bloat from stored CIImages
        activePlayer.effectManager.clearFrameBuffer()

        // Clear image cache if it's getting large to prevent memory bloat
        let cacheSize = StillImageCache.cacheSize()
        if cacheSize.ciImages > 30 || cacheSize.cgImages > 30 {
            StillImageCache.clear()
        }

        generateNewHypnogram(for: player)
    }

    /// Send current hypnogram to live display
    func sendToLivePlayer() {
        livePlayer.send(
            recipe: activePlayer.recipe,
            config: activePlayer.config
        )
    }

    func toggleHUD() {
        state.windowState.toggle("hud")
    }

    func togglePause() {
        activePlayer.togglePause()
    }

    func addSource() {
        addSourceToPlayer(activePlayer)
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
            print("Dream: no sources to render.")
            return
        }

        // Deep copy recipe with fresh effect instances to avoid sharing state with preview
        let renderRecipe = activePlayer.recipe.copyForExport()

        // Create renderer with current settings (aspect ratio + resolution)
        let outputSize = exportSettings()

        print("Dream: enqueueing recipe with \(renderRecipe.sources.count) layer(s), duration: \(renderRecipe.targetDuration.seconds)s")

        // Enqueue immediately (don't defer - the renderer handles async internally)
        renderQueue.enqueue(
            recipe: renderRecipe,
            outputFolder: state.settings.outputURL,
            outputSize: outputSize
        )

        AppNotifications.show("Rendering video...", flash: true)

        // Reset for next hypnogram
        // Defer this to avoid modifying @Published during button action
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.generateNewHypnogram(for: self.player)
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

        // Ensure we're editing the preview deck
        liveMode = .edit

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
