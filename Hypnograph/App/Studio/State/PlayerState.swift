//
//  PlayerState.swift
//  Hypnograph
//
//  Independent player state for Studio module.
//  Holds the current session, effects, and settings for the in-app deck.
//

import Foundation
import CoreMedia
import Combine
import HypnoCore

/// Independent player state for the Studio in-app deck.
/// Maintains its own session, playback state, and generation settings.
@MainActor
final class PlayerState: ObservableObject {

    // MARK: - Session (the composition)

    /// The current hypnograph session - hypnograms, effects, duration
    @Published var session: HypnographSession

    /// The active hypnogram index in `session.hypnograms`
    @Published var currentHypnogramIndex: Int = 0

    /// Bumps when the session or any of its hypnograms are mutated.
    /// Use this for persistence triggers (mutating nested fields of a struct doesn't reliably publish).
    @Published private(set) var sessionRevision: Int = 0

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

    // MARK: - Session Properties (convenience accessors)

    /// The currently selected hypnogram (materialized).
    var currentHypnogram: Hypnogram {
        get {
            let index = max(0, min(currentHypnogramIndex, session.hypnograms.count - 1))
            return session.hypnograms[index]
        }
        set {
            let index = max(0, min(currentHypnogramIndex, session.hypnograms.count - 1))
            session.hypnograms[index] = newValue
            sessionRevision &+= 1
            objectWillChange.send()
        }
    }

    private func updateCurrentHypnogram(_ update: (inout Hypnogram) -> Void) {
        var hypnogram = currentHypnogram
        update(&hypnogram)
        currentHypnogram = hypnogram
    }

    /// Playback rate - reads/writes directly to the current hypnogram
    var playRate: Float {
        get { currentHypnogram.playRate }
        set {
            updateCurrentHypnogram { $0.playRate = newValue }
        }
    }

    /// Target duration - reads/writes directly to the current hypnogram
    var targetDuration: CMTime {
        get { currentHypnogram.targetDuration }
        set {
            updateCurrentHypnogram { $0.targetDuration = newValue }
        }
    }

    // MARK: - Init

    init(config: PlayerConfiguration, effectsSession: EffectsSession) {
        self.config = config
        // Session starts with defaults; restored from clip history on app launch.
        self.session = HypnographSession(
            layers: [],
            targetDuration: CMTime(seconds: 15, preferredTimescale: 600),
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
        effectManager.clipProvider = { [weak self] in
            self?.currentHypnogram
        }

        // Global effect chain setter
        effectManager.globalEffectChainSetter = { [weak self] chain in
            self?.updateCurrentHypnogram { $0.effectChain = chain }
        }

        // Source effect chain setter
        effectManager.sourceEffectChainSetter = { [weak self] sourceIndex, chain in
            guard let self else { return }
            self.updateCurrentHypnogram { hypnogram in
                guard sourceIndex < hypnogram.layers.count else { return }
                hypnogram.layers[sourceIndex].effectChain = chain
            }
        }

        // Blend mode setter (getter is via recipeProvider reading source.blendMode)
        effectManager.blendModeSetter = { [weak self] sourceIndex, blendMode in
            guard let self else { return }
            self.updateCurrentHypnogram { hypnogram in
                guard sourceIndex < hypnogram.layers.count else { return }
                hypnogram.layers[sourceIndex].blendMode = blendMode
            }
        }
    }

    private func setupEffectsSession() {
        // Step 2 (MVR): template updates should not overwrite CURRENT (recipe) by name.
        // Templates are applied explicitly; editing CURRENT flows through EffectManager recipe mutation APIs.
        effectsSession.onChainUpdated = nil
        effectsSession.onReloaded = nil
    }

    // MARK: - Session Management

    /// Replace the entire session (used when loading from file)
    func setSession(_ newSession: HypnographSession) {
        session = newSession
        currentHypnogramIndex = 0
        sessionRevision &+= 1
    }

    /// Notify that session has changed (triggers re-render)
    func notifySessionChanged() {
        effectsChangeCounter += 1
    }

    /// Notify that session has changed (triggers persistence).
    func notifySessionMutated() {
        sessionRevision &+= 1
    }

    // MARK: - Convenience Accessors

    var layers: [HypnogramLayer] {
        get { currentHypnogram.layers }
        set { updateCurrentHypnogram { $0.layers = newValue } }
    }

    var effectChain: EffectChain {
        get { currentHypnogram.effectChain }
        set { updateCurrentHypnogram { $0.effectChain = newValue } }
    }
    
    var activeLayerCount: Int { layers.count }
    
    var currentLayer: HypnogramLayer? {
        guard currentSourceIndex >= 0, currentSourceIndex < layers.count else { return nil }
        return layers[currentSourceIndex]
    }
    
    var currentMediaClip: MediaClip? {
        currentLayer?.mediaClip
    }

    // MARK: - Navigation

    func nextSource() {
        guard !layers.isEmpty else { return }
        currentSourceIndex = (currentSourceIndex + 1) % layers.count
    }

    func previousSource() {
        guard !layers.isEmpty else { return }
        currentSourceIndex = currentSourceIndex > 0 ? currentSourceIndex - 1 : layers.count - 1
    }

    func selectSource(_ index: Int) {
        guard index >= -1, index < layers.count else { return }
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

    /// Ensure `currentSourceIndex` is valid for the current clip.
    func clampCurrentSourceIndex() {
        if currentSourceIndex == -1 { return }
        let maxIndex = layers.count - 1
        if maxIndex < 0 {
            currentSourceIndex = -1
            return
        }
        if currentSourceIndex > maxIndex {
            currentSourceIndex = maxIndex
        }
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
        let savedEffectChain = preserveGlobalEffect ? currentHypnogram.effectChain.clone() : nil

        updateCurrentHypnogram { hypnogram in
            hypnogram.layers.removeAll()
            hypnogram.effectChain = EffectChain()
        }
        currentSourceIndex = -1  // Reset to global layer
        currentClipTimeOffset = nil

        // Restore effect chain (it will lazily re-instantiate effects when apply() is called)
        if preserveGlobalEffect, let chain = savedEffectChain {
            updateCurrentHypnogram { $0.effectChain = chain }
        }
    }

    /// Display string for current editing layer
    var editingLayerDisplay: String {
        if isOnGlobalLayer {
            return "Layer: Global"
        } else {
            return "Layer: Source \(currentSourceIndex + 1)/\(layers.count)"
        }
    }
}
