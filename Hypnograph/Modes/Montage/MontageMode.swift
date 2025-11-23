import Foundation
import CoreGraphics
import Combine
import SwiftUI


/// Montage-specific configuration that can be serialized into a HypnogramRecipe.
///
/// Right now this just carries the per-layer Core Image blend filter names used
/// at render time. It is owned conceptually by Montage mode, but lives here so
/// both the mode and renderer can see it.
struct MontageConfig: ModeConfig {
    static let modeType: ModeType = .montage

    /// One CI filter name per source/layer (bottom → top).
    /// e.g. ["CISourceOverCompositing", "CIScreenBlendMode", ...]
    var layerBlendModes: [String]
}

/// Concrete HypnographMode backed by HypnogramState + Montage renderer semantics.
/// Holds any Montage-specific preview state (like solo pulses).
final class MontageMode: ObservableObject, HypnographMode {
    let state: HypnogramState
    let renderQueue: RenderQueue

    /// Available blend modes for Montage, stored as CI filter names.
    private let availableBlendModes: [BlendMode] = [
        BlendMode(ciFilterName: "CIScreenBlendMode"),
        BlendMode(ciFilterName: "CIOverlayBlendMode"),
        BlendMode(ciFilterName: "CISoftLightBlendMode"),
        BlendMode(ciFilterName: "CIMultiplyBlendMode"),
        BlendMode(ciFilterName: "CIDarkenBlendMode"),
        BlendMode(ciFilterName: "CILightenBlendMode"),
        // If you want the full set later, just extend this list.
        // BlendMode(ciFilterName: "CIDifferenceBlendMode"),
        // BlendMode(ciFilterName: "CIExclusionBlendMode"),
    ]

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

    // MARK: - Blend mode helpers (preview-time)

    private var defaultBlendMode: BlendMode {
        availableBlendModes.first ?? .sourceOver
    }

    private var currentBlendMode: BlendMode {
        state.currentSource?.blendMode ?? defaultBlendMode
    }

    private var currentBlendModeName: String {
        currentBlendMode.displayName
    }

    /// Build the CI filter name list for the *current* sources in state.
    /// First layer is always treated as source-over for compositing purposes.
    private func currentLayerBlendModes(for sources: [HypnogramSource]) -> [String] {
        sources.enumerated().map { index, source in
            if index == 0 {
                return "CISourceOverCompositing"
            } else {
                return source.blendMode.ciFilterName
            }
        }
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
            .text("Blend mode (M): \(currentBlendModeName)", order: 26),
            .text("Source Effect (F): \(sourceEffectName)", order: 27),
        ]

        // Mode-specific shortcuts (after global shortcuts)
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
        guard var recipe = state.sourcesForRender() else {
            print("renderCurrentHypnogram(): no renderable hypnogram (no selected clips).")
            return
        }

        // Attach Montage-specific blend-mode configuration to the recipe.
        let blendModes = currentLayerBlendModes(for: recipe.sources)
        let config = MontageConfig(layerBlendModes: blendModes)
        recipe.setModeConfig(config)

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

    // MARK: - Mode-specific tweaks

    func cycleBlendMode(at index: Int? = nil) {
        let idx = index ?? state.currentSourceIndex
        let count = state.sources.count

        guard idx >= 0,
              idx < count,
              !availableBlendModes.isEmpty
        else { return }

        let current = state.sources[idx]
        let modes = availableBlendModes

        let currentIndex = modes.firstIndex {
            $0.ciFilterName == current.blendMode.ciFilterName
        } ?? -1

        let next = positiveMod(currentIndex + 1, modes.count)

        var updated = current
        updated.blendMode = modes[next]
        state.sources[idx] = updated
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        soloPulseIndex = nil
    }
}

// Local helper to keep indices positive when wrapping.
private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    guard modulus > 0 else { return 0 }
    let r = value % modulus
    return r >= 0 ? r : r + modulus
}
