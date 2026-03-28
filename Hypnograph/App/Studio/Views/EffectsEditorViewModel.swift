//
//  EffectsEditorViewModel.swift
//  Hypnograph
//

import Foundation
import Combine
import HypnoCore

@MainActor
final class EffectsEditorViewModel: ObservableObject {
    @Published var showingAddEffectPicker: Bool = false

    /// Subscription to session changes for auto-sync
    private var sessionCancellable: AnyCancellable?

    // MARK: - Navigation State

    /// Which section has keyboard navigation focus (for arrow keys)
    /// This is separate from SwiftUI focus - it tracks which section responds to arrow keys
    @Published var activeSection: EffectsEditorField = .effectList

    /// Pending selection - updated immediately on click for instant UI feedback
    /// Key: layer index (-1 = global, 0+ = source), Value: effect index (-1 = None)
    @Published private var pendingSelection: [Int: Int] = [:]

    /// Local copy of effect chains for immediate UI updates
    /// This mirrors the session's chains for UI responsiveness
    @Published private(set) var effectChains: [EffectChain] = []

    /// The session this view model is working with (set by the view on appear)
    weak var session: EffectsSession? {
        didSet {
            setupSessionSubscription()
            syncFromSession()
        }
    }

    init() {
        // Chains will be synced when session is set
    }

    /// Subscribe to session changes to auto-sync when chains are modified
    /// (e.g., when loading a hypnogram imports effect chains)
    private func setupSessionSubscription() {
        // Cancel any existing subscription
        sessionCancellable?.cancel()

        guard let session = session else {
            sessionCancellable = nil
            return
        }

        // Subscribe to session's chainsPublisher to sync AFTER chains change
        // (Not objectWillChange which fires BEFORE the change)
        sessionCancellable = session.chainsPublisher
            .dropFirst() // Skip initial value (we already synced in didSet)
            .receive(on: RunLoop.main)
            .sink { [weak self] newChains in
                // Session chains changed - update our local copy
                self?.effectChains = newChains
            }
    }

    /// Check if arrow key navigation should be active (not in a text field)
    var isNavigationActive: Bool {
        switch activeSection {
        case .effectList, .parameterList, .effectCheckbox:
            return true
        case .effectName, .parameterText:
            return false
        }
    }

    /// Sync local chains from the session
    func syncFromSession() {
        effectChains = session?.chains ?? []
    }

    /// Set pending selection for immediate UI update
    func setPendingSelection(effectIndex: Int, for layer: Int) {
        pendingSelection[layer] = effectIndex
    }

    /// Clear pending selection (called when render catches up)
    func clearPendingSelection(for layer: Int) {
        pendingSelection.removeValue(forKey: layer)
    }

    /// Get selected effect index - uses pending selection if available, otherwise from recipe
    func selectedEffectIndex(for globalEffectName: String?, layer: Int) -> Int {
        // Return pending selection if we have one (immediate UI feedback)
        if let pending = pendingSelection[layer] {
            return pending
        }
        // Otherwise derive from recipe
        guard let name = globalEffectName, name != "None" else { return -1 }
        return effectChains.firstIndex(where: { $0.name == name }) ?? -1
    }

    /// Currently selected effect chain (nil for "None")
    func selectedChain(for globalEffectName: String?, layer: Int) -> EffectChain? {
        let index = selectedEffectIndex(for: globalEffectName, layer: layer)
        guard index >= 0 && index < effectChains.count else { return nil }
        return effectChains[index]
    }

    /// Merge effect's parameterSpecs with JSON params.
    /// Effect specs define what params exist (source of truth).
    /// JSON values override defaults. Unknown JSON params are ignored.
    static func mergedParametersForEffect(_ effectDef: EffectDefinition) -> [String: AnyCodableValue] {
        let effectType = effectDef.type
        let specs = EffectRegistry.parameterSpecs(for: effectType)
        var result: [String: AnyCodableValue] = [:]

        // Start with defaults from specs
        for (name, spec) in specs {
            result[name] = spec.defaultValue
        }

        // Overlay JSON values (only for params that exist in specs)
        if let jsonParams = effectDef.params {
            for (name, value) in jsonParams {
                // Skip internal params and params not in specs
                if name.hasPrefix("_") { continue }
                if specs[name] != nil {
                    result[name] = value
                }
            }
        }

        return result
    }

