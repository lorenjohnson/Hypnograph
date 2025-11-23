//
//  SequenceMode.swift
//  Hypnograph
//
//  Created by Loren Johnson on 20.11.25.
//

import Foundation
import SwiftUI
import CoreMedia
import Combine

/// Sequence mode: Select multiple sources (video clips) with random durations (2-15s each)
/// that play one after another in sequence until the total duration equals targetDuration.
/// Navigate between sources with arrow keys or 1-5 keys. Global and per-source effects still apply.
final class SequenceMode: ObservableObject, HypnographMode {

    /// Shared session state
    private let state: HypnogramState

    /// Render queue + backend for this mode
    let renderQueue: RenderQueue

    /// Total accumulated duration of all sources in the sequence
    var totalDuration: CMTime {
        sequenceSources.reduce(CMTime.zero) { $0 + $1.duration }
    }

    /// Desired starting source count
    private let initialSourceCount = 5

    private var cancellables = Set<AnyCancellable>()

    var sequenceSources: [VideoClip] {
        state.sources.map { $0.clip }
    }

    var currentSourceIndex: Int {
        state.currentSourceIndex
    }

    /// Max sources for this mode (independent of settings.maxSources if you want)
    var maxSources: Int = 20

    init(state: HypnogramState) {
        self.state = state
        let backend = SequenceRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize
        )
        self.renderQueue = RenderQueue(renderer: backend)

        // Forward state changes so SwiftUI updates, while reading directly from state.
        state.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - HypnographMode – display wiring

    func makeDisplayView(
        state: HypnogramState,
        renderQueue: RenderQueue
    ) -> AnyView {
        // Ensure we have something to show when the user switches into the mode
        if sequenceSources.isEmpty {
            fillSequence()
        }

        return AnyView(
            SequenceView(
                mode: self,
                outputSize: state.settings.outputSize
            )
        )
    }

    func hudItems(
        state: HypnogramState,
        renderQueue: RenderQueue
    ) -> [HUDItem] {
        var items: [HUDItem] = []

        // Sequence status
        items.append(.text("Sources: \(sequenceSources.count)", order: 25))
        items.append(.text("Current: \(currentSourceIndex + 1)/\(sequenceSources.count)", order: 26))

        let totalSecs = totalDuration.seconds
        items.append(.text(String(format: "Duration: %.1fs", totalSecs), order: 27))
        items.append(.text("Press N for new clip", order: 28))

        // Current source info
        if currentSourceIndex < sequenceSources.count {
            let clip = sequenceSources[currentSourceIndex]
            items.append(.padding(8, order: 29))
            items.append(.text("Source \(currentSourceIndex + 1): \(clip.duration.seconds)s", order: 30))
            items.append(.text("Source Effect: \(state.renderHooks.sourceEffectName(for: currentSourceIndex))", order: 31))
        }

        // Mode-specific shortcuts
        items.append(.text("←/→ = Navigate sources", order: 46))
        items.append(.text("1-5 = Jump to source", order: 47))

        return items
    }

    func compositionCommands() -> [ModeCommand] {
        return []
    }

    func sourceCommands() -> [ModeCommand] {
        return []
    }

    // MARK: - HypnographMode – engine behavior

    func new() {
        // Generate a new sequence
        fillSequence()
    }

    func save() {
        guard !sequenceSources.isEmpty else {
            print("SequenceMode: no sources to save")
            return
        }

        // Convert sequence sources to HypnogramRecipe format
        // Each source becomes a single-source that will be concatenated during rendering
        let sources = sequenceSources.map { source in
            HypnogramSource(clip: source)
        }

        let recipe = HypnogramRecipe(
            sources: sources,
            targetDuration: totalDuration  // Use actual total duration of all sources
        )

        print("SequenceMode: enqueuing sequence with \(sequenceSources.count) source(s), total duration: \(totalDuration.seconds)s")
        renderQueue.enqueue(recipe: recipe)

        // Reset for next sequence
        fillSequence()
    }

    // MARK: - Source navigation

    func nextSource() {
        guard !sequenceSources.isEmpty else { return }
        state.nextSource()
    }

    func previousSource() {
        guard !sequenceSources.isEmpty else { return }
        state.previousSource()
    }

    func selectSource(index: Int) {
        guard !sequenceSources.isEmpty else { return }
        state.selectSource(index)
    }

    func addSource() {
        let activeCount = state.activeSourceCount
        guard activeCount < maxSources else { return }

        if let _ = state.addSource(length: randomSourceDuration()) {
            // addSource auto-selects the new source
        }
    }

    // MARK: - Clip randomisation (was "candidate")

    func newRandomClip() {
        guard !sequenceSources.isEmpty else { return }
        _ = state.replaceClip(at: currentSourceIndex, length: randomSourceDuration())
    }

    func deleteCurrentSource() {
        guard currentSourceIndex < sequenceSources.count else { return }
        state.deleteCurrentSource()
    }

    // MARK: - Mode-specific tweaks

    func cycleEffect() {
        // No blend modes in sequence mode
    }

    func toggleHUD() {
        state.isHUDVisible.toggle()
    }

    func toggleSolo() {
        state.soloSource(index: currentSourceIndex)
    }

    func reloadSettings() {
        state.resetForNextHypnogram()
        if sequenceSources.isEmpty {
            fillSequence()
        }
    }

    // MARK: - Effects

    func cycleGlobalEffect() {
        state.renderHooks.cycleGlobalEffect()
    }

    func cycleSourceEffect() {
        state.renderHooks.cycleSourceEffect(for: currentSourceIndex)
    }

    func clearAllEffects() {
        state.renderHooks.setGlobalEffect(nil)
        for i in 0..<sequenceSources.count {
            state.renderHooks.setSourceEffect(nil, for: i)
        }
    }

    var globalEffectName: String {
        state.renderHooks.globalEffectName
    }

    var sourceEffectName: String {
        state.renderHooks.sourceEffectName(for: currentSourceIndex)
    }

    func selectOrToggleSolo(index: Int) {
        // In sequence mode, number keys just jump; solo is explicit via Toggle Solo
        selectSource(index: index)
    }

    // MARK: - Sequence building

    /// Fill the sequence with random sources until we reach our starting count
    private func fillSequence() {
        state.resetForNextHypnogram()

        let desiredCount = min(initialSourceCount, maxSources)
        for _ in 0..<desiredCount {
            _ = state.addSource(length: randomSourceDuration())
        }

        let active = state.activeSourceCount
        let clampedIndex = max(0, min(active - 1, currentSourceIndex))
        state.selectSource(clampedIndex)

        print("SequenceMode: generated sequence with \(sequenceSources.count) sources, total duration: \(totalDuration.seconds)s")
    }

    private func randomSourceDuration() -> Double {
        Double.random(in: 2.0...15.0)
    }

    // MARK: - Solo / HUD

    var isSoloActive: Bool {
        state.soloSourceIndex != nil
    }

    /// Exposed so SequenceView can know which index is solo'd
    var soloSourceIndex: Int? {
        state.soloSourceIndex
    }

    var soloIndicatorText: String? {
        if let solo = state.soloSourceIndex {
            return "SOLO \(solo + 1)"
        } else {
            return "\(currentSourceIndex + 1)"
        }
    }
}
