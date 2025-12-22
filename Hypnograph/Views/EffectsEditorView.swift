//
//  EffectsEditorView.swift
//  Hypnograph
//
//  Semi-transparent panel for editing effect parameters.
//  Toggle with Shift+E. Changes are live and persist to JSON.
//

import SwiftUI

/// Which panel is focused in the effects editor
enum EffectsEditorPanel {
    case effects    // Left panel - effect list
    case parameters // Right panel - parameter sliders
}

/// View model for the effects editor
@MainActor
final class EffectsEditorViewModel: ObservableObject {
    @Published var showingAddEffectPicker: Bool = false

    // MARK: - Navigation State

    /// Which panel is currently focused
    @Published var focusedPanel: EffectsEditorPanel = .effects

    /// Selected parameter index in the parameters panel (for chained effects, this is a flat index across all hooks)
    @Published var selectedParameterIndex: Int = 0

    /// Pending selection - updated immediately on click for instant UI feedback
    /// Key: layer index (-1 = global, 0+ = source), Value: effect index (-1 = None)
    @Published private var pendingSelection: [Int: Int] = [:]

    /// Local copy of effect definitions for immediate UI updates
    /// This is the source of truth for the UI - synced from EffectConfigLoader
    @Published private(set) var effectDefinitions: [EffectDefinition] = []

    init() {
        // Initialize from current config
        syncFromConfig()
    }

    /// Sync local definitions from the config loader
    func syncFromConfig() {
        effectDefinitions = EffectConfigLoader.currentDefinitions
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
        return effectDefinitions.firstIndex(where: { $0.name == name }) ?? -1
    }

    /// Get selected effect index from global effect name (-1 = None) - legacy for compatibility
    func selectedEffectIndex(for globalEffectName: String?) -> Int {
        guard let name = globalEffectName, name != "None" else { return -1 }
        return effectDefinitions.firstIndex(where: { $0.name == name }) ?? -1
    }

    /// Currently selected effect definition (nil for "None")
    func selectedDefinition(for globalEffectName: String?, layer: Int) -> EffectDefinition? {
        let index = selectedEffectIndex(for: globalEffectName, layer: layer)
        guard index >= 0 && index < effectDefinitions.count else { return nil }
        return effectDefinitions[index]
    }

    /// Currently selected effect definition - legacy for compatibility
    func selectedDefinition(for globalEffectName: String?) -> EffectDefinition? {
        let index = selectedEffectIndex(for: globalEffectName)
        guard index >= 0 && index < effectDefinitions.count else { return nil }
        return effectDefinitions[index]
    }

    /// Get all navigable parameters for the current effect (flattened for chained effects)
    /// Uses hook's parameterSpecs as source of truth for what parameters exist.
    /// JSON values override defaults from specs.
    /// Returns: array of (hookIndex: Int?, paramName: String, paramValue: AnyCodableValue)
    func navigableParameters(for def: EffectDefinition?) -> [(hookIndex: Int?, paramName: String, value: AnyCodableValue)] {
        guard let def = def else { return [] }

        if def.isChained, let hooks = def.hooks {
            // Flatten all parameters from all hooks
            var result: [(hookIndex: Int?, paramName: String, value: AnyCodableValue)] = []
            for (hookIndex, hook) in hooks.enumerated() {
                let isEnabled = hook.params?["_enabled"]?.boolValue ?? true
                guard isEnabled else { continue }

                let mergedParams = Self.mergedParameters(for: hook)
                for key in mergedParams.keys.sorted() {
                    if let value = mergedParams[key] {
                        result.append((hookIndex: hookIndex, paramName: key, value: value))
                    }
                }
            }
            return result
        } else {
            // Single effect
            let mergedParams = Self.mergedParameters(for: def)
            return mergedParams.keys.sorted().compactMap { key in
                guard let value = mergedParams[key] else { return nil }
                return (hookIndex: nil, paramName: key, value: value)
            }
        }
    }