    /// Update a parameter value for an effect (or child effect in a chain)
    func updateParameter(effectIndex: Int, effectDefIndex: Int?, paramName: String, value: AnyCodableValue) {
        guard let session = session else { return }

        // Update local state for responsive UI
        updateLocalChain(at: effectIndex) { chain in
            if let defIndex = effectDefIndex {
                // Update parameter in a child effect
                guard defIndex >= 0 && defIndex < chain.effects.count else { return chain }
                let updatedChain = chain
                var params = updatedChain.effects[defIndex].params ?? [:]
                params[paramName] = value
                updatedChain.effects[defIndex].params = params
                return updatedChain
            } else {
                // Update parameter on the chain itself (future: chain-level params)
                let updatedChain = chain
                var params = updatedChain.params ?? [:]
                params[paramName] = value
                updatedChain.params = params
                return updatedChain
            }
        }

        // Persist to session
        session.updateParameter(chainIndex: effectIndex, effectIndex: effectDefIndex, key: paramName, value: value)
    }

    /// Add an effect to the currently selected effect chain
    func addEffectToChain(effectIndex: Int, effectType: String) {
        guard let session = session else { return }
        // Session update triggers subscription which syncs effectChains
        session.addEffectToChain(chainIndex: effectIndex, effectType: effectType)
    }

    /// Remove an effect from the currently selected effect chain
    func removeEffectFromChain(effectIndex: Int, effectDefIndex: Int) {
        guard let session = session else { return }
        session.removeEffectFromChain(chainIndex: effectIndex, effectIndex: effectDefIndex)
    }

    /// Reorder effects in the currently selected effect chain
    func reorderEffects(effectIndex: Int, fromIndex: Int, toIndex: Int) {
        guard let session = session else { return }
        session.reorderEffectsInChain(chainIndex: effectIndex, fromIndex: fromIndex, toIndex: toIndex)
    }

    /// Toggle effect enabled state
    func setEffectEnabled(effectIndex: Int, effectDefIndex: Int, enabled: Bool) {
        guard let session = session else { return }
        session.setEffectEnabled(chainIndex: effectIndex, effectIndex: effectDefIndex, enabled: enabled)
    }

    /// Reset an effect's parameters to their default values
    func resetEffectToDefaults(effectIndex: Int, effectDefIndex: Int) {
        guard let session = session else { return }
        session.resetEffectToDefaults(chainIndex: effectIndex, effectIndex: effectDefIndex)
    }

    /// Randomize an effect's parameters
    func randomizeEffect(effectIndex: Int, effectDefIndex: Int) {
        guard let session = session else { return }
        session.randomizeEffect(chainIndex: effectIndex, effectIndex: effectDefIndex)
    }

    /// Update the name of the selected effect chain
    func updateEffectName(effectIndex: Int, name: String) {
        guard let session = session else { return }
        session.updateChainName(chainIndex: effectIndex, name: name)
    }

    /// Available effect types for adding to chains
    var availableEffectTypes: [(type: String, displayName: String)] {
        EffectRegistry.availableEffectTypes
    }

    /// Create a new effect chain (with Basic as default effect)
    /// Returns the index of the new chain
    @discardableResult
    func createNewEffect() -> Int {
        guard let session = session else { return -1 }
        return session.createNewChain()
        // Subscription will sync effectChains
    }

    /// Delete an effect chain at the given index
    func deleteEffect(at index: Int) {
        guard let session = session else { return }
        session.deleteChain(at: index)
        // Subscription will sync effectChains
    }

    // MARK: - Private Helpers

    /// Update a local chain immediately (for responsive UI - used by parameter sliders)
    private func updateLocalChain(at index: Int, transform: (EffectChain) -> EffectChain) {
        guard index >= 0 && index < effectChains.count else { return }
        effectChains[index] = transform(effectChains[index])
    }
}
