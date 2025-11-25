import Foundation
import CoreGraphics
import Combine
import SwiftUI

/// Concrete HypnographMode backed by HypnogramState + Montage renderer semantics.
/// Holds any Montage-specific preview state (like solo pulses and per-source mode data).
final class MontageMode: ObservableObject, HypnographMode {
    let state: HypnogramState
    let renderQueue: RenderQueue

    /// Mode-specific renderer for Montage exports.
    private let renderer: MontageRenderer

    /// Available blend modes for Montage, stored as Core Image filter names.
    private let availableBlendModes: [String] = [
        "CIScreenBlendMode",
        "CIOverlayBlendMode",
        "CISoftLightBlendMode",
        "CIMultiplyBlendMode",
        "CIDarkenBlendMode",
        "CILightenBlendMode",
    ]

    /// Mode-specific per-source data, same shape as `HypnogramMode.sourceData`.
    /// We keep `"blendMode"` here under `values["blendMode"]`.
    ///
    /// This is exactly the structure we later serialize into the recipe.
    private var modeSourceData: [ModeSourceData] = []

    /// Short-lived solo pulse index for visual inspection when switching sources.
    /// This never touches global solo in state; it’s view-only.
    @Published private var soloPulseIndex: Int? = nil
    private var soloPulseWorkItem: DispatchWorkItem?

