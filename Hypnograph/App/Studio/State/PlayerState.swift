//
//  PlayerState.swift
//  Hypnograph
//
//  Independent player state for Studio module.
//  Holds the current hypnogram, effects, and settings for the in-app deck.
//

import Foundation
import CoreMedia
import Combine
import HypnoCore

/// Independent player state for the Studio in-app deck.
/// Maintains its own hypnogram, playback state, and generation settings.
@MainActor
final class PlayerState: ObservableObject {

    // MARK: - Hypnogram

    /// The current hypnogram document - compositions, effects, duration
    @Published var hypnogram: Hypnogram

    /// The active composition index in `hypnogram.compositions`
    @Published var currentCompositionIndex: Int = 0

    /// Bumps when the hypnogram or any of its compositions are mutated.
    /// Use this for persistence triggers (mutating nested fields of a struct doesn't reliably publish).
    @Published private(set) var hypnogramRevision: Int = 0

    // MARK: - Playback State

    /// Current layer index for navigation (-1 = composition effect chain, 0+ = layer index)
    /// Defaults to composition scope so effects set via E key persist across new compositions.
    @Published var currentLayerIndex: Int = -1

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

    // MARK: - Hypnogram Properties

    /// The currently selected composition.
    var currentComposition: Composition {
        get {
            let index = max(0, min(currentCompositionIndex, hypnogram.compositions.count - 1))
            var composition = hypnogram.compositions[index]
            composition.syncTargetDurationToLayers()
            return composition
        }
        set {
            let index = max(0, min(currentCompositionIndex, hypnogram.compositions.count - 1))
            var normalized = newValue
            normalized.syncTargetDurationToLayers()
            hypnogram.compositions[index] = normalized
            hypnogramRevision &+= 1
            objectWillChange.send()
        }
    }

    private func updateCurrentComposition(_ update: (inout Composition) -> Void) {
        var composition = currentComposition
        update(&composition)
        currentComposition = composition
    }

    /// Playback rate - reads/writes directly to the current composition
    var playRate: Float {
        get { currentComposition.playRate }
        set {
            updateCurrentComposition { $0.playRate = newValue }
        }
    }

    /// Target duration - reads/writes directly to the current composition
    var targetDuration: CMTime {
        get { currentComposition.effectiveDuration }
        set {
            updateCurrentComposition { $0.targetDuration = newValue }
        }
    }

    // MARK: - Init

