//
//  DreamPlayerState.swift
//  Hypnograph
//
//  Independent player state for Dream module.
//  Holds the current recipe, effects, and settings for the preview deck.
//

import Foundation
import CoreMedia
import Combine
import HypnoCore

/// Independent player state for the Dream preview deck.
/// Maintains its own recipe, playback state, and generation settings.
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

    /// When true, global effect chain is temporarily bypassed (e.g., while holding 0 key)
    @Published var isGlobalEffectSuspended: Bool = false

    // MARK: - Player Configuration

    /// Per-player settings (aspect ratio, resolution, generation settings)
    @Published var config: PlayerConfiguration

    // MARK: - Effects Library

    /// This player's effects session - stores effect chains for this mode
    let effectsSession: EffectsSession

    // MARK: - Effect Processing

    /// This player's own effect manager - independent effects per deck
    let effectManager = EffectManager()

    // MARK: - Recipe Properties (convenience accessors)

    /// Playback rate - reads/writes directly to recipe
    var playRate: Float {
        get { recipe.playRate }
        set {
            recipe.playRate = newValue
            objectWillChange.send()
        }
    }

    /// Target duration - reads/writes directly to recipe
    var targetDuration: CMTime {
        get { recipe.targetDuration }
        set {
            recipe.targetDuration = newValue
            objectWillChange.send()
        }
    }

    // MARK: - Init

    init(config: PlayerConfiguration, effectsSession: EffectsSession) {
        self.config = config
        // Recipe starts with defaults; restored from lastRecipe on app launch
        self.recipe = HypnogramRecipe(
            sources: [],
            targetDuration: CMTime(seconds: 60, preferredTimescale: 600),
            playRate: 1.0
        )
        self.effectsSession = effectsSession

        setupEffectManager()
        setupEffectsSession()
    }

    private func setupEffectManager() {
        // Wire up the effects session for chain lookups
        effectManager.session = effectsSession

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

    private func setupEffectsSession() {
        // Step 2 (MVR): template updates should not overwrite CURRENT (recipe) by name.
        // Templates are applied explicitly; editing CURRENT flows through EffectManager recipe mutation APIs.
        effectsSession.onChainUpdated = nil
        effectsSession.onReloaded = nil
    }

    // MARK: - Recipe Management

    /// Replace the entire recipe (used when loading from file)
    func setRecipe(_ newRecipe: HypnogramRecipe) {
        recipe = newRecipe
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

    // MARK: - Recipe Management

    /// Reset for next hypnogram, optionally preserving global effects
    func resetForNextHypnogram(preserveGlobalEffect: Bool = true) {
        effectManager.clearFrameBuffer()

        // Save the effect chain (source of truth) before clearing
        let savedEffectChain = preserveGlobalEffect ? recipe.effectChain.clone() : nil

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
