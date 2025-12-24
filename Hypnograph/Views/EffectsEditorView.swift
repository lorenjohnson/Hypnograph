//
//  EffectsEditorView.swift
//  Hypnograph
//
//  Semi-transparent panel for editing effect parameters.
//  Toggle with Shift+E. Changes are live and persist to JSON.
//

import SwiftUI

/// Focus fields for the effects editor
/// Uses SwiftUI's native focus system for tab/shift-tab navigation
enum EffectsEditorField: Hashable {
    case effectList           // Effect selection list
    case parameterList        // Parameter sliders area
    case effectName           // Effect name text field
    case parameterText(Int)   // Parameter text field at index
}

/// View model for the effects editor
/// Handles data operations and effect management.
/// Focus state is managed by SwiftUI's @FocusState in the view.
@MainActor
final class EffectsEditorViewModel: ObservableObject {
    @Published var showingAddEffectPicker: Bool = false

    // MARK: - Navigation State

    /// Which section has keyboard navigation focus (for arrow keys)
    /// This is separate from SwiftUI focus - it tracks which section responds to arrow keys
    @Published var activeSection: EffectsEditorField = .effectList

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

    /// Check if arrow key navigation should be active (not in a text field)
    var isNavigationActive: Bool {
        switch activeSection {
        case .effectList, .parameterList:
            return true
        case .effectName, .parameterText:
            return false
        }
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

    /// Reset a hook's parameters to their default values
    func resetHookToDefaults(effectIndex: Int, hookIndex: Int) {
        updateLocalDefinition(at: effectIndex) { effect in
            var hooks = effect.hooks ?? []
            guard hookIndex >= 0 && hookIndex < hooks.count else { return effect }
            var hook = hooks[hookIndex]
            guard let hookType = hook.resolvedType else { return effect }

            // Get defaults from EffectRegistry, preserve _enabled state
            var defaults = EffectRegistry.defaults(for: hookType)
            if let wasEnabled = hook.params?["_enabled"] {
                defaults["_enabled"] = wasEnabled
            }
            hook = EffectDefinition(name: hook.name, type: hook.type, params: defaults, hooks: hook.hooks)
            hooks[hookIndex] = hook
            return EffectDefinition(name: effect.name, type: effect.type, params: effect.params, hooks: hooks)
        }
        EffectConfigLoader.resetHookToDefaults(effectIndex: effectIndex, hookIndex: hookIndex)
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

    /// SwiftUI focus state - tracks which field has keyboard focus
    @FocusState private var focusedField: EffectsEditorField?

    /// Track which hook in the chain is expanded (only one at a time, first by default)
    @State private var expandedHookIndex: Int = 0

    /// Currently dragged hook index for reordering
    @State private var draggingHookIndex: Int?

    /// Current layer being edited (-1 = global, 0+ = source)
    private var currentLayer: Int {
        state.currentSourceIndex
    }

    /// Effect name for the current layer (from active hooks - edit or live mode)
    private var currentLayerEffectName: String {
        state.activeRenderHooks.effectName(for: currentLayer)
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

    /// Check if currently in a text editing state
    private var isTextEditing: Bool {
        switch focusedField {
        case .effectName, .parameterText:
            return true
        default:
            return false
        }
    }

    /// Select an effect with immediate UI feedback
    private func selectEffect(at index: Int) {
        // Update UI immediately via pending selection
        viewModel.setPendingSelection(effectIndex: index, for: currentLayer)

        // Defer the recipe update to next run loop to allow UI to update first
        // Use activeRenderHooks so effects go to performance display in live mode
        let layer = currentLayer
        let hooks = state.activeRenderHooks
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

                // Add new effect button
                Button(action: {
                    let newIndex = viewModel.createNewEffect()
                    // Select the new effect immediately
                    selectEffect(at: newIndex)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.6))
                .cornerRadius(4)

                // Toggle effects list sidebar button (styled like Performance "Window" button)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.settings.effectsListCollapsed.toggle()
                        state.saveSettings()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sidebar.left")
                        Text(state.settings.effectsListCollapsed ? "Show List" : "Hide List")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(state.settings.effectsListCollapsed ? Color.gray.opacity(0.4) : Color.blue.opacity(0.6))
                .cornerRadius(4)

                // Close button
                Button(action: {
                    state.isEffectsEditorVisible = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 0) {
                if !state.settings.effectsListCollapsed {
                    // Left column: Effect list (Tab stop 1)
                    effectListColumn
                        .frame(width: 160)
                        .focusable()
                        .focused($focusedField, equals: .effectList)
                        .focusSection()
                        .focusEffectDisabled()  // Disable default focus ring on panel
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider()
                        .background(Color.white.opacity(0.3))
                        .padding(.horizontal, 12)
                }

                // Right column: Parameters (Tab stop 2) - expands when list is collapsed
                parametersColumn
                    .frame(minWidth: 240)
                    .focusable()
                    .focused($focusedField, equals: .parameterList)
                    .focusSection()
                    .focusEffectDisabled()  // Disable default focus ring on panel
            }
        }
        .foregroundColor(.white)
        .padding(20)
        .frame(width: 500)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Arrow key navigation - only when not in text fields
        .onKeyPress(.upArrow) {
            guard !isTextEditing else { return .ignored }
            handleUpDown(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !isTextEditing else { return .ignored }
            handleUpDown(delta: 1)
            return .handled
        }
        // Left/right arrow and Tab/Shift-Tab handled natively by SwiftUI focus system
        .onAppear {
            // Auto-expand list when no effect is selected (None)
            if selectedEffectIndex == -1 && state.settings.effectsListCollapsed {
                state.settings.effectsListCollapsed = false
                state.saveSettings()
            }
            // Set initial focus to effect list immediately
            focusedField = .effectList
            viewModel.activeSection = .effectList
        }
        .onChange(of: focusedField) { _, newField in
            // Sync active section when focus changes
            if let field = newField {
                viewModel.activeSection = field
            }
        }
    }

    // MARK: - Navigation Helpers

    private func handleUpDown(delta: Int) {
        switch focusedField {
        case .effectList, .none:
            // Move effect selection up/down with wrap-around
            // Also handle nil focus (initial state before focus is explicitly set)
            let defs = viewModel.effectDefinitions
            let currentIndex = selectedEffectIndex  // -1 = None, 0+ = effects
            var newIndex = currentIndex + delta

            // Total items: None (-1) + effects (0 to defs.count-1)
            // Wrap around: going up from None wraps to last effect, going down from last wraps to None
            if newIndex < -1 {
                // Wrap to last effect
                newIndex = defs.count - 1
            } else if newIndex >= defs.count {
                // Wrap to None
                newIndex = -1
            }

            // Select new effect with immediate UI feedback
            selectEffect(at: newIndex)

            // Ensure focus is set to effect list if it wasn't already
            if focusedField == nil {
                focusedField = .effectList
                viewModel.activeSection = .effectList
            }

        default:
            // In parameters or text fields, let native focus handle navigation
            break
        }
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

                    ForEach(Array(viewModel.effectDefinitions.enumerated()), id: \.offset) { index, def in
                        effectRowCached(index: index, definition: def, isSelected: index == currentlySelected)
                    }
                }
            }
        }
        .padding(.trailing, 12)
    }

    /// Background color for selected effect row
    /// - Cyan when effect list is focused (active highlight)
    /// - Gray when parameters panel is focused (selected but not active)
    private func effectRowBackground(isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        let isEffectListFocused = viewModel.activeSection == .effectList
        return isEffectListFocused ? Color.cyan.opacity(0.3) : Color.white.opacity(0.15)
    }

    private func effectNoneRow(isSelected: Bool) -> some View {
        HStack {
            Text("None")
                .font(.system(.body, design: .monospaced))
                .italic()
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(effectRowBackground(isSelected: isSelected))
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectEffect(at: -1)
        }
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
        .background(effectRowBackground(isSelected: isSelected))
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
                        let currentIndex = selectedEffectIndex
                        viewModel.updateEffectName(effectIndex: currentIndex, name: newName)
                        // Re-apply the effect by index to update the recipe with the new name
                        // This prevents the selection from jumping because the old name no longer matches
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            // After debounce, Effect.all is updated with new name
                            if currentIndex >= 0 && currentIndex < Effect.all.count {
                                state.activeRenderHooks.setEffect(Effect.all[currentIndex], for: currentLayer)
                            }
                        }
                    }
                )

                Divider()
                    .background(Color.white.opacity(0.3))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        parametersForDefinition(def, effectIndex: selectedEffectIndex, hookIndex: nil)
                    }
                }
            } else {
                Text("Select an effect")
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.leading, 12)
    }

    @ViewBuilder
    private func parametersForDefinition(_ def: EffectDefinition, effectIndex: Int, hookIndex: Int?) -> some View {
        if def.isChained, let hooks = def.hooks {
            // Chained effect: show each child with heading and controls
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(hooks.enumerated()), id: \.offset) { childIndex, childDef in
                    chainedHookSection(
                        childDef: childDef,
                        childIndex: childIndex,
                        totalHooks: hooks.count,
                        effectIndex: effectIndex
                    )
                    .opacity(draggingHookIndex == childIndex ? 0.5 : 1.0)
                    .onDrag {
                        draggingHookIndex = childIndex
                        return NSItemProvider(object: String(childIndex) as NSString)
                    }
                    .onDrop(of: [.text], delegate: HookDropDelegate(
                        currentIndex: childIndex,
                        draggingIndex: $draggingHookIndex,
                        effectIndex: effectIndex,
                        onReorder: { from, to in
                            viewModel.reorderHooks(effectIndex: effectIndex, fromIndex: from, toIndex: to)
                        }
                    ))
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
        let isExpanded = expandedHookIndex == childIndex

        VStack(alignment: .leading, spacing: 0) {
            // Header with controls - clicking header expands this hook
            HStack(spacing: 6) {
                // Drag handle indicator
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 20)

                // Effect name - use formatted type name if no custom name
                Text(childDef.name ?? formatHookType(childDef.type) ?? "Hook \(childIndex + 1)")
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.5))

                Spacer()

                // Delete button - borderless style for macOS idiom
                Button(action: {
                    viewModel.removeHookFromChain(effectIndex: effectIndex, hookIndex: childIndex)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Remove from chain")

                // Reset to defaults button
                Button(action: {
                    viewModel.resetHookToDefaults(effectIndex: effectIndex, hookIndex: childIndex)
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Reset to defaults")

                // Enable/disable toggle - real Toggle for keyboard/focus support
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { viewModel.setHookEnabled(effectIndex: effectIndex, hookIndex: childIndex, enabled: $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(isEnabled ? "Disable effect" : "Enable effect")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isExpanded ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedHookIndex = childIndex
                }
            }

            // Parameters (only if enabled AND expanded)
            if isEnabled && isExpanded {
                parameterFields(for: childDef, effectIndex: effectIndex, hookIndex: childIndex)
                    .padding(.leading, 28)
                    .padding(.top, 8)
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
        let specs = def.resolvedType.map { EffectRegistry.parameterSpecs(for: $0) } ?? [:]

        if !mergedParams.isEmpty {
            ForEach(Array(mergedParams.keys.sorted()), id: \.self) { key in
                if let value = mergedParams[key] {
                    ParameterSliderRow(
                        name: key,
                        value: value,
                        effectType: def.resolvedType,
                        spec: specs[key],
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

}

// MARK: - Parameter Slider Row

struct ParameterSliderRow: View {
    let name: String
    let value: AnyCodableValue
    let effectType: String?
    let spec: ParameterSpec?
    let onChange: (AnyCodableValue) -> Void

    @State private var textValue: String = ""
    @State private var sliderValue: Double = 0
    /// Track last known external value to detect actual user changes vs. re-render
    @State private var lastExternalValue: Double = 0
    @FocusState private var isTextFieldFocused: Bool

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
            // Label row with reset button right-aligned
            HStack {
                Text(displayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button(action: resetToDefault) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.borderless)
                .help("Reset to default")
            }

            HStack(spacing: 8) {
                switch value {
                case .double:
                    numericSlider(isInt: false)
                    compactTextField(onSubmit: {
                        if let d = Double(textValue) {
                            sliderValue = d
                            onChange(.double(d))
                        }
                    })

                case .int:
                    // Check if this should really be treated as a double (has decimal range in registry)
                    let treatAsDouble = shouldTreatIntAsDouble
                    numericSlider(isInt: !treatAsDouble)
                    compactTextField(onSubmit: {
                        if treatAsDouble, let d = Double(textValue) {
                            sliderValue = d
                            onChange(.double(d))
                        } else if let i = Int(textValue) {
                            sliderValue = Double(i)
                            onChange(.int(i))
                        }
                    })

                case .bool(let b):
                    Toggle("", isOn: Binding(
                        get: { b },
                        set: { onChange(.bool($0)) }
                    ))
                    .labelsHidden()

                case .string(let s):
                    // Check if this is a color parameter
                    if spec?.isColor == true {
                        colorPicker(currentHex: s)
                    } else if let options = spec?.choiceOptions {
                        // Check if this is a choice parameter
                        choicePicker(currentValue: s, options: options)
                    } else if spec?.isFile == true {
                        // File picker parameter
                        filePicker(currentValue: s, spec: spec!)
                    } else {
                        TextField("", text: Binding(
                            get: { s },
                            set: { onChange(.string($0)) }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(isTextFieldFocused ? Color.white : Color.white.opacity(0.1))
                        .foregroundColor(isTextFieldFocused ? .black : .white)
                        .cornerRadius(3)
                        .focused($isTextFieldFocused)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .focusable()  // Makes this row participate in Tab navigation
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

    /// Get the default value for this parameter from the registry
    private var defaultValue: AnyCodableValue? {
        guard let type = effectType else { return nil }
        return EffectRegistry.defaults(for: type)[name]
    }

    /// Reset the parameter to its default value
    private func resetToDefault() {
        guard let defaultVal = defaultValue else { return }
        switch defaultVal {
        case .double(let d):
            sliderValue = d
            lastExternalValue = d
            textValue = String(format: "%.2f", d)
            onChange(.double(d))
        case .int(let i):
            sliderValue = Double(i)
            lastExternalValue = Double(i)
            textValue = "\(i)"
            onChange(.int(i))
        case .bool(let b):
            onChange(.bool(b))
        case .string(let s):
            onChange(.string(s))
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

    /// Compact text field - shows white background only when focused
    @ViewBuilder
    private func compactTextField(onSubmit: @escaping () -> Void) -> some View {
        TextField("", text: $textValue)
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .frame(width: 50)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isTextFieldFocused ? Color.white : Color.white.opacity(0.1))
            .foregroundColor(isTextFieldFocused ? .black : .white)
            .cornerRadius(3)
            .focused($isTextFieldFocused)
            .onSubmit(onSubmit)
    }

    /// Choice picker for enum-style parameters
    @ViewBuilder
    private func choicePicker(currentValue: String, options: [(key: String, label: String)]) -> some View {
        Picker("", selection: Binding(
            get: { currentValue },
            set: { onChange(.string($0)) }
        )) {
            ForEach(options, id: \.key) { option in
                Text(option.label).tag(option.key)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Color picker for hex color parameters
    @ViewBuilder
    private func colorPicker(currentHex: String) -> some View {
        let nsColor = NSColor.fromHex(currentHex) ?? .white
        let swiftUIColor = Color(nsColor: nsColor)

        ColorPicker("", selection: Binding(
            get: { swiftUIColor },
            set: { newColor in
                // Convert SwiftUI Color back to hex
                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                    let r = Int(components.redComponent * 255)
                    let g = Int(components.greenComponent * 255)
                    let b = Int(components.blueComponent * 255)
                    let hex = String(format: "#%02X%02X%02X", r, g, b)
                    onChange(.string(hex))
                }
            }
        ))
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// File picker for file-based parameters (e.g., LUT files)
    @ViewBuilder
    private func filePicker(currentValue: String, spec: ParameterSpec) -> some View {
        let files = spec.availableFiles

        if files.isEmpty {
            // No files found - show placeholder with directory info
            HStack {
                Text("No files found")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                if let info = spec.filePickerInfo {
                    Button(action: {
                        NSWorkspace.shared.open(info.directory)
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Open \(info.directory.lastPathComponent) folder")

                    Button(action: {
                        ParameterSpec.clearFileListCache()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh file list")
                }
            }
        } else {
            HStack(spacing: 4) {
                Picker("", selection: Binding(
                    get: { currentValue },
                    set: { onChange(.string($0)) }
                )) {
                    Text("Select file...").tag("")
                    ForEach(files, id: \.key) { file in
                        Text(file.label).tag(file.key)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                // Refresh button to rescan for new files
                Button(action: {
                    ParameterSpec.clearFileListCache()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Refresh file list")
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
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack {
            if isEditing {
                TextField("Effect Name", text: $editedName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.black)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        saveAndClose()
                    }
                    .onAppear {
                        // Auto-focus the text field when editing starts
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isTextFieldFocused = true
                        }
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

// MARK: - Hook Drag and Drop Delegate

/// Delegate for handling drag and drop reordering of hooks in a chain
struct HookDropDelegate: DropDelegate {
    let currentIndex: Int
    @Binding var draggingIndex: Int?
    let effectIndex: Int
    let onReorder: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggingIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let fromIndex = draggingIndex, fromIndex != currentIndex else { return }
        onReorder(fromIndex, currentIndex)
        draggingIndex = currentIndex
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // No action needed
    }
}