    /// Merge hook's parameterSpecs with JSON params.
    /// Hook specs define what params exist (source of truth).
    /// JSON values override defaults. Unknown JSON params are ignored.
    static func mergedParameters(for def: EffectDefinition) -> [String: AnyCodableValue] {
        guard let effectType = def.resolvedType else {
            // No type info, fall back to JSON params only
            return (def.params ?? [:]).filter { !$0.key.hasPrefix("_") }
        }

        let specs = EffectRegistry.parameterSpecs(for: effectType)
        var result: [String: AnyCodableValue] = [:]

        // Start with defaults from specs
        for (name, spec) in specs {
            result[name] = spec.defaultValue
        }

        // Overlay JSON values (only for params that exist in specs)
        if let jsonParams = def.params {
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

    /// Move parameter selection up/down
    func moveParameterSelection(by delta: Int, totalParams: Int) {
        guard totalParams > 0 else { return }
        selectedParameterIndex = max(0, min(totalParams - 1, selectedParameterIndex + delta))
    }

    /// Reset parameter selection when effect changes
    func resetParameterSelection() {
        selectedParameterIndex = 0
    }

    /// Update a parameter value for an effect (or child hook in a chain)
    func updateParameter(effectIndex: Int, hookIndex: Int?, paramName: String, value: AnyCodableValue) {
        // Update local state for responsive UI
        updateLocalDefinition(at: effectIndex) { effect in
            if let hookIndex = hookIndex, var hooks = effect.hooks {
                // Update parameter in a chained hook
                guard hookIndex >= 0 && hookIndex < hooks.count else { return effect }
                var hook = hooks[hookIndex]
                var params = hook.params ?? [:]
                params[paramName] = value
                hook = EffectDefinition(name: hook.name, type: hook.type, params: params, hooks: hook.hooks)
                hooks[hookIndex] = hook
                return EffectDefinition(name: effect.name, type: effect.type, params: effect.params, hooks: hooks)
            } else {
                // Update parameter on the effect itself
                var params = effect.params ?? [:]
                params[paramName] = value
                return EffectDefinition(name: effect.name, type: effect.type, params: params, hooks: effect.hooks)
            }
        }
        // Persist to config
        EffectConfigLoader.updateParameter(
            effectIndex: effectIndex,
            hookIndex: hookIndex,
            paramName: paramName,
            value: value
        )
    }

    /// Adjust the currently selected parameter by one step in the given direction (-1 or +1)
    /// Returns true if adjustment was made
    @discardableResult
    func adjustSelectedParameter(direction: Int, effectIndex: Int, definition: EffectDefinition?) -> Bool {
        guard focusedPanel == .parameters else { return false }

        let params = navigableParameters(for: definition)
        guard selectedParameterIndex < params.count else { return false }

        let param = params[selectedParameterIndex]

        // Get the effect type for this specific parameter
        let effectType = getEffectType(for: definition, hookIndex: param.hookIndex)
        let range = getParameterRange(for: effectType, paramName: param.paramName)

        switch param.value {
        case .double(let d):
            let step = getParameterStep(for: effectType, paramName: param.paramName, range: range)
            let newValue = max(range.min, min(range.max, d + step * Double(direction)))
            updateParameter(effectIndex: effectIndex, hookIndex: param.hookIndex, paramName: param.paramName, value: .double(newValue))
            return true

        case .int(let i):
            let step = max(1, Int(getParameterStep(for: effectType, paramName: param.paramName, range: range)))
            let newValue = max(Int(range.min), min(Int(range.max), i + step * direction))
            updateParameter(effectIndex: effectIndex, hookIndex: param.hookIndex, paramName: param.paramName, value: .int(newValue))
            return true

        case .bool(let b):
            updateParameter(effectIndex: effectIndex, hookIndex: param.hookIndex, paramName: param.paramName, value: .bool(!b))
            return true

        case .string:
            return false
        }
    }

    /// Get the effect type for a parameter, handling chained hooks
    private func getEffectType(for def: EffectDefinition?, hookIndex: Int?) -> String? {
        guard let def = def else { return nil }

        if let hookIndex = hookIndex, let hooks = def.hooks, hookIndex < hooks.count {
            return hooks[hookIndex].resolvedType
        }
        return def.resolvedType
    }

    /// Get parameter range from the effect registry
    private func getParameterRange(for effectType: String?, paramName: String) -> (min: Double, max: Double) {
        guard let effectType = effectType,
              let range = EffectRegistry.range(for: effectType, param: paramName) else {
            return (min: 0, max: 1)
        }
        return (min: range.min, max: range.max)
    }

    /// Get the step size for a parameter
    private func getParameterStep(for effectType: String?, paramName: String, range: (min: Double, max: Double)) -> Double {
        if let effectType = effectType,
           let paramRange = EffectRegistry.range(for: effectType, param: paramName),
           let step = paramRange.step {
            return step
        }
        return (range.max - range.min) / 20.0
    }

    /// Add a hook to the currently selected chained effect
    func addHookToChain(effectIndex: Int, hookType: String) {
        // Update local state for responsive UI
        updateLocalDefinition(at: effectIndex) { effect in
            var hooks = effect.hooks ?? []
            let defaults = EffectRegistry.defaults(for: hookType)
            let newHook = EffectDefinition(name: nil, type: hookType, params: defaults, hooks: nil)
            hooks.append(newHook)
            return EffectDefinition(name: effect.name, type: effect.type, params: effect.params, hooks: hooks)
        }
        // Update config (instantiation is debounced in EffectConfigLoader)
        EffectConfigLoader.addHookToChain(effectIndex: effectIndex, hookType: hookType)
    }

    /// Remove a hook from the currently selected chained effect
    func removeHookFromChain(effectIndex: Int, hookIndex: Int) {
        updateLocalDefinition(at: effectIndex) { effect in
            var hooks = effect.hooks ?? []
            guard hookIndex >= 0 && hookIndex < hooks.count else { return effect }
            hooks.remove(at: hookIndex)
            return EffectDefinition(name: effect.name, type: effect.type, params: effect.params, hooks: hooks)
        }
        EffectConfigLoader.removeHookFromChain(effectIndex: effectIndex, hookIndex: hookIndex)
    }

    /// Reorder hooks in the currently selected chained effect
    func reorderHooks(effectIndex: Int, fromIndex: Int, toIndex: Int) {
        updateLocalDefinition(at: effectIndex) { effect in
            var hooks = effect.hooks ?? []
            guard fromIndex >= 0 && fromIndex < hooks.count else { return effect }
            guard toIndex >= 0 && toIndex < hooks.count else { return effect }
            let hook = hooks.remove(at: fromIndex)
            hooks.insert(hook, at: toIndex)
            return EffectDefinition(name: effect.name, type: effect.type, params: effect.params, hooks: hooks)
        }
        EffectConfigLoader.reorderHooksInChain(effectIndex: effectIndex, fromIndex: fromIndex, toIndex: toIndex)
    }

    /// Toggle hook enabled state
    func setHookEnabled(effectIndex: Int, hookIndex: Int, enabled: Bool) {
        updateLocalDefinition(at: effectIndex) { effect in
            var hooks = effect.hooks ?? []
            guard hookIndex >= 0 && hookIndex < hooks.count else { return effect }
            var hook = hooks[hookIndex]
            var params = hook.params ?? [:]
            params["_enabled"] = .bool(enabled)
            hook = EffectDefinition(name: hook.name, type: hook.type, params: params, hooks: hook.hooks)
            hooks[hookIndex] = hook
            return EffectDefinition(name: effect.name, type: effect.type, params: effect.params, hooks: hooks)
        }
        EffectConfigLoader.setHookEnabled(effectIndex: effectIndex, hookIndex: hookIndex, enabled: enabled)
    }

    /// Update the name of the selected effect
    func updateEffectName(effectIndex: Int, name: String) {
        updateLocalDefinition(at: effectIndex) { effect in
            EffectDefinition(name: name, type: effect.type, params: effect.params, hooks: effect.hooks)
        }
        EffectConfigLoader.updateEffectName(effectIndex: effectIndex, name: name)
    }

    /// Available effect types for adding to chains
    var availableEffectTypes: [(type: String, displayName: String)] {
        EffectRegistry.availableEffectTypes
    }

    /// Create a new effect (ChainedHook with Basic as default)
    /// Returns the index of the new effect
    @discardableResult
    func createNewEffect() -> Int {
        let index = EffectConfigLoader.createNewEffect()
        syncFromConfig()  // Sync to get the new effect
        return index
    }

    /// Delete an effect at the given index
    func deleteEffect(at index: Int) {
        guard index >= 0 && index < effectDefinitions.count else { return }
        effectDefinitions.remove(at: index)
        EffectConfigLoader.deleteEffect(at: index)
    }

    // MARK: - Private Helpers

    /// Update a local definition immediately (for responsive UI)
    private func updateLocalDefinition(at index: Int, transform: (EffectDefinition) -> EffectDefinition) {
        guard index >= 0 && index < effectDefinitions.count else { return }
        effectDefinitions[index] = transform(effectDefinitions[index])
    }
}

// MARK: - Main View

struct EffectsEditorView: View {
    @ObservedObject var viewModel: EffectsEditorViewModel
    @ObservedObject var state: HypnographState

    /// Focus state for keyboard navigation
    @FocusState private var isFocused: Bool

    /// Current layer being edited (-1 = global, 0+ = source)
    private var currentLayer: Int {
        state.currentSourceIndex
    }

    /// Effect name for the current layer
    private var currentLayerEffectName: String {
        state.renderHooks.effectName(for: currentLayer)
    }

    /// Computed selected effect index from current layer's effect (-1 = None)
    /// Uses pending selection for immediate UI feedback
    private var selectedEffectIndex: Int {
        viewModel.selectedEffectIndex(for: currentLayerEffectName, layer: currentLayer)
    }

    /// Computed selected definition from current layer's effect
    private var selectedDefinition: EffectDefinition? {
        viewModel.selectedDefinition(for: currentLayerEffectName, layer: currentLayer)
    }

    /// All navigable parameters for the current effect
    private var navigableParams: [(hookIndex: Int?, paramName: String, value: AnyCodableValue)] {
        viewModel.navigableParameters(for: selectedDefinition)
    }

    /// Select an effect with immediate UI feedback
    private func selectEffect(at index: Int) {
        // Update UI immediately via pending selection
        viewModel.setPendingSelection(effectIndex: index, for: currentLayer)

        // Defer the recipe update to next run loop to allow UI to update first
        let layer = currentLayer
        let hooks = state.renderHooks
        DispatchQueue.main.async {
            if index == -1 {
                hooks.setEffect(nil, for: layer)
            } else if index >= 0 && index < Effect.all.count {
                hooks.setEffect(Effect.all[index], for: layer)
            }
        }

        // Clear pending after a short delay to let recipe update propagate
        let vm = viewModel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            vm.clearPendingSelection(for: layer)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header showing which layer is being edited
            HStack {
                Text(state.editingLayerDisplay)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(state.isOnGlobalLayer ? .cyan : .orange)
                Spacer()

                // Close button
                Button(action: {
                    state.isEffectsEditorVisible = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 0) {
                // Left column: Effect list
                effectListColumn
                    .frame(width: 180)
                    .padding(4)
                    .overlay(
                        // Focus indicator for left panel
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.cyan.opacity(0.6), lineWidth: viewModel.focusedPanel == .effects ? 1 : 0)
                    )

                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.horizontal, 4)

                // Right column: Parameters
                parametersColumn
                    .frame(minWidth: 280)
                    .padding(4)
                    .overlay(
                        // Focus indicator for right panel
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.cyan.opacity(0.6), lineWidth: viewModel.focusedPanel == .parameters ? 1 : 0)
                    )
            }
        }
        .foregroundColor(.white)
        .padding(16)
        .background(Color.black.opacity(0.9))
        .frame(width: 480)
        .focusable()
        .focused($isFocused)
        .onKeyPress(.tab) {
            togglePanel()
            return .handled
        }
        .onKeyPress(.upArrow) {
            handleUpDown(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            handleUpDown(delta: 1)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            handleLeftRight(delta: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            handleLeftRight(delta: 1)
            return .handled
        }
        .onAppear {
            // Grab focus when panel appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }

    // MARK: - Navigation Helpers

    private func togglePanel() {
        if viewModel.focusedPanel == .effects && selectedDefinition != nil {
            viewModel.focusedPanel = .parameters
        } else {
            viewModel.focusedPanel = .effects
        }
    }

    private func handleUpDown(delta: Int) {
        switch viewModel.focusedPanel {
        case .effects:
            // Move effect selection up/down
            let defs = viewModel.effectDefinitions
            let currentIndex = selectedEffectIndex  // -1 = None, 0+ = effects
            let newIndex = currentIndex + delta

            if newIndex < -1 {
                // Already at None, can't go higher
                return
            } else if newIndex >= defs.count {
                // Already at bottom
                return
            } else {
                // Select new effect with immediate UI feedback
                selectEffect(at: newIndex)
                viewModel.resetParameterSelection()
            }

        case .parameters:
            viewModel.moveParameterSelection(by: delta, totalParams: navigableParams.count)
        }
    }

    private func handleLeftRight(delta: Int) {
        switch viewModel.focusedPanel {
        case .effects:
            // Left/right does nothing in effects panel
            break
        case .parameters:
            // In parameters panel, left/right adjusts the selected parameter value
            adjustCurrentParameter(delta: delta)
        }
    }

    private func adjustCurrentParameter(delta: Int) {
        viewModel.adjustSelectedParameter(
            direction: delta,
            effectIndex: selectedEffectIndex,
            definition: selectedDefinition
        )
    }

    /// Format hook type for display: "FrameDifferenceHook" -> "Frame Difference"
    private func formatHookType(_ type: String?) -> String? {
        guard let type = type else { return nil }
        return EffectRegistry.formatEffectTypeName(type)
    }

    // MARK: - Effect List Column

    private var effectListColumn: some View {
        // Cache selected index once to avoid recomputing for every row
        let currentlySelected = selectedEffectIndex

        return VStack(alignment: .leading, spacing: 8) {
            Text("Effects")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    // None option (always first)
                    effectNoneRow(isSelected: currentlySelected == -1)

                    Divider()
                        .background(Color.white.opacity(0.2))
                        .padding(.vertical, 2)

                    ForEach(Array(viewModel.effectDefinitions.enumerated()), id: \.offset) { index, def in
                        effectRowCached(index: index, definition: def, isSelected: index == currentlySelected)
                    }
                }
            }

            // Add Effect button at bottom
            Button(action: {
                let newIndex = viewModel.createNewEffect()
                // Select the new effect
                if newIndex < Effect.all.count {
                    state.renderHooks.setEffect(Effect.all[newIndex], for: currentLayer)
                }
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Effect")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.cyan.opacity(0.15))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 12)
    }

    private func effectNoneRow(isSelected: Bool) -> some View {
        Button(action: {
            selectEffect(at: -1)
        }) {
            Text("None")
                .font(.system(.body, design: .monospaced))
                .italic()
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func effectRowCached(index: Int, definition: EffectDefinition, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(definition.name ?? "Unnamed")
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Delete button (only visible when selected)
            if isSelected {
                Button(action: {
                    // Clear selection first if this effect is selected
                    selectEffect(at: -1)
                    viewModel.deleteEffect(at: index)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.white.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectEffect(at: index)
        }
    }

    // MARK: - Parameters Column

    private var parametersColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let def = selectedDefinition {
                // Editable name header
                EditableEffectNameHeader(
                    name: def.name ?? "Unnamed",
                    onSave: { newName in
                        viewModel.updateEffectName(effectIndex: selectedEffectIndex, name: newName)
                    }
                )

                Divider()
                    .background(Color.white.opacity(0.3))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        parametersForDefinitionWithHighlight(def, effectIndex: selectedEffectIndex)
                    }
                }
            } else {
                Text("Select an effect")
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.leading, 12)
    }

    /// Version with highlight support for keyboard/controller navigation
    @ViewBuilder
    private func parametersForDefinitionWithHighlight(_ def: EffectDefinition, effectIndex: Int) -> some View {
        let params = navigableParams
        let isFocused = viewModel.focusedPanel == .parameters

        if def.isChained, let hooks = def.hooks {
            // Chained effect: show each child with heading and controls
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(hooks.enumerated()), id: \.offset) { childIndex, childDef in
                    // Calculate flat parameter start index for this hook
                    let startIndex = params.prefix(while: { ($0.hookIndex ?? -1) < childIndex }).count

                    chainedHookSectionWithHighlight(
                        childDef: childDef,
                        childIndex: childIndex,
                        totalHooks: hooks.count,
                        effectIndex: effectIndex,
                        paramStartIndex: startIndex,
                        isFocused: isFocused
                    )
                }

                // Add effect button
                addEffectButton
            }
        } else {
            // Single effect
            parameterFieldsWithHighlight(for: def, effectIndex: effectIndex, hookIndex: nil, paramStartIndex: 0, isFocused: isFocused)
        }
    }

    @ViewBuilder
    private func parametersForDefinition(_ def: EffectDefinition, effectIndex: Int, hookIndex: Int?) -> some View {
        if def.isChained, let hooks = def.hooks {
            // Chained effect: show each child with heading and controls
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(hooks.enumerated()), id: \.offset) { childIndex, childDef in
                    chainedHookSection(
                        childDef: childDef,
                        childIndex: childIndex,
                        totalHooks: hooks.count,
                        effectIndex: effectIndex
                    )
                }

                // Add effect button
                addEffectButton
            }
        } else {
            // Single effect
            parameterFields(for: def, effectIndex: effectIndex, hookIndex: nil)
        }
    }

    @ViewBuilder
    private func chainedHookSection(childDef: EffectDefinition, childIndex: Int, totalHooks: Int, effectIndex: Int) -> some View {
        let isEnabled = childDef.params?["_enabled"]?.boolValue ?? true

        VStack(alignment: .leading, spacing: 6) {
            // Header with controls
            HStack(spacing: 6) {
                // Reorder buttons (horizontal, larger tap targets)
                HStack(spacing: 0) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(childIndex > 0 ? .white : .white.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if childIndex > 0 {
                                viewModel.reorderHooks(effectIndex: effectIndex, fromIndex: childIndex, toIndex: childIndex - 1)
                            }
                        }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(childIndex < totalHooks - 1 ? .white : .white.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if childIndex < totalHooks - 1 {
                                viewModel.reorderHooks(effectIndex: effectIndex, fromIndex: childIndex, toIndex: childIndex + 1)
                            }
                        }
                }
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)

                // Effect name - use formatted type name if no custom name
                Text(childDef.name ?? formatHookType(childDef.type) ?? "Hook \(childIndex + 1)")
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.5))

                Spacer()

                // Delete button (before enable/disable)
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.removeHookFromChain(effectIndex: effectIndex, hookIndex: childIndex)
                    }
                    .help("Remove from chain")