    init(state: HypnogramState, renderQueue: RenderQueue) {
        self.state = state
        self.renderQueue = renderQueue
        self.renderer = MontageRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize
        )
    }

    // MARK: - ModeSourceData helpers

    /// Keep `modeSourceData` aligned 1:1 with `state.sources`.
    private func syncModeSourceDataToSources() {
        let count = state.sources.count
        if modeSourceData.count < count {
            modeSourceData.append(contentsOf: repeatElement([:], count: count - modeSourceData.count))
        } else if modeSourceData.count > count {
            modeSourceData.removeLast(modeSourceData.count - count)
        }
    }

    /// Resolve the CI filter name to use for a given source index.
    ///
    /// - Index 0: always treated as SourceOver in the compositor.
    /// - Others: use stored value if present; otherwise default Montage blend.
    private func blendModeForSourceIndex(_ idx: Int) -> String {
        syncModeSourceDataToSources()

        if idx == 0 {
            return kBlendModeSourceOver
        }

        let stored = modeSourceData[idx]["blendMode"]
        return stored ?? kBlendModeDefaultMontage
    }

    /// Blend modes for the *displayed* set, mapped via indices.
    private func blendModesForDisplay(sourceIndices: [Int]) -> [String] {
        sourceIndices.map { blendModeForSourceIndex($0) }
    }

    /// Filter name for the currently selected source.
    private var currentBlendModeFilterName: String {
        blendModeForSourceIndex(state.currentSourceIndex)
    }

    /// Very simple display name: "CIScreenBlendMode" → "Screen"
    private var currentBlendModeDisplayName: String {
        currentBlendModeFilterName
            .replacingOccurrences(of: "CI", with: "")
            .replacingOccurrences(of: "BlendMode", with: "")
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
            return "\(state.currentSourceIndex + 1)"
        }
    }

    // MARK: - Preview / solo

    /// Returns sources for display along with their original indices.
    private func sourcesForDisplay(using state: HypnogramState) -> (sources: [HypnogramSource], sourceIndices: [Int]) {
        let all = state.sources

        if let pulse = soloPulseIndex, pulse < all.count {
            return ([all[pulse]], [pulse])
        }

        if let solo = state.soloSourceIndex, solo < all.count {
            return ([all[solo]], [solo])
        }

        return (all, Array(0..<all.count))
    }

    private func startSoloPulse(for index: Int) {
        soloPulseWorkItem?.cancel()
        soloPulseIndex = index

        let work = DispatchWorkItem { [weak self] in
            self?.soloPulseIndex = nil
        }
        soloPulseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: - HypnographMode – display wiring

    func makeDisplayView(
        state: HypnogramState,
        renderQueue: RenderQueue
    ) -> AnyView {
        let (sources, sourceIndices) = sourcesForDisplay(using: state)
        let blendModes = blendModesForDisplay(sourceIndices: sourceIndices)

        return AnyView(
            MontageView(
                sources: sources,
                sourceIndices: sourceIndices,
                blendModes: blendModes,
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
            .text("Source \(state.currentSourceIndex + 1) of \(state.activeSourceCount)", order: 25),
            .text("Blend mode (M): \(currentBlendModeDisplayName)", order: 26),
            .text("Source Effect (F): \(sourceEffectName)", order: 27),
        ]

        items.append(.text("M = Cycle Blend mode", order: 46))
        return items
    }

    func compositionCommands() -> [ModeCommand] {
        []
    }

    func sourceCommands() -> [ModeCommand] {
        [
            ModeCommand(title: "Cycle Blend Mode", key: "m") { [weak self] in
                self?.cycleBlendMode()
            }
        ]
    }

    // MARK: - HypnographMode – engine behavior

    func new() {
        soloPulseIndex = nil
        state.clearSolo()
        state.newAutoPrimeSet()
        modeSourceData.removeAll()
    }

    func addSource() {
        let activeCount = state.activeSourceCount
        print("MontageMode.addSource", activeCount)

        if let _ = state.addSource() {
            // Newly added source is auto-selected by state.addSource()
            // modeSourceData will be synced lazily on first use.
            startSoloPulse(for: state.currentSourceIndex)
        }

        soloPulseIndex = nil
    }

    func deleteCurrentSource() {
        let idx = state.currentSourceIndex
        state.deleteCurrentSource()

        // Keep per-layer mode data aligned by removing the same index.
        if idx >= 0, idx < modeSourceData.count {
            modeSourceData.remove(at: idx)
        }
    }

    func save() {
        guard var recipe = state.sourcesForRender() else {
            print("renderCurrentHypnogram(): no renderable hypnogram (no selected clips).")
            return
        }

        // Ensure one entry per source
        syncModeSourceDataToSources()
        let trimmed = Array(modeSourceData.prefix(recipe.sources.count))

        // Attach Montage mode payload to the recipe
        let montageMode = HypnogramMode(
            name: .montage,
            sourceData: trimmed
        )
        recipe.mode = montageMode

        print("renderCurrentHypnogram(): enqueuing recipe with \(recipe.sources.count) source(s).")

        renderQueue.enqueue(renderer: renderer, recipe: recipe)

        DispatchQueue.main.async {
            self.state.resetForNextHypnogram()
            self.soloPulseIndex = nil
            self.modeSourceData.removeAll()

            if self.state.settings.autoPrime {
                self.state.newAutoPrimeSet()
            }
        }
    }

    // Source navigation
    func nextSource() {
        guard state.activeSourceCount > 0 else { return }
        state.nextSource()
        startSoloPulse(for: state.currentSourceIndex)
    }

    func previousSource() {
        guard state.activeSourceCount > 0 else { return }
        state.previousSource()
        startSoloPulse(for: state.currentSourceIndex)
    }

    func selectSource(index: Int) {
        guard state.activeSourceCount > 0 else { return }
        let clamped = max(0, min(state.activeSourceCount - 1, index))
        selectSource(index: clamped, pulse: true)
    }

    private func selectSource(index: Int, pulse: Bool) {
        state.selectSource(index)

        if pulse {
            startSoloPulse(for: index)
        }
    }

    // MARK: - Mode-specific tweaks

    func cycleBlendMode(at index: Int? = nil) {
        guard !availableBlendModes.isEmpty else { return }

        let idx = index ?? state.currentSourceIndex
        guard idx > 0 else {
            // We never cycle bottom layer; it's SourceOver.
            return
        }

        syncModeSourceDataToSources()

        let current = modeSourceData[idx]["blendMode"] ?? kBlendModeDefaultMontage
        let currentIndex = availableBlendModes.firstIndex(of: current) ?? -1
        let next = positiveMod(currentIndex + 1, availableBlendModes.count)

        modeSourceData[idx]["blendMode"] = availableBlendModes[next]
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        soloPulseIndex = nil
        modeSourceData.removeAll()
    }
}

// Local helper to keep indices positive when wrapping.
private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    guard modulus > 0 else { return 0 }
    let r = value % modulus
    return r >= 0 ? r : r + modulus
}
