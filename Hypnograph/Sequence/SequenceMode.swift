//
//  SequenceMode.swift
//  Hypnograph
//
//  Created by Loren Johnson on 20.11.25.
//

import Foundation
import SwiftUI
import CoreMedia

/// Sequence mode: Select multiple clips with random durations (2-15s each)
/// that play one after another in sequence until the total duration equals targetDuration.
/// Navigate between clips with arrow keys or 1-5 keys. Global and per-source effects still apply.
/// Compatible with HypnogramRecipe by creating a single-layer recipe for each clip.
final class SequenceMode: ObservableObject, HypnographMode {

    /// Shared session state
    private let state: HypnogramState

    /// Render queue + backend for this mode
    let renderQueue: RenderQueue

    /// Array of clips in the sequence (each plays one after another)
    @Published private(set) var sequenceClips: [VideoClip] = []

    /// Current clip index being viewed/edited
    @Published private(set) var currentClipIndex: Int = 0

    /// Soloed clip index (loops when active)
    @Published private(set) var soloClipIndex: Int? = nil

    /// Total accumulated duration of all clips in the sequence
    var totalDuration: CMTime {
        sequenceClips.reduce(CMTime.zero) { $0 + $1.duration }
    }

    /// Desired starting clip count
    private let initialClipCount = 5