                // Enable/disable toggle
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isEnabled ? .green : .white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.setHookEnabled(effectIndex: effectIndex, hookIndex: childIndex, enabled: !isEnabled)
                    }
                    .help(isEnabled ? "Disable effect" : "Enable effect")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.15))
            .cornerRadius(6)

            // Parameters (only if enabled)
            if isEnabled {
                parameterFields(for: childDef, effectIndex: effectIndex, hookIndex: childIndex)
                    .padding(.leading, 8)
            }
        }
    }

    @ViewBuilder
    private var addEffectButton: some View {
        Menu {
            ForEach(viewModel.availableEffectTypes, id: \.type) { effect in
                Button(effect.displayName) {
                    viewModel.addHookToChain(effectIndex: selectedEffectIndex, hookType: effect.type)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.white)
                Text("Add Effect")
                    .foregroundColor(.white)
            }
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .tint(.white)
    }

    @ViewBuilder
    private func parameterFields(for def: EffectDefinition, effectIndex: Int, hookIndex: Int?) -> some View {
        // Use hook's parameterSpecs as source of truth, merged with JSON values
        let mergedParams = EffectsEditorViewModel.mergedParameters(for: def)

        if !mergedParams.isEmpty {
            ForEach(Array(mergedParams.keys.sorted()), id: \.self) { key in
                if let value = mergedParams[key] {
                    ParameterSliderRow(
                        name: key,
                        value: value,
                        effectType: def.resolvedType,
                        onChange: { newValue in
                            viewModel.updateParameter(
                                effectIndex: effectIndex,
                                hookIndex: hookIndex,
                                paramName: key,
                                value: newValue
                            )
                        }
                    )
                }
            }
        } else {
            Text("No parameters")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private func parameterFieldsWithHighlight(for def: EffectDefinition, effectIndex: Int, hookIndex: Int?, paramStartIndex: Int, isFocused: Bool) -> some View {
        // Use hook's parameterSpecs as source of truth, merged with JSON values
        let mergedParams = EffectsEditorViewModel.mergedParameters(for: def)
        let sortedKeys = mergedParams.keys.sorted()

        if !sortedKeys.isEmpty {
            ForEach(Array(sortedKeys.enumerated()), id: \.offset) { localIndex, key in
                if let value = mergedParams[key] {
                    let flatIndex = paramStartIndex + localIndex
                    let isHighlighted = isFocused && flatIndex == viewModel.selectedParameterIndex

                    ParameterSliderRow(
                        name: key,
                        value: value,
                        effectType: def.resolvedType,
                        onChange: { newValue in
                            viewModel.updateParameter(
                                effectIndex: effectIndex,
                                hookIndex: hookIndex,
                                paramName: key,
                                value: newValue
                            )
                        },
                        isHighlighted: isHighlighted
                    )
                }
            }
        } else {
            Text("No parameters")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private func chainedHookSectionWithHighlight(childDef: EffectDefinition, childIndex: Int, totalHooks: Int, effectIndex: Int, paramStartIndex: Int, isFocused: Bool) -> some View {
        let isEnabled = childDef.params?["_enabled"]?.boolValue ?? true

        VStack(alignment: .leading, spacing: 6) {
            // Header with controls (larger tap targets)
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(childIndex > 0 ? .white : .white.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if childIndex > 0 {
                                viewModel.reorderHooks(effectIndex: effectIndex, fromIndex: childIndex, toIndex: childIndex - 1)
                            }
                        }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(childIndex < totalHooks - 1 ? .white : .white.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if childIndex < totalHooks - 1 {
                                viewModel.reorderHooks(effectIndex: effectIndex, fromIndex: childIndex, toIndex: childIndex + 1)
                            }
                        }
                }
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)

                Text(formatHookType(childDef.resolvedType) ?? "Unknown")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.5))

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isEnabled ? .green : .white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.setHookEnabled(effectIndex: effectIndex, hookIndex: childIndex, enabled: !isEnabled)
                    }

                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.removeHookFromChain(effectIndex: effectIndex, hookIndex: childIndex)
                    }
            }

            if isEnabled {
                parameterFieldsWithHighlight(for: childDef, effectIndex: effectIndex, hookIndex: childIndex, paramStartIndex: paramStartIndex, isFocused: isFocused)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(6)
    }
}

