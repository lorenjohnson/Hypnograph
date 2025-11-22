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

    /// If set, preview only this source (solo).
    /// `nil` = normal multi-source preview.
    @Published private(set) var soloLayerIndex: Int? = nil
    private var persistentSoloIndex: Int? = nil
    private var soloPulseWorkItem: DispatchWorkItem?

    init(state: HypnogramState) {
        self.state = state
        let backend = MontageRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize
        )
        self.renderQueue = RenderQueue(renderer: backend)
    }

    // Expose state bits if you need them (read-only)
    var currentSourceIndex: Int {
        state.currentSourceIndex
    }

    var currentBlendModeName: String {
        state.currentBlendModeName
    }

    var isSoloActive: Bool {
        soloLayerIndex != nil
    }

    var soloIndicatorText: String? {
        if let solo = soloLayerIndex {
            return "SOLO \(solo + 1)"
        } else {
            return "\(currentSourceIndex + 1)"
        }
    }

    // MARK: - Preview / solo

    /// Returns sources for display along with their original indices
    private func sourcesForDisplay(using state: HypnogramState) -> (sources: [HypnogramSource], sourceIndices: [Int]) {
        let all = state.sources

        if let solo = soloLayerIndex {
            guard solo >= 0, solo < all.count else {
                return (all, Array(0..<all.count))
            }
            // Solo mode: return only the soloed source with its original index
            return ([all[solo]], [solo])
        } else {
            // Normal mode: all sources with sequential indices
            return (all, Array(0..<all.count))
        }
    }

    /// Solo the current source (or clear solo if already soloed).
    func toggleSoloCurrentSource() {
        let idx = state.currentSourceIndex
        if persistentSoloIndex == idx {
            persistentSoloIndex = nil
        } else {
            persistentSoloIndex = idx
        }
        soloPulseWorkItem?.cancel()
        soloLayerIndex = persistentSoloIndex
    }

    // MARK: - HypnographMode – display wiring

    func makeDisplayView(
        state: HypnogramState,
        renderQueue: RenderQueue
    ) -> AnyView {
        let (sources, sourceIndices) = sourcesForDisplay(using: state)
        return AnyView(
            MontageView(
                sources: sources,
                sourceIndices: sourceIndices,
                currentSourceTime: Binding(
                    get: { state.currentClipTimeOffset },
                    set: { state.currentClipTimeOffset = $0 }
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
            .text("Source \(state.currentSourceIndex + 1) of \(state.activeSourceCount)", order: 25),
            .text("Blend mode (M): \(state.currentBlendModeName)", order: 26),
            .text("Source Effect (F): \(sourceEffectName)", order: 27),
        ]

        // Mode-specific shortcuts (after global shortcuts)
        // Global shortcuts are shown by the app, only show Montage-specific ones here
        items.append(.text("M = Cycle Blend mode", order: 46))

        return items
    }

    func compositionCommands() -> [ModeCommand] {
        return []
    }

    func sourceCommands() -> [ModeCommand] {
        return [
            ModeCommand(title: "Cycle Blend Mode", key: "m") { [weak self] in
                self?.cycleEffect()
            }
        ]
    }

    func selectOrToggleSolo(index: Int) {
        // Number keys: only momentary solo pulse, never latch persistent solo.
        selectSource(index: index)
    }

    // MARK: - HypnographMode – engine behavior

    func new() {
        soloLayerIndex = nil
        persistentSoloIndex = nil
        state.newAutoPrimeSet()
    }

    func addSource() {
        let activeCount = state.activeSourceCount
        guard activeCount < state.maxSources else { return }

        state.selectSource(index: activeCount)
        _ = state.nextCandidateForCurrentSource()
        soloLayerIndex = nil
        persistentSoloIndex = nil
    }

    func save() {
        guard let recipe = state.sourcesForRender() else {
            print("renderCurrentHypnogram(): no renderable hypnogram (no selected clips).")
            return
        }

        print("renderCurrentHypnogram(): enqueuing recipe with \(recipe.sources.count) source(s).")
        renderQueue.enqueue(recipe: recipe)

        state.resetForNextHypnogram()

        soloLayerIndex = nil

        if state.settings.autoPrime {
            state.newAutoPrimeSet()
        }
    }

    // Source navigation

    func nextSource() {
        let activeCount = state.activeSourceCount
        guard activeCount > 0 else { return }
        let nextIndex = min(activeCount - 1, state.currentSourceIndex + 1)
        selectSource(index: nextIndex, pulse: true)
    }

    func previousSource() {
        let activeCount = state.activeSourceCount
        guard activeCount > 0 else { return }
        let prevIndex = max(0, state.currentSourceIndex - 1)
        selectSource(index: prevIndex, pulse: true)
    }

    func selectSource(index: Int) {
        let activeCount = state.activeSourceCount
        guard activeCount > 0 else { return }
        let clamped = max(0, min(activeCount - 1, index))
        selectSource(index: clamped, pulse: true)
    }

    private func selectSource(index: Int, pulse: Bool) {
        state.selectSource(index: index)

        // If persistent solo is enabled, keep it aligned to selection.
        if persistentSoloIndex != nil {
            persistentSoloIndex = index
        }

        soloPulseWorkItem?.cancel()

        if pulse {
            soloLayerIndex = index
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.soloLayerIndex = self.persistentSoloIndex
            }
            soloPulseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        } else {
            soloLayerIndex = persistentSoloIndex
        }
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
        state.renderHooks.cycleSourceEffect(for: state.currentSourceIndex)
    }

    func clearAllEffects() {
        // Clear global effect
        state.renderHooks.setGlobalEffect(nil)

        // Clear all per-source effects
        for i in 0..<state.maxSources {
            state.renderHooks.setSourceEffect(nil, for: i)
        }

        // Montage-specific: also clear solo mode
        soloLayerIndex = nil
    }

    var globalEffectName: String {
        state.renderHooks.globalEffectName
    }

    var sourceEffectName: String {
        state.renderHooks.sourceEffectName(for: state.currentSourceIndex)
    }
}
