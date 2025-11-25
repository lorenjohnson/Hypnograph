import Foundation
import CoreGraphics
import Combine
import SwiftUI

/// Concrete HypnographMode backed by HypnographState + Montage renderer semantics.
/// Holds any Montage-specific preview state and owns a HypnogramRecipe for this mode.
final class MontageMode: ObservableObject, HypnographMode {
    let state: HypnographState
    let renderQueue: RenderQueue
    @Published var recipe: HypnogramRecipe
    private let renderer: MontageRenderer

    private let availableBlendModes: [String] = [
        "CIScreenBlendMode",
        "CIOverlayBlendMode",
        "CISoftLightBlendMode",
        "CIMultiplyBlendMode",
        "CIDarkenBlendMode",
        "CILightenBlendMode",
    ]

    init(state: HypnographState, renderQueue: RenderQueue) {
        self.state = state
        self.renderQueue = renderQueue
        self.recipe = HypnogramRecipe(
            sources: [],
            targetDuration: state.settings.outputDuration,
            mode: HypnogramMode(name: .montage)
        )
        self.renderer = MontageRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize
        )
    }

    // MARK: - HUD

    func hudItems(
        state: HypnographState,
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

    // MARK: - HypnographMode – display wiring

    func makeDisplayView(
        state: HypnographState,
        renderQueue: RenderQueue
    ) -> AnyView {
        let displayRecipe = displayRecipe(using: state)

        return AnyView(
            MontageView(
                recipe: displayRecipe,
                outputSize: state.settings.outputSize,
                currentSourceTime: Binding(
                    get: { state.currentClipTimeOffset },
                    set: { state.currentClipTimeOffset = $0 }
                )
            )
        )
    }

    /// Compute the recipe to use for *preview*:
    /// - if state.soloSourceIndex is set and valid → show just that source
    /// - else → show full composition
    private func displayRecipe(using state: HypnographState) -> HypnogramRecipe {
        // For now, treat `state.sources` as canonical for clips,
        // and `recipe.mode.sourceData` as the mode-specific payload.
        var full = recipe
        full.sources = state.sources
        full.targetDuration = state.settings.outputDuration

        let total = full.sources.count
        guard total > 0 else { return full }

        guard let soloIdx = state.soloSourceIndex,
              soloIdx >= 0,
              soloIdx < total
        else {
            return full
        }

        // Build a 1-source solo recipe for preview.
        var display = full
        display.sources = [full.sources[soloIdx]]

        if var mode = display.mode {
            if soloIdx < mode.sourceData.count {
                mode.sourceData = [mode.sourceData[soloIdx]]
            } else {
                mode.sourceData = [[:]]
            }
            display.mode = mode
        }

        return display
    }

    // MARK: - Blend mode helpers

    /// Resolve the CI filter name to use for a given source index.
    /// - Index 0: always treated as SourceOver in the compositor.
    /// - Others: use stored value if present; otherwise default Montage blend.
    private func blendModeForSourceIndex(_ idx: Int) -> String {
        if idx == 0 {
            return kBlendModeSourceOver
        }

        let stored = recipe.modeValue(for: .blendMode, sourceIndex: idx)
        return stored ?? kBlendModeDefaultMontage
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

    // MARK: - HypnographMode – engine behavior

    func new() {
        state.clearSolo()
        state.newRandomHypnogram()

        recipe = HypnogramRecipe(
            sources: [],
            targetDuration: state.settings.outputDuration,
            mode: HypnogramMode(name: .montage)
        )
    }

    func addSource() {
        let activeCount = state.activeSourceCount
        print("MontageMode.addSource", activeCount)

        _ = state.addSource()
        // No pulse for now.
    }

    func deleteCurrentSource() {
        let idx = state.currentSourceIndex
        state.deleteCurrentSource()

        // Remove corresponding mode data index, if present.
        if var m = recipe.mode {
            if idx >= 0, idx < m.sourceData.count {
                m.sourceData.remove(at: idx)
            }
            recipe.mode = m
        }
    }

    func save() {
        // Let state compute the renderable sources (it may skip unselected, etc).
        guard var renderRecipe = state.sourcesForRender() else {
            print("renderCurrentHypnogram(): no renderable hypnogram (no selected clips).")
            return
        }

        // Attach Montage mode payload from this mode’s recipe.
        if var modePayload = recipe.mode {
            modePayload.sourceData.ensureCount(renderRecipe.sources.count)
            modePayload.sourceData = Array(modePayload.sourceData.prefix(renderRecipe.sources.count))
            renderRecipe.mode = modePayload
        } else {
            renderRecipe.mode = HypnogramMode(name: .montage, sourceData: [])
        }

        print("renderCurrentHypnogram(): enqueuing recipe with \(renderRecipe.sources.count) source(s).")

        renderQueue.enqueue(renderer: renderer, recipe: renderRecipe)

        DispatchQueue.main.async {
            self.state.resetForNextHypnogram()
            self.recipe = HypnogramRecipe(
                sources: [],
                targetDuration: self.state.settings.outputDuration,
                mode: HypnogramMode(name: .montage)
            )

            if self.state.settings.watch {
                self.state.newRandomHypnogram()
            }
        }
    }

    // Source navigation
    func nextSource() {
        guard state.activeSourceCount > 0 else { return }
        state.nextSource()
        // Solo behavior will be handled inside HypnographState (see below).
    }

    func previousSource() {
        guard state.activeSourceCount > 0 else { return }
        state.previousSource()
    }

    func selectSource(index: Int) {
        guard state.activeSourceCount > 0 else { return }
        let clamped = max(0, min(state.activeSourceCount - 1, index))
        state.selectSource(clamped)
    }

    // MARK: - Mode-specific tweaks

    func cycleBlendMode(at index: Int? = nil) {
        guard !availableBlendModes.isEmpty else { return }

        let idx = index ?? state.currentSourceIndex
        guard idx > 0 else {
            // We never cycle bottom layer; it's SourceOver.
            return
        }

        let current = recipe.modeValue(for: .blendMode, sourceIndex: idx)
            ?? kBlendModeDefaultMontage

        let currentIndex = availableBlendModes.firstIndex(of: current) ?? -1
        let next = positiveMod(currentIndex + 1, availableBlendModes.count)

        recipe.setModeValue(
            availableBlendModes[next],
            key: .blendMode,
            sourceIndex: idx,
            modeName: .montage
        )
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        state.clearSolo()

        recipe.targetDuration = state.settings.outputDuration
        // Keep mode data; user’s blend choices don’t need to be nuked on settings reload.
    }
}

// Local helper to keep indices positive when wrapping.
private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    guard modulus > 0 else { return 0 }
    let r = value % modulus
    return r >= 0 ? r : r + modulus
}
