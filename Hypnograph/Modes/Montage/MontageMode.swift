import Foundation
import CoreGraphics
import Combine
import SwiftUI

/// Concrete HypnographMode backed by HypnogramState + Montage renderer semantics.
/// Holds any Montage-specific preview state (like solo pulses).
final class MontageMode: ObservableObject, HypnographMode {

    /// Shared session state used by the Montage mode.
    /// This is the same instance that ContentView observes.
    private let state: HypnogramState

    /// Render queue + backend for this mode.
    let renderQueue: RenderQueue

    /// Short-lived solo pulse index for visual inspection when switching sources.
    /// This never touches global solo in state; it’s view-only.
    @Published private var soloPulseIndex: Int? = nil
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
        soloPulseIndex != nil || state.soloSourceIndex != nil
    }

    var soloIndicatorText: String? {
        if let pulse = soloPulseIndex {
            return "SOLO \(pulse + 1)"
        } else if let solo = state.soloSourceIndex {
            return "SOLO \(solo + 1)"
        } else {
            return "\(currentSourceIndex + 1)"
        }
    }
    
    var maxSources: Int {
        max(1, state.settings.maxSources)
    }

    // MARK: - Preview / solo

    /// Returns sources for display along with their original indices
    private func sourcesForDisplay(using state: HypnogramState) -> (sources: [HypnogramSource], sourceIndices: [Int]) {
        let all = state.sources

        if let pulse = soloPulseIndex {
            guard pulse >= 0, pulse < all.count else {
                return (all, Array(0..<all.count))
            }
            // Pulse solo: momentary view-only solo.
            return ([all[pulse]], [pulse])
        } else if let solo = state.soloSourceIndex {
            guard solo >= 0, solo < all.count else {
                return (all, Array(0..<all.count))
            }
            // Persistent solo: use state solo.
            return ([all[solo]], [solo])
        } else {
            // Normal mode: all sources with sequential indices
            return (all, Array(0..<all.count))
        }
    }

    private func startSoloPulse(for index: Int) {
        soloPulseWorkItem?.cancel()
        soloPulseIndex = index

        let work = DispatchWorkItem { [weak self] in
            self?.soloPulseIndex = nil
        }
        soloPulseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
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

    /// Number keys: momentary solo pulse, never latch persistent solo.
    func selectOrToggleSolo(index: Int) {
        selectSource(index: index, pulse: true)
    }

    // MARK: - HypnographMode – engine behavior

    func new() {
        soloPulseIndex = nil
        state.clearSolo()
        state.newAutoPrimeSet()
    }

    func addSource() {
        let activeCount = state.activeSourceCount
        print("MontageMode.addSource", activeCount)
        // Always allow appending; no hard cap here.
        if let _ = state.addSource() {
            // Newly added source is auto-selected by state.addSource()
            startSoloPulse(for: state.currentSourceIndex)
        }

        soloPulseIndex = nil
    }

    func save() {
        guard let recipe = state.sourcesForRender() else {
            print("renderCurrentHypnogram(): no renderable hypnogram (no selected clips).")
            return
        }

        print("renderCurrentHypnogram(): enqueuing recipe with \(recipe.sources.count) source(s).")
        renderQueue.enqueue(recipe: recipe)

        state.resetForNextHypnogram()
        soloPulseIndex = nil

        if state.settings.autoPrime {
            state.newAutoPrimeSet()
        }
    }

    // Source navigation
    func nextSource() {
        let activeCount = state.activeSourceCount
        guard activeCount > 0 else { return }
        state.nextSource()
        startSoloPulse(for: state.currentSourceIndex)
    }

    func previousSource() {
        let activeCount = state.activeSourceCount
        guard activeCount > 0 else { return }
        state.previousSource()
        startSoloPulse(for: state.currentSourceIndex)
    }

    func selectSource(index: Int) {
        let activeCount = state.activeSourceCount
        guard activeCount > 0 else { return }
        let clamped = max(0, min(activeCount - 1, index))
        selectSource(index: clamped, pulse: true)
    }

    private func selectSource(index: Int, pulse: Bool) {
        state.selectSource(index)

        if pulse {
            startSoloPulse(for: index)
        }
    }

    // MARK: - Candidate / selection

    func newRandomClip() {
        _ = state.replaceClip(at: state.currentSourceIndex)
    }

    func deleteCurrentSource() {
        state.deleteCurrentSource()
    }

    // MARK: - Mode-specific tweaks

    func cycleEffect() {
        state.cycleBlendMode()
    }

    func toggleHUD() {
        state.isHUDVisible.toggle()
    }

    func toggleSolo() {
        state.soloSource(index: state.currentSourceIndex)
    }

    func reloadSettings() {
        state.resetForNextHypnogram()
        soloPulseIndex = nil
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
        for i in 0..<maxSources {
            state.renderHooks.setSourceEffect(nil, for: i)
        }

        soloPulseIndex = nil
        state.clearSolo()
    }

    var globalEffectName: String {
        state.renderHooks.globalEffectName
    }

    var sourceEffectName: String {
        state.renderHooks.sourceEffectName(for: state.currentSourceIndex)
    }
}