// MARK: - Parameter Slider Row

struct ParameterSliderRow: View {
    let name: String
    let value: AnyCodableValue
    let effectType: String?
    let onChange: (AnyCodableValue) -> Void
    var isHighlighted: Bool = false

    @State private var textValue: String = ""
    @State private var sliderValue: Double = 0
    /// Track last known external value to detect actual user changes vs. re-render
    @State private var lastExternalValue: Double = 0

    /// Convert camelCase to readable title: "maxHistoryOffset" -> "Max History Offset"
    private var displayName: String {
        Self.formatCamelCase(name)
    }

    /// Convert camelCase string to "Title Case With Spaces"
    static func formatCamelCase(_ input: String) -> String {
        guard !input.isEmpty else { return input }

        var result = ""
        for (index, char) in input.enumerated() {
            if char.isUppercase && index > 0 {
                result += " "
            }
            result += index == 0 ? String(char).uppercased() : String(char)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName)
                .font(.caption)
                .foregroundColor(isHighlighted ? .cyan : .white.opacity(0.7))

            HStack(spacing: 8) {
                switch value {
                case .double:
                    numericSlider(isInt: false)

                    TextField("", text: $textValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .foregroundColor(.black)
                        .onSubmit {
                            if let d = Double(textValue) {
                                sliderValue = d
                                onChange(.double(d))
                            }
                        }

                case .int:
                    // Check if this should really be treated as a double (has decimal range in registry)
                    let treatAsDouble = shouldTreatIntAsDouble
                    numericSlider(isInt: !treatAsDouble)

                    TextField("", text: $textValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .foregroundColor(.black)
                        .onSubmit {
                            if treatAsDouble, let d = Double(textValue) {
                                sliderValue = d
                                onChange(.double(d))
                            } else if let i = Int(textValue) {
                                sliderValue = Double(i)
                                onChange(.int(i))
                            }
                        }

                case .bool(let b):
                    Toggle("", isOn: Binding(
                        get: { b },
                        set: { onChange(.bool($0)) }
                    ))
                    .labelsHidden()

                case .string(let s):
                    TextField("", text: Binding(
                        get: { s },
                        set: { onChange(.string($0)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(.black)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHighlighted ? Color.cyan.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isHighlighted ? Color.cyan.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onAppear {
            initializeValues()
        }
        .onChange(of: value) { _, newValue in
            // Re-initialize when value changes externally
            initializeFromValue(newValue)
        }
    }

    private func initializeValues() {
        initializeFromValue(value)
    }

    private func initializeFromValue(_ val: AnyCodableValue) {
        switch val {
        case .double(let d):
            // Set lastExternalValue BEFORE sliderValue to prevent spurious onChange triggers
            lastExternalValue = d
            sliderValue = d
            textValue = String(format: "%.2f", d)
        case .int(let i):
            // Set lastExternalValue BEFORE sliderValue to prevent spurious onChange triggers
            lastExternalValue = Double(i)
            sliderValue = Double(i)
            textValue = "\(i)"
        default:
            break
        }
    }

    /// Creates a slider without the step parameter to avoid slow tick mark layout
    /// Step values are enforced programmatically in onChange instead
    @ViewBuilder
    private func numericSlider(isInt: Bool) -> some View {
        let range = sliderRange
        let step = safeSliderStep(isInt: isInt, range: range)

        // NOTE: Do NOT use Slider(step:) - it causes AppKit to create tick marks
        // which triggers extremely slow layout calculations (1+ seconds per slider).
        // Instead, we snap values to step in the onChange handler.
        Slider(value: $sliderValue, in: range)
            .frame(minWidth: 100)
            .onChange(of: sliderValue) { _, newVal in
                // Snap to step if we have one
                let snappedVal: Double
                if let step = step, step > 0 {
                    snappedVal = (newVal / step).rounded() * step
                } else {
                    snappedVal = newVal
                }

                // Only trigger onChange if value actually changed from external value
                guard abs(snappedVal - lastExternalValue) > 0.0001 else { return }

                if isInt {
                    textValue = "\(Int(snappedVal))"
                    onChange(.int(Int(snappedVal)))
                } else {
                    textValue = String(format: "%.2f", snappedVal)
                    onChange(.double(snappedVal))
                }
            }
    }

    /// Safe slider step - returns nil if step would be invalid
    private func safeSliderStep(isInt: Bool, range: ClosedRange<Double>) -> Double? {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return nil }

        // For ints, default to step of 1
        if isInt {
            let step = sliderStep ?? 1
            // Ensure step is positive and less than or equal to span
            if step > 0 && step <= span {
                return step
            }
            // Fall back: if span >= 1, use 1, otherwise no step
            return span >= 1 ? 1 : nil
        }

        // For doubles, use registry step if valid
        guard let step = sliderStep, step > 0, step < span else {
            return nil
        }
        return step
    }

    /// Slider range - from registry if available, else heuristic
    /// Always returns a valid range where min < max
    private var sliderRange: ClosedRange<Double> {
        // Try to get range from registry
        if let type = effectType, let range = EffectRegistry.range(for: type, param: name) {
            // Ensure valid range (min < max)
            if range.min < range.max {
                return range.min...range.max
            }
        }

        // Fallback: use value heuristics
        let initialValue: Double
        switch value {
        case .double(let d): initialValue = d
        case .int(let i): initialValue = Double(i)
        default: return 0...100
        }

        if initialValue == 0 {
            return 0...100
        } else if initialValue < 0 {
            return (initialValue * 2)...abs(initialValue * 2)
        } else if initialValue <= 1 {
            return 0...2
        } else if initialValue <= 10 {
            return 0...20
        } else if initialValue <= 100 {
            return 0...(initialValue * 3)
        } else {
            return 0...(initialValue * 3)
        }
    }

    /// Slider step - from registry if available, must be positive and less than range
    private var sliderStep: Double? {
        guard let type = effectType,
              let range = EffectRegistry.range(for: type, param: name),
              let step = range.step,
              step > 0 else {
            return nil
        }
        // Ensure step is less than range span
        let span = sliderRange.upperBound - sliderRange.lowerBound
        guard step < span else { return nil }
        return step
    }

    /// Check if an int value should be treated as a double based on registry range
    /// (e.g., contrast: 1 should be treated as 1.0 with decimal range 0.5-2.0)
    private var shouldTreatIntAsDouble: Bool {
        guard let type = effectType,
              let range = EffectRegistry.range(for: type, param: name) else {
            return false
        }
        // If registry has non-integer bounds, treat as double
        return range.min != floor(range.min) || range.max != floor(range.max) || range.step == nil
    }
}

// MARK: - Editable Effect Name Header

struct EditableEffectNameHeader: View {
    let name: String
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editedName: String = ""

    var body: some View {
        HStack {
            if isEditing {
                TextField("Effect Name", text: $editedName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.black)
                    .onSubmit {
                        saveAndClose()
                    }

                Button(action: saveAndClose) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)

                Button(action: {
                    isEditing = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            } else {
                Text(name)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                editedName = name
                isEditing = true
            }
        }
    }

    private func saveAndClose() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onSave(trimmed)
        }
        isEditing = false
    }
}

