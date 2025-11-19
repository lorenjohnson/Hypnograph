//
//  MontageMode.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//


import Foundation
import CoreGraphics

/// Concrete HypnographMode backed by HypnogramState + Montage renderer semantics.
final class MontageMode: HypnographMode {

    /// Shared session state used by the Montage mode.
    /// This is the same instance that ContentView observes.
    private let state: HypnogramState

    init(state: HypnogramState) {
        self.state = state
    }

    // MARK: - HypnographMode

    var outputSize: CGSize {
        state.outputSize
    }

    // MARK: Hypnogram lifecycle

    func newRandomHypnogram() {
        state.newAutoPrimeSet()
    }

    func saveCurrentHypnogram(using queue: RenderQueue) {
        guard let recipe = state.layersForRender() else {
            print("renderCurrentHypnogram(): no renderable hypnogram (no selected clips).")
            return
        }

        print("renderCurrentHypnogram(): enqueuing recipe with \(recipe.layers.count) layer(s).")
        queue.enqueue(recipe: recipe)

        state.resetForNextHypnogram()

        if state.settings.autoPrime {
            state.newAutoPrimeSet()
        }
    }

    // MARK: Source navigation

    func nextSource() {
        // "Source" == layer in Montage mode
        state.nextLayer()
    }

    func previousSource() {
        state.prevLayer()
    }

    func selectSource(index: Int) {
        state.selectLayer(index: index)
    }

    // MARK: Candidate / selection

    func nextCandidate() {
        state.nextCandidate()
    }

    func acceptCandidate() {
        state.acceptCandidate()
    }

    func deleteCurrentSource() {
        state.handleEscape()
    }

    // MARK: Mode-specific tweaks

    func cycleEffect() {
        state.cycleBlendMode()
    }

    func toggleHUD() {
        state.toggleHUD()
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
    }
}
