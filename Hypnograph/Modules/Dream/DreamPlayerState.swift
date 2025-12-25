//
//  DreamPlayerState.swift
//  Hypnograph
//
//  Independent player state for Dream module.
//  Each player (montage, sequence) has its own recipe, effects, and settings.
//

import Foundation
import CoreMedia
import Combine

/// Independent player state for a Dream deck (montage or sequence).
/// Each player maintains its own recipe, playback state, and generation settings.
@MainActor
final class DreamPlayerState: ObservableObject {
    
    // MARK: - Recipe (the composition)
    
    /// The current hypnogram recipe - sources, effects, duration
    @Published var recipe: HypnogramRecipe
    
    // MARK: - Playback State
    
    /// Current source index for navigation (-1 = global layer, 0+ = source index)
    /// Defaults to global layer so effects set via E key persist across new hypnograms
    @Published var currentSourceIndex: Int = -1
    
    /// Optional playhead offset for scrubbing
    @Published var currentClipTimeOffset: CMTime?
    
    /// Pause/play state
    @Published var isPaused: Bool = false

    /// Incremented when effects change - triggers re-render when paused
    @Published var effectsChangeCounter: Int = 0
    
    // MARK: - Display Settings
    
    /// Aspect ratio for this player
    @Published var aspectRatio: AspectRatio
    
    /// Output resolution
    @Published var outputResolution: OutputResolution
    
    // MARK: - Generation Settings (for "New" operations)

    /// Max sources when generating new random hypnograms
    @Published var maxSourcesForNew: Int

    /// Target duration for new hypnograms
    @Published var targetDuration: CMTime

    // MARK: - UI State

    @Published var isHUDVisible: Bool = false
    @Published var isEffectsEditorVisible: Bool = false
    @Published var isPlayerSettingsVisible: Bool = false
    
    // MARK: - Effect Processing

    /// This player's own effect manager - independent effects per deck
    let effectManager = EffectManager()

    // MARK: - Computed Properties

    /// Playback rate - stored in recipe so it's part of the hypnogram
    var playRate: Float {
        get { recipe.playRate }
        set {
            recipe.playRate = newValue
            objectWillChange.send()
        }
    }

    // MARK: - Init
    
    init(settings: Settings) {
        self.recipe = HypnogramRecipe(
            sources: [],
            targetDuration: settings.outputDuration
        )
        self.aspectRatio = settings.aspectRatio
        self.outputResolution = settings.outputResolution
        self.maxSourcesForNew = settings.maxSourcesForNew
        self.targetDuration = settings.outputDuration
        
        setupEffectManager()
    }
    
    private func setupEffectManager() {
        // Increment counter when effects change
        effectManager.onEffectChanged = { [weak self] in
            self?.effectsChangeCounter += 1
        }
        
        // Recipe provider
        effectManager.recipeProvider = { [weak self] in
            self?.recipe
        }

        // Global effect chain setter
        effectManager.globalEffectChainSetter = { [weak self] chain in
            self?.recipe.effectChain = chain
        }

        // Source effect chain setter
        effectManager.sourceEffectChainSetter = { [weak self] sourceIndex, chain in
            guard let self = self, sourceIndex < self.recipe.sources.count else { return }
            self.recipe.sources[sourceIndex].effectChain = chain
        }

        // Blend mode setter (getter is via recipeProvider reading source.blendMode)
        effectManager.blendModeSetter = { [weak self] sourceIndex, blendMode in
            guard let self = self, sourceIndex < self.recipe.sources.count else { return }
            self.recipe.sources[sourceIndex].blendMode = blendMode
        }
    }

    // MARK: - Recipe Management

    /// Replace the entire recipe (used when loading from file)
    func setRecipe(_ newRecipe: HypnogramRecipe) {
        recipe = newRecipe
        targetDuration = newRecipe.targetDuration
    }

    /// Notify that recipe has changed (triggers re-render)
    func notifyRecipeChanged() {
        effectsChangeCounter += 1
    }

    // MARK: - Convenience Accessors

    var sources: [HypnogramSource] {
        get { recipe.sources }
        set { recipe.sources = newValue }
    }

    var effectChain: EffectChain {
        get { recipe.effectChain }
        set { recipe.effectChain = newValue }
    }
    
    var activeSourceCount: Int { sources.count }
    
    var currentSource: HypnogramSource? {
        guard currentSourceIndex >= 0, currentSourceIndex < sources.count else { return nil }
        return sources[currentSourceIndex]
    }
    
    var currentClip: VideoClip? {
        currentSource?.clip
    }

    // MARK: - Navigation

    func nextSource() {
        guard !sources.isEmpty else { return }
        currentSourceIndex = (currentSourceIndex + 1) % sources.count
    }

    func previousSource() {
        guard !sources.isEmpty else { return }
        currentSourceIndex = currentSourceIndex > 0 ? currentSourceIndex - 1 : sources.count - 1
    }

    func selectSource(_ index: Int) {
        guard index >= -1, index < sources.count else { return }
        currentSourceIndex = index
    }

    /// Whether we're on the global layer (-1) vs a specific source
    var isOnGlobalLayer: Bool {
        currentSourceIndex == -1
    }

    /// Move to global layer
    func selectGlobalLayer() {
        currentSourceIndex = -1
    }

    // MARK: - Playback Control

    func togglePause() {
        isPaused.toggle()
    }

    func toggleHUD() {
        isHUDVisible.toggle()
    }

    func toggleEffectsEditor() {
        isEffectsEditorVisible.toggle()
    }

    // MARK: - Recipe Management

    /// Reset for next hypnogram, optionally preserving global effects
    func resetForNextHypnogram(preserveGlobalEffect: Bool = true) {
        effectManager.clearFrameBuffer()

        // Save the effect chain (source of truth) before clearing
        let savedEffectChain = preserveGlobalEffect ? recipe.effectChain.copy() : nil

        sources.removeAll()
        recipe.effectChain = EffectChain()
        currentSourceIndex = -1  // Reset to global layer
        currentClipTimeOffset = nil

        // Restore effect chain (it will lazily re-instantiate effects when apply() is called)
        if preserveGlobalEffect, let chain = savedEffectChain {
            recipe.effectChain = chain
        }
    }

    /// Display string for current editing layer
    var editingLayerDisplay: String {
        if isOnGlobalLayer {
            return "Layer: Global"
        } else {
            return "Layer: Source \(currentSourceIndex + 1)/\(sources.count)"
        }
    }
}

