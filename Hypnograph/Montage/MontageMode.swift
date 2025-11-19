import Foundation
import CoreGraphics
import Combine
import SwiftUI

/// Concrete HypnographMode backed by HypnogramState + Montage renderer semantics.
/// Holds any Montage-specific preview state (like solo).
final class MontageMode: ObservableObject, HypnographMode {

    /// Shared session state used by the Montage mode.
    /// This is the same instance that ContentView observes.
    private let state: HypnogramState

    /// Render queue + backend for this mode.
    let renderQueue: RenderQueue

    /// If set, preview only this layer (solo).
    /// `nil` = normal multi-layer preview.
    @Published private(set) var soloLayerIndex: Int? = nil

    init(state: HypnogramState) {
        self.state = state
        let backend = MontageRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize
        )
        self.renderQueue = RenderQueue(renderer: backend)
    }

    // Expose state bits if you need them (read-only)
    var currentLayerIndex: Int {
        state.currentLayerIndex
    }

    var currentBlendModeName: String {
        state.currentBlendModeName
    }

    // MARK: - Preview / solo

    func layersForDisplay() -> [HypnogramLayer] {
        if let solo = soloLayerIndex {
            let all = state.layers
            guard solo >= 0, solo < all.count else { return all }
            return [all[solo]]
        } else {
            return state.layers
        }
    }

    /// Solo the current layer (or clear solo if already soloed).
    func toggleSoloCurrentSource() {
        let idx = state.currentLayerIndex
        if soloLayerIndex == idx {
            soloLayerIndex = nil
        } else {
            soloLayerIndex = idx
        }
    }

    var isSoloActive: Bool {
        soloLayerIndex != nil
    }

    // MARK: - HypnographMode – display wiring

    func makeDisplayView(
        state: HypnogramState,
        renderQueue: RenderQueue
    ) -> AnyView {
        // We ignore parameters and use our captured state/queue,
        // assuming they’re the same instances.
        AnyView(
            MontageView(
                layers: layersForDisplay(),
                currentLayerTime: Binding(
                    get: { self.state.currentCandidateStartOverride },
                    set: { self.state.currentCandidateStartOverride = $0 }
                ),
                outputDuration: self.state.settings.outputDuration,
                outputSize: self.state.settings.outputSize
            )
        )
    }

    // MARK: - HypnographMode – engine behavior

    // Hypnogram lifecycle

    func newRandomHypnogram() {
        // Clear solo on new random set, feels saner.
        soloLayerIndex = nil
        state.newAutoPrimeSet()
    }

    func saveCurrentHypnogram() {
        guard let recipe = state.layersForRender() else {
            print("renderCurrentHypnogram(): no renderable hypnogram (no selected clips).")
            return
        }

        print("renderCurrentHypnogram(): enqueuing recipe with \(recipe.layers.count) layer(s).")
        renderQueue.enqueue(recipe: recipe)

        state.resetForNextHypnogram()

        // Keep solo off after saving; new set is full stack again.
        soloLayerIndex = nil

        if state.settings.autoPrime {
            state.newAutoPrimeSet()
        }
    }

    // Source navigation

    func nextSource() {
        state.nextLayer()
    }

    func previousSource() {
        state.prevLayer()
    }

    func selectSource(index: Int) {
        state.selectLayer(index: index)
    }

    // Candidate / selection

    func nextCandidate() {
        state.nextCandidate()
    }

    func acceptCandidate() {
        state.acceptCandidate()
    }

    func deleteCurrentSource() {
        state.handleEscape()
    }

    // Mode-specific tweaks

    func cycleEffect() {
        state.cycleBlendMode()
    }

    func toggleHUD() {
        state.toggleHUD()
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        // settings reload might change layer counts; safest is to clear solo
        soloLayerIndex = nil
    }
}
