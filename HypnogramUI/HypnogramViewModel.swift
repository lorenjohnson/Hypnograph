//
//  HypnogramViewModel.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import Combine
import AVFoundation

/// ViewModel that bridges the SwiftUI layer with the Hypnogram core:
/// - Owns a HypnogramState (selection logic)
/// - Owns a RenderQueue (render jobs)
/// - Exposes simple intent methods for key commands (Space, Return, M, R).
final class HypnogramViewModel: ObservableObject {
    @Published private(set) var state: HypnogramState
    @Published var currentCandidateStartOverride: CMTime?

    let renderQueue: RenderQueue

    init(config: HypnogramConfig, renderQueue: RenderQueue) {
        self.state = HypnogramState(config: config)
        self.renderQueue = renderQueue
    }

    // MARK: - Intents driven by key commands

    /// SPACE: advance to the next random candidate for the current layer.
    func nextCandidate() {
        currentCandidateStartOverride = nil
        _ = state.nextCandidateForCurrentLayer()
        objectWillChange.send()
    }

    /// RETURN: accept the current candidate for this layer, possibly advancing to the next layer.
    func acceptCandidate() {
        state.acceptCandidateForCurrentLayer(usingStartTime: currentCandidateStartOverride)
        currentCandidateStartOverride = nil
        objectWillChange.send()
    }

    /// M: cycle the blend mode for the current layer.
    func cycleBlendMode() {
        state.cycleBlendModeForCurrentLayer()
        objectWillChange.send()
    }

    /// R: if all layers have selected clips, enqueue a recipe for rendering
    /// and reset the state for the next hypnogram.
    func renderCurrentHypnogram() {
        guard let recipe = state.currentRecipe() else {
            print("Hypnogram not complete yet; cannot render.")
            return
        }

        renderQueue.enqueue(recipe: recipe)
        state.resetForNextHypnogram()
        objectWillChange.send()
    }

    // MARK: - Convenience accessors for the UI

    var currentLayerIndex: Int {
        state.currentLayer
    }

    var maxLayers: Int {
        state.maxLayers
    }

    var currentBlendModeName: String {
        state.currentBlendMode.name
    }

    var currentCandidateClip: VideoClip? {
        let idx = state.currentLayer
        guard idx >= 0 && idx < state.candidateClips.count else { return nil }
        return state.candidateClips[idx]
    }
    
    var previewLayers: [HypnogramLayer] {
        state.previewLayers()
    }
    
    func handleEscape() {
        if state.currentLayer > 0 {
            // Step back one layer, preserving its selection as candidate.
            state.goBackOneLayer()
            currentCandidateStartOverride = nil
            objectWillChange.send()
        } else {
            // On the first layer: quit after the render queue is empty.
            // renderQueue.requestTerminateWhenDone()
        }
    }
}
