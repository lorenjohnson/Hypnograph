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

    /// Soloed source index (loops when active)
    @Published private(set) var soloSourceIndex: Int? = nil

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
        items.append(.text("Press N to add sources", order: 28))
        
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
            HypnogramSource(clip: source, blendMode: BlendMode(key: "normal"))
        }

        let recipe = HypnogramRecipe(
            sources: sources,
            targetDuration: totalDuration  // Use actual total duration of all sources
        )

        print("SequenceMode: enqueuing sequence with \(sequenceSources.count) source(s), total duration: \(totalDuration.seconds)s")
        (renderQueue.renderer as? SequenceRenderer)?.enqueueSequence(recipe: recipe) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    print("SequenceMode: render completed → \(url.path)")
                case .failure(let error):
                    print("SequenceMode: render failed: \(error)")
                }
            }
        }

        // Reset for next sequence
        fillSequence()
    }


    // MARK: - Source navigation
    
    func nextSource() {
        guard !sequenceSources.isEmpty else { return }
        state.nextSource()
        if soloSourceIndex != nil {
            soloSourceIndex = currentSourceIndex
        }
    }

    func previousSource() {
        state.prevSource()
        if soloSourceIndex != nil {
            soloSourceIndex = currentSourceIndex
        }
    }

    func selectSource(index: Int) {
        guard !sequenceSources.isEmpty else { return }
        state.selectSource(index: index)
        if soloSourceIndex != nil {
            soloSourceIndex = currentSourceIndex
        }
    }

    func addSource() {
        let activeCount = state.activeSourceCount
        guard activeCount < state.maxSources else { return }

        state.selectSource(index: activeCount)
        _ = state.setRandomCandidateForCurrentSource(clipLength: randomSourceDuration())

        if soloSourceIndex != nil {
            soloSourceIndex = currentSourceIndex
        }
    }
    
    // MARK: - Candidate / selection
    
    func nextCandidate() {
        // In sequence mode, "next candidate" refreshes the current source with a new random clip
        _ = state.setRandomCandidateForCurrentSource(clipLength: randomSourceDuration())

        if soloSourceIndex != nil {
            soloSourceIndex = currentSourceIndex
        }
    }
    
    func acceptCandidate() {
        // In sequence mode, accepting moves to the next source
        nextSource()
    }
    
    func deleteCurrentSource() {
        guard currentSourceIndex < sequenceSources.count else { return }
        state.deleteCurrentSource()

        if soloSourceIndex == currentSourceIndex {
            soloSourceIndex = nil
        } else if let solo = soloSourceIndex, solo > currentSourceIndex {
            soloSourceIndex = solo - 1
        }
    }
    
    // MARK: - Mode-specific tweaks
    
    func cycleEffect() {
        // No blend modes in sequence mode
    }
    
    func toggleHUD() {
        state.toggleHUD()
    }
    
    func toggleSolo() {
        if soloSourceIndex == currentSourceIndex {
            soloSourceIndex = nil
        } else {
            soloSourceIndex = currentSourceIndex
        }
    }
    
    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
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
        if currentSourceIndex == index {
            toggleSolo()
        } else {
            selectSource(index: index)
        }
    }
    
    // MARK: - Sequence building
    
    /// Fill the sequence with random sources until we reach our starting count
    private func fillSequence() {
        // Reset state-managed storage, then populate with random-duration candidates.
        state.resetForNextHypnogram()

        let desiredCount = min(initialSourceCount, state.maxSources)
        for i in 0..<desiredCount {
            state.selectSource(index: i)
            _ = state.setRandomCandidateForCurrentSource(clipLength: randomSourceDuration())
        }

        let active = state.activeSourceCount
        let clampedIndex = max(0, min(active - 1, currentSourceIndex))
        state.selectSource(index: clampedIndex)

        print("SequenceMode: generated sequence with \(sequenceSources.count) sources, total duration: \(totalDuration.seconds)s")
    }
    
    private func randomSourceDuration() -> Double {
        Double.random(in: 2.0...15.0)
    }

    var isSoloActive: Bool {
        soloSourceIndex != nil
    }

    var soloIndicatorText: String? {
        if let solo = soloSourceIndex {
            return "SOLO \(solo + 1)"
        } else {
            return "\(currentSourceIndex + 1)"
        }
    }
}
