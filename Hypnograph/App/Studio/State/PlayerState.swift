//
//  PlayerState.swift
//  Hypnograph
//
//  Playback-local state for the Studio preview deck.
//

import Foundation
import CoreMedia
import HypnoCore

@MainActor
final class PlayerState: ObservableObject {
    struct CompositionLoadFailure: Equatable {
        let compositionID: UUID
    }

    // MARK: - Playback State

    /// Current layer index for navigation (-1 = composition effect chain, 0+ = layer index)
    /// Defaults to composition scope so effects set via E key persist across new compositions.
    @Published var currentLayerIndex: Int = -1

    /// Optional playhead offset for scrubbing
    @Published var currentLayerTimeOffset: CMTime?

    /// Pause/play state
    @Published var isPaused: Bool = false

    /// Incremented when effects change - triggers re-render when paused
    @Published var effectsChangeCounter: Int = 0

    /// When true, composition effect chain is temporarily bypassed (e.g., while holding 0 key)
    @Published var isCompositionEffectSuspended: Bool = false

    /// True while the primary player is building/loading the current composition.
    @Published var isPrimaryCompositionLoadInFlight: Bool = false

    /// True while a manually generated "next" composition at the end of history
    /// is still unresolved and has not yet started transitioning in.
    var hasPendingGeneratedNextComposition: Bool = false

    /// Set when the current composition failed to resolve any playable sources.
    @Published var currentCompositionLoadFailure: CompositionLoadFailure?

    /// The composition that most recently presented a frame in the main preview.
    var currentRenderedCompositionID: UUID?
    /// Whether the current composition needs a fresh persisted preview after its next real render.
    var currentCompositionPreviewNeedsRefresh: Bool = true
    /// Used to ignore the immediate preview invalidation caused by writing preview metadata itself.
    var suppressNextPreviewInvalidation: Bool = false

    // MARK: - Player Configuration

    /// Per-player settings (aspect ratio, resolution, generation settings)
    @Published var config: PlayerConfiguration

    // MARK: - Effects Library

    /// This player's effects session - stores effect chains for this mode
    let effectsSession: EffectsSession

    // MARK: - Effect Processing

    /// This player's own effect manager - independent effects per deck
    let effectManager = EffectManager()
    private var compositionProvider: (() -> Composition?)?
    private var compositionEffectChainSetter: ((EffectChain) -> Void)?
    private var sourceEffectChainSetter: ((Int, EffectChain) -> Void)?
    private var blendModeSetter: ((Int, String) -> Void)?

    init(
        config: PlayerConfiguration,
        effectsSession: EffectsSession
    ) {
        self.config = config
        self.effectsSession = effectsSession

        setupEffectManager()
        setupEffectsSession()
    }

    private func setupEffectManager() {
        effectManager.session = effectsSession

        effectManager.onEffectChanged = { [weak self] in
            self?.effectsChangeCounter += 1
        }

        effectManager.compositionProvider = { [weak self] in
            self?.compositionProvider?()
        }

        effectManager.compositionEffectChainSetter = { [weak self] chain in
            self?.compositionEffectChainSetter?(chain)
        }

        effectManager.sourceEffectChainSetter = { [weak self] sourceIndex, chain in
            self?.sourceEffectChainSetter?(sourceIndex, chain)
        }

        effectManager.blendModeSetter = { [weak self] sourceIndex, blendMode in
            self?.blendModeSetter?(sourceIndex, blendMode)
        }
    }

    private func setupEffectsSession() {
        // Templates are applied explicitly; editing CURRENT flows through EffectManager recipe mutation APIs.
        effectsSession.onChainUpdated = nil
        effectsSession.onReloaded = nil
    }

    func configureDocumentBindings(
        compositionProvider: @escaping () -> Composition,
        setCompositionEffectChain: @escaping (EffectChain) -> Void,
        setSourceEffectChain: @escaping (Int, EffectChain) -> Void,
        setBlendMode: @escaping (Int, String) -> Void
    ) {
        self.compositionProvider = compositionProvider
        self.compositionEffectChainSetter = setCompositionEffectChain
        self.sourceEffectChainSetter = setSourceEffectChain
        self.blendModeSetter = setBlendMode
    }

    func togglePause() {
        isPaused.toggle()
    }
}
