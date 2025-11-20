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

    /// Returns layers for display along with their original indices
    private func layersForDisplay(using state: HypnogramState) -> (layers: [HypnogramLayer], sourceIndices: [Int]) {
        let all = state.layers

        if let solo = soloLayerIndex {
            guard solo >= 0, solo < all.count else {
                return (all, Array(0..<all.count))
            }
            // Solo mode: return only the soloed layer with its original index
            return ([all[solo]], [solo])
        } else {
            // Normal mode: all layers with sequential indices
            return (all, Array(0..<all.count))
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
        let (layers, sourceIndices) = layersForDisplay(using: state)
        return AnyView(
            MontageView(
                layers: layers,
                sourceIndices: sourceIndices,
                currentLayerTime: Binding(
                    get: { state.currentCandidateStartOverride },
                    set: { state.currentCandidateStartOverride = $0 }
                ),
                outputDuration: state.settings.outputDuration,
                outputSize: state.settings.outputSize
            )
        )
    }

    func hudItems(
        state: HypnogramState,
        renderQueue: RenderQueue
    ) -> [HUDItem] {
        var items: [HUDItem] = [
            // Source/Layer-specific status (order 25-29 range)
            .text("Source \(state.currentLayerIndex + 1) of \(state.maxLayers)", order: 25),
            .text("Blend mode: \(state.currentBlendModeName)", order: 26),
            .text("Source Effect: \(sourceEffectName)", order: 27),
        ]

        // Show solo status if active
        if isSoloActive {
            items.append(.text("SOLO: Source \(soloLayerIndex! + 1)", order: 28, font: .headline))
        }

        // Mode-specific shortcuts (after global shortcuts)
        // Global shortcuts are shown by the app, only show Montage-specific ones here
        items.append(.text("M = Cycle Blend mode", order: 46))
        items.append(.text("S = Toggle solo current source", order: 47))
        items.append(.text("1-5 = Toggle solo source", order: 48))

        return items
    }

    func modeCommands() -> [ModeCommand] {
        // Only Montage-specific commands
        // Global commands (navigation, candidates, etc.) are in HypnographApp
        return [
            ModeCommand(title: "Cycle Blend Mode", key: "m") { [weak self] in
                self?.cycleEffect()
            },
            ModeCommand(title: "Solo Current Source", key: "s") { [weak self] in
                self?.toggleSolo()
            },
            // 1-5 keys: Toggle solo for that source
            ModeCommand(title: "Toggle Solo Source 1", key: "1") { [weak self] in
                self?.toggleSoloForSource(index: 0)
            },
            ModeCommand(title: "Toggle Solo Source 2", key: "2") { [weak self] in
                self?.toggleSoloForSource(index: 1)
            },
            ModeCommand(title: "Toggle Solo Source 3", key: "3") { [weak self] in
                self?.toggleSoloForSource(index: 2)
            },
            ModeCommand(title: "Toggle Solo Source 4", key: "4") { [weak self] in
                self?.toggleSoloForSource(index: 3)
            },
            ModeCommand(title: "Toggle Solo Source 5", key: "5") { [weak self] in
                self?.toggleSoloForSource(index: 4)
            }
        ]
    }

    /// Toggle solo for a specific source index
    private func toggleSoloForSource(index: Int) {
        // Check if this source is already soloed BEFORE selecting
        // (selectSource clears solo, so we need to check first)
        let wasAlreadySoloed = (soloLayerIndex == index)

        // Select the source (this will clear solo)
        selectSource(index: index)

        // Toggle solo: if it was already soloed, leave it off; otherwise turn it on
        if !wasAlreadySoloed {
            soloLayerIndex = index
        }
        // If wasAlreadySoloed is true, solo stays nil (turned off by selectSource)
    }

    // MARK: - HypnographMode – engine behavior

    func newRandomHypnogram() {
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

        soloLayerIndex = nil

        if state.settings.autoPrime {
            state.newAutoPrimeSet()
        }
    }

    // Source navigation

    func nextSource() {
        soloLayerIndex = nil // Clear solo when switching layers
        state.nextLayer()
    }

    func previousSource() {
        soloLayerIndex = nil // Clear solo when switching layers
        state.prevLayer()
    }

    func selectSource(index: Int) {
        soloLayerIndex = nil // Clear solo when switching layers
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

    func toggleSolo() {
        toggleSoloCurrentSource()
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        soloLayerIndex = nil
    }

    // MARK: - Effects

    func cycleGlobalEffect() {
        state.renderHooks.cycleGlobalEffect()
    }

    func cycleSourceEffect() {
        state.renderHooks.cycleSourceEffect(for: state.currentLayerIndex)
    }

    func clearAllEffects() {
        // Clear global effect
        state.renderHooks.setGlobalEffect(nil)

        // Clear all per-source effects
        for i in 0..<state.maxLayers {
            state.renderHooks.setSourceEffect(nil, for: i)
        }

        // Montage-specific: also clear solo mode
        soloLayerIndex = nil
    }

    var globalEffectName: String {
        state.renderHooks.globalEffectName
    }

    var sourceEffectName: String {
        state.renderHooks.sourceEffectName(for: state.currentLayerIndex)
    }
}