    init(config: PlayerConfiguration, effectsSession: EffectsSession) {
        self.config = config
        // Hypnogram starts with defaults; restored from composition history on app launch.
        self.hypnogram = Hypnogram(
            compositions: [
                Composition(
                    layers: [],
                    targetDuration: CMTime(seconds: 15, preferredTimescale: 600),
                    playRate: 1.0
                )
            ]
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
        effectManager.compositionProvider = { [weak self] in
            self?.currentComposition
        }

        // Global effect chain setter
        effectManager.globalEffectChainSetter = { [weak self] chain in
            self?.updateCurrentComposition { $0.effectChain = chain }
        }

        // Source effect chain setter
        effectManager.sourceEffectChainSetter = { [weak self] sourceIndex, chain in
            guard let self else { return }
            self.updateCurrentComposition { composition in
                guard sourceIndex < composition.layers.count else { return }
                composition.layers[sourceIndex].effectChain = chain
            }
        }

        // Blend mode setter (getter is via recipeProvider reading source.blendMode)
        effectManager.blendModeSetter = { [weak self] sourceIndex, blendMode in
            guard let self else { return }
            self.updateCurrentComposition { composition in
                guard sourceIndex < composition.layers.count else { return }
                composition.layers[sourceIndex].blendMode = blendMode
            }
        }
    }

    private func setupEffectsSession() {
        // Step 2 (MVR): template updates should not overwrite CURRENT (recipe) by name.
        // Templates are applied explicitly; editing CURRENT flows through EffectManager recipe mutation APIs.
        effectsSession.onChainUpdated = nil
        effectsSession.onReloaded = nil
    }

    // MARK: - Hypnogram Management

    /// Replace the entire hypnogram (used when loading from file)
    func setHypnogram(_ newSession: Hypnogram) {
        var normalizedSession = newSession
        for index in normalizedSession.compositions.indices {
            normalizedSession.compositions[index].syncTargetDurationToLayers()
        }
        hypnogram = normalizedSession
        currentCompositionIndex = 0
        hypnogramRevision &+= 1
    }

    /// Notify that the hypnogram has changed (triggers re-render)
    func notifyHypnogramChanged() {
        effectsChangeCounter += 1
    }

    /// Notify that the hypnogram has changed (triggers persistence).
    func notifyHypnogramMutated() {
        for index in hypnogram.compositions.indices {
            hypnogram.compositions[index].syncTargetDurationToLayers()
        }
        hypnogramRevision &+= 1
    }

    // MARK: - Convenience Accessors

    var layers: [Layer] {
        get { currentComposition.layers }
        set { updateCurrentComposition { $0.layers = newValue } }
    }

    var effectChain: EffectChain {
        get { currentComposition.effectChain }
        set { updateCurrentComposition { $0.effectChain = newValue } }
    }
    
    var activeLayerCount: Int { layers.count }
    
    var currentLayer: Layer? {
        guard currentLayerIndex >= 0, currentLayerIndex < layers.count else { return nil }
        return layers[currentLayerIndex]
    }
    
    var currentMediaClip: MediaClip? {
        currentLayer?.mediaClip
    }

    // MARK: - Navigation

    func nextSource() {
        guard !layers.isEmpty else { return }
        currentLayerIndex = (currentLayerIndex + 1) % layers.count
    }

    func previousSource() {
        guard !layers.isEmpty else { return }
        currentLayerIndex = currentLayerIndex > 0 ? currentLayerIndex - 1 : layers.count - 1
    }

    func selectSource(_ index: Int) {
        guard index >= -1, index < layers.count else { return }
        currentLayerIndex = index
    }

    /// Whether we're on the global layer (-1) vs a specific source
    var isOnGlobalLayer: Bool {
        currentLayerIndex == -1
    }

    /// Move to global layer
    func selectGlobalLayer() {
        currentLayerIndex = -1
    }

    /// Ensure `currentLayerIndex` is valid for the current clip.
    func clampCurrentSourceIndex() {
        if currentLayerIndex == -1 { return }
        let maxIndex = layers.count - 1
        if maxIndex < 0 {
            currentLayerIndex = -1
            return
        }
        if currentLayerIndex > maxIndex {
            currentLayerIndex = maxIndex
        }
    }

    // MARK: - Playback Control

    func togglePause() {
        isPaused.toggle()
    }

    // MARK: - Recipe Management

    /// Reset for the next composition, optionally preserving composition-level effects.
    func resetForNextComposition(preserveGlobalEffect: Bool = true) {
        effectManager.clearFrameBuffer()

        // Save the effect chain (source of truth) before clearing
        let savedEffectChain = preserveGlobalEffect ? currentComposition.effectChain.clone() : nil

        updateCurrentComposition { composition in
            composition.layers.removeAll()
            composition.effectChain = EffectChain()
        }
        currentLayerIndex = -1  // Reset to composition-level effect chain
        currentClipTimeOffset = nil

        // Restore effect chain (it will lazily re-instantiate effects when apply() is called)
        if preserveGlobalEffect, let chain = savedEffectChain {
            updateCurrentComposition { $0.effectChain = chain }
        }
    }

    /// Display string for current editing layer
    var editingLayerDisplay: String {
        if isOnGlobalLayer {
            return "Composition"
        } else {
            return "Layer \(currentLayerIndex + 1)/\(layers.count)"
        }
    }
}