    init(state: HypnogramState) {
        self.state = state
        let backend = SequenceRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize
        )
        self.renderQueue = RenderQueue(renderer: backend)
    }
    
    // MARK: - HypnographMode – display wiring

    func makeDisplayView(
        state: HypnogramState,
        renderQueue: RenderQueue
    ) -> AnyView {
        // Ensure we have something to show when the user switches into the mode
        if sequenceClips.isEmpty {
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
        items.append(.text("Sources: \(sequenceClips.count)", order: 25))
        items.append(.text("Current: \(currentClipIndex + 1)/\(sequenceClips.count)", order: 26))
        
        let totalSecs = totalDuration.seconds
        items.append(.text(String(format: "Duration: %.1fs", totalSecs), order: 27))
        items.append(.text("Press N to add sources", order: 28))
        
        // Current clip info
        if currentClipIndex < sequenceClips.count {
            let clip = sequenceClips[currentClipIndex]
            items.append(.padding(8, order: 29))
            items.append(.text("Source \(currentClipIndex + 1): \(clip.duration.seconds)s", order: 30))
            items.append(.text("Source Effect: \(state.renderHooks.sourceEffectName(for: currentClipIndex))", order: 31))
        }
        
        // Mode-specific shortcuts
        items.append(.text("←/→ = Navigate sources", order: 46))
        items.append(.text("1-5 = Jump to source", order: 47))
        
        return items
    }
    
    func modeCommands() -> [ModeCommand] {
        // Sequence-specific commands (number keys handled globally)
        return []
    }
    
    // MARK: - HypnographMode – engine behavior
    
    func newRandomHypnogram() {
        // Generate a new sequence
        sequenceClips.removeAll()
        currentClipIndex = 0
        fillSequence()
    }
    
    func saveCurrentHypnogram() {
        guard !sequenceClips.isEmpty else {
            print("SequenceMode: no clips to save")
            return
        }

        // Convert sequence clips to HypnogramRecipe format
        // Each clip becomes a single-layer recipe that will be concatenated during rendering
        let layers = sequenceClips.map { clip in
            HypnogramLayer(clip: clip, blendMode: BlendMode(key: "normal"))
        }

        let recipe = HypnogramRecipe(
            layers: layers,
            targetDuration: totalDuration  // Use actual total duration of all clips
        )

        print("SequenceMode: enqueuing sequence with \(sequenceClips.count) clip(s), total duration: \(totalDuration.seconds)s")
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
        sequenceClips.removeAll()
        currentClipIndex = 0

        if state.settings.autoPrime {
            fillSequence()
        }
    }


    // MARK: - Source navigation
    
    func nextSource() {
        guard !sequenceClips.isEmpty else { return }
        currentClipIndex = min(sequenceClips.count - 1, currentClipIndex + 1)
        if soloClipIndex != nil {
            soloClipIndex = currentClipIndex
        }
    }

    func previousSource() {
        currentClipIndex = max(0, currentClipIndex - 1)
        if soloClipIndex != nil {
            soloClipIndex = currentClipIndex
        }
    }

    func selectSource(index: Int) {
        guard !sequenceClips.isEmpty else { return }
        currentClipIndex = max(0, min(sequenceClips.count - 1, index))
        if soloClipIndex != nil {
            soloClipIndex = currentClipIndex
        }
    }

    func addSource() {
        let clipDuration = randomClipDuration()
        guard let clip = state.library.randomClip(clipLength: clipDuration) else {
            print("SequenceMode: failed to get random clip")
            return
        }

        sequenceClips.append(clip)
        currentClipIndex = sequenceClips.count - 1
        if soloClipIndex != nil {
            soloClipIndex = currentClipIndex
        }
    }
    
    // MARK: - Candidate / selection
    
    func nextCandidate() {
        // In sequence mode, "next candidate" refreshes the current source with a new random clip
        let clipDuration = randomClipDuration()
        guard let clip = state.library.randomClip(clipLength: clipDuration) else {
            print("SequenceMode: failed to get random clip")
            return
        }

        if sequenceClips.isEmpty {
            sequenceClips = [clip]
            currentClipIndex = 0
        } else {
            sequenceClips[currentClipIndex] = clip
        }

        if soloClipIndex != nil {
            soloClipIndex = currentClipIndex
        }
    }
    
    func acceptCandidate() {
        // In sequence mode, accepting moves to the next clip
        nextSource()
    }
    
    func deleteCurrentSource() {
        guard currentClipIndex < sequenceClips.count else { return }
        sequenceClips.remove(at: currentClipIndex)
        if soloClipIndex == currentClipIndex {
            soloClipIndex = nil
        } else if let solo = soloClipIndex, solo > currentClipIndex {
            soloClipIndex = solo - 1
        }
        if currentClipIndex >= sequenceClips.count && currentClipIndex > 0 {
            currentClipIndex -= 1
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
        if soloClipIndex == currentClipIndex {
            soloClipIndex = nil
        } else {
            soloClipIndex = currentClipIndex
        }
    }
    
    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        sequenceClips.removeAll()
        currentClipIndex = 0
    }
    
    // MARK: - Effects
    
    func cycleGlobalEffect() {
        state.renderHooks.cycleGlobalEffect()
    }
    
    func cycleSourceEffect() {
        state.renderHooks.cycleSourceEffect(for: currentClipIndex)
    }
    
    func clearAllEffects() {
        state.renderHooks.setGlobalEffect(nil)
        for i in 0..<sequenceClips.count {
            state.renderHooks.setSourceEffect(nil, for: i)
        }
    }
    
    var globalEffectName: String {
        state.renderHooks.globalEffectName
    }
    
    var sourceEffectName: String {
        state.renderHooks.sourceEffectName(for: currentClipIndex)
    }

    func selectOrToggleSolo(index: Int) {
        if currentClipIndex == index {
            toggleSolo()
        } else {
            selectSource(index: index)
        }
    }
    
    // MARK: - Sequence building
    
    /// Fill the sequence with random clips until we reach targetDuration
    private func fillSequence() {
        while sequenceClips.count < initialClipCount {
            let clipDuration = randomClipDuration()
            guard let clip = state.library.randomClip(clipLength: clipDuration) else {
                print("SequenceMode: failed to get random clip")
                break
            }
            sequenceClips.append(clip)
        }

        currentClipIndex = min(currentClipIndex, max(sequenceClips.count - 1, 0))

        print("SequenceMode: generated sequence with \(sequenceClips.count) clips, total duration: \(totalDuration.seconds)s")
    }
    
    /// Add a single clip to the sequence
    private func addClipToSequence() {
        let clipDuration = randomClipDuration()

        if let clip = state.library.randomClip(clipLength: clipDuration) {
            sequenceClips.append(clip)
            currentClipIndex = sequenceClips.count - 1
            print("SequenceMode: added clip with duration \(clip.duration.seconds)s")
        } else {
            print("SequenceMode: failed to get random clip")
        }
    }

    private func randomClipDuration() -> Double {
        Double.random(in: 2.0...15.0)
    }

    var currentSourceIndex: Int {
        currentClipIndex
    }

    var isSoloActive: Bool {
        soloClipIndex != nil
    }

    var soloIndicatorText: String? {
        if let solo = soloClipIndex {
            return "SOLO \(solo + 1)"
        } else {
            return "\(currentSourceIndex + 1)"
        }
    }
}
