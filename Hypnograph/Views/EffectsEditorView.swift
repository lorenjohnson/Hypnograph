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

    /// Get current effect definitions with their parameters
    var effectDefinitions: [EffectDefinition] {
        EffectConfigLoader.currentDefinitions
    }

    /// Get selected effect index from global effect name (-1 = None)
    func selectedEffectIndex(for globalEffectName: String?) -> Int {
        guard let name = globalEffectName, name != "None" else { return -1 }
        return effectDefinitions.firstIndex(where: { $0.name == name }) ?? -1
    }

    /// Currently selected effect definition (nil for "None")
    func selectedDefinition(for globalEffectName: String?) -> EffectDefinition? {
        let index = selectedEffectIndex(for: globalEffectName)
        guard index >= 0 && index < effectDefinitions.count else { return nil }
        return effectDefinitions[index]
    }

    /// Get all navigable parameters for the current effect (flattened for chained effects)
    /// Returns: array of (hookIndex: Int?, paramName: String, paramValue: AnyCodableValue)
    func navigableParameters(for def: EffectDefinition?) -> [(hookIndex: Int?, paramName: String, value: AnyCodableValue)] {
        guard let def = def else { return [] }

        if def.isChained, let hooks = def.hooks {
            // Flatten all parameters from all hooks
            var result: [(hookIndex: Int?, paramName: String, value: AnyCodableValue)] = []
            for (hookIndex, hook) in hooks.enumerated() {
                let isEnabled = hook.params?["_enabled"]?.boolValue ?? true
                guard isEnabled else { continue }

                let visibleParams = (hook.params ?? [:]).filter { !$0.key.hasPrefix("_") }
                for key in visibleParams.keys.sorted() {
                    if let value = visibleParams[key] {
                        result.append((hookIndex: hookIndex, paramName: key, value: value))
                    }
                }
            }
            return result
        } else {
            // Single effect
            let visibleParams = (def.params ?? [:]).filter { !$0.key.hasPrefix("_") }
            return visibleParams.keys.sorted().compactMap { key in
                guard let value = visibleParams[key] else { return nil }
                return (hookIndex: nil, paramName: key, value: value)
            }
        }
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
        EffectConfigLoader.updateParameter(
            effectIndex: effectIndex,
            hookIndex: hookIndex,
            paramName: paramName,
            value: value
        )
    }

    /// Add a hook to the currently selected chained effect
    func addHookToChain(effectIndex: Int, hookType: String) {
        EffectConfigLoader.addHookToChain(effectIndex: effectIndex, hookType: hookType)
    }

    /// Remove a hook from the currently selected chained effect
    func removeHookFromChain(effectIndex: Int, hookIndex: Int) {
        EffectConfigLoader.removeHookFromChain(effectIndex: effectIndex, hookIndex: hookIndex)
    }

    /// Reorder hooks in the currently selected chained effect
    func reorderHooks(effectIndex: Int, fromIndex: Int, toIndex: Int) {
        EffectConfigLoader.reorderHooksInChain(effectIndex: effectIndex, fromIndex: fromIndex, toIndex: toIndex)
    }

    /// Toggle hook enabled state
    func setHookEnabled(effectIndex: Int, hookIndex: Int, enabled: Bool) {
        EffectConfigLoader.setHookEnabled(effectIndex: effectIndex, hookIndex: hookIndex, enabled: enabled)
    }

    /// Update the name of the selected effect
    func updateEffectName(effectIndex: Int, name: String) {
        EffectConfigLoader.updateEffectName(effectIndex: effectIndex, name: name)
    }

    /// Available effect types for adding to chains
    var availableEffectTypes: [(type: String, displayName: String)] {
        EffectRegistry.availableEffectTypes
    }
}

// MARK: - Main View

struct EffectsEditorView: View {
    @ObservedObject var viewModel: EffectsEditorViewModel
    @ObservedObject var state: HypnographState

    /// Current layer being edited (-1 = global, 0+ = source)
    private var currentLayer: Int {
        state.currentSourceIndex
    }

    /// Effect name for the current layer
    private var currentLayerEffectName: String {
        state.renderHooks.effectName(for: currentLayer)
    }

    /// Computed selected effect index from current layer's effect (-1 = None)
    private var selectedEffectIndex: Int {
        viewModel.selectedEffectIndex(for: currentLayerEffectName)
    }

    /// Computed selected definition from current layer's effect
    private var selectedDefinition: EffectDefinition? {
        viewModel.selectedDefinition(for: currentLayerEffectName)
    }

    /// All navigable parameters for the current effect
    private var navigableParams: [(hookIndex: Int?, paramName: String, value: AnyCodableValue)] {
        viewModel.navigableParameters(for: selectedDefinition)
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
            }
            .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 0) {
                // Left column: Effect list
                effectListColumn
                    .frame(width: 180)
                    .overlay(
                        // Focus indicator for left panel
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.cyan, lineWidth: viewModel.focusedPanel == .effects ? 2 : 0)
                            .padding(2)
                    )

                Divider()
                    .background(Color.white.opacity(0.3))

                // Right column: Parameters
                parametersColumn
                    .frame(minWidth: 280)
                    .overlay(
                        // Focus indicator for right panel
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.cyan, lineWidth: viewModel.focusedPanel == .parameters ? 2 : 0)
                            .padding(2)
                    )
            }
        }
        .foregroundColor(.white)
        .padding(16)
        .background(
            Color.black.opacity(0.75)
                .cornerRadius(12)
        )
        .frame(maxWidth: 500, maxHeight: 600)
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
            if viewModel.focusedPanel == .parameters {
                viewModel.focusedPanel = .effects
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if viewModel.focusedPanel == .effects && selectedDefinition != nil {
                viewModel.focusedPanel = .parameters
            }
            return .handled
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
            } else if newIndex == -1 {
                // Select None
                state.renderHooks.setEffect(nil, for: currentLayer)
                viewModel.resetParameterSelection()
            } else if newIndex >= 0 && newIndex < Effect.all.count {
                state.renderHooks.setEffect(Effect.all[newIndex], for: currentLayer)
                viewModel.resetParameterSelection()
            }

        case .parameters:
            viewModel.moveParameterSelection(by: delta, totalParams: navigableParams.count)
        }
    }

    // MARK: - Effect List Column

    private var effectListColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effects")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // None option (always first)
                    noneRow

                    Divider()
                        .background(Color.white.opacity(0.2))
                        .padding(.vertical, 2)

                    ForEach(Array(viewModel.effectDefinitions.enumerated()), id: \.offset) { index, def in
                        effectRow(index: index, definition: def)
                    }
                }
            }
        }
        .padding(.trailing, 12)
    }

    private var noneRow: some View {
        let isSelected = selectedEffectIndex == -1

        return Button(action: {
            state.renderHooks.setEffect(nil, for: currentLayer)
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

    private func effectRow(index: Int, definition: EffectDefinition) -> some View {
        let isSelected = index == selectedEffectIndex

        return Button(action: {
            // Set effect for the current layer
            if index >= 0 && index < Effect.all.count {
                let effect = Effect.all[index]
                state.renderHooks.setEffect(effect, for: currentLayer)
            }
        }) {
            Text(definition.name ?? "Unnamed")
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
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
                    VStack(alignment: .leading, spacing: 12) {
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
                // Reorder buttons (horizontal, more compact)
                HStack(spacing: 2) {
                    Button(action: {
                        if childIndex > 0 {
                            viewModel.reorderHooks(effectIndex: effectIndex, fromIndex: childIndex, toIndex: childIndex - 1)
                        }
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 16, height: 16)
                            .foregroundColor(childIndex > 0 ? .white : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(childIndex == 0)

                    Button(action: {
                        if childIndex < totalHooks - 1 {
                            viewModel.reorderHooks(effectIndex: effectIndex, fromIndex: childIndex, toIndex: childIndex + 1)
                        }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 16, height: 16)
                            .foregroundColor(childIndex < totalHooks - 1 ? .white : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(childIndex == totalHooks - 1)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)

                // Effect name
                Text(childDef.name ?? childDef.type ?? "Hook \(childIndex + 1)")
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.5))

                Spacer()

                // Delete button (before enable/disable)
                Button(action: {
                    viewModel.removeHookFromChain(effectIndex: effectIndex, hookIndex: childIndex)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove from chain")

                // Enable/disable toggle
                Button(action: {
                    viewModel.setHookEnabled(effectIndex: effectIndex, hookIndex: childIndex, enabled: !isEnabled)
                }) {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isEnabled ? .green : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
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
                Text("Add Effect")
            }
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2))
            .cornerRadius(6)
        }
        .foregroundColor(.white)
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private func parameterFields(for def: EffectDefinition, effectIndex: Int, hookIndex: Int?) -> some View {
        // Filter out internal params (prefixed with _)
        let visibleParams = (def.params ?? [:]).filter { !$0.key.hasPrefix("_") }

        if !visibleParams.isEmpty {
            ForEach(Array(visibleParams.keys.sorted()), id: \.self) { key in
                if let value = visibleParams[key] {
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
        let visibleParams = (def.params ?? [:]).filter { !$0.key.hasPrefix("_") }
        let sortedKeys = visibleParams.keys.sorted()

        if !sortedKeys.isEmpty {
            ForEach(Array(sortedKeys.enumerated()), id: \.offset) { localIndex, key in
                if let value = visibleParams[key] {
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
            // Header with controls (same as chainedHookSection)
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    Button(action: {
                        if childIndex > 0 {
                            viewModel.reorderHooks(effectIndex: effectIndex, fromIndex: childIndex, toIndex: childIndex - 1)
                        }
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 16, height: 16)
                            .foregroundColor(childIndex > 0 ? .white : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(childIndex == 0)

                    Button(action: {
                        if childIndex < totalHooks - 1 {
                            viewModel.reorderHooks(effectIndex: effectIndex, fromIndex: childIndex, toIndex: childIndex + 1)
                        }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 16, height: 16)
                            .foregroundColor(childIndex < totalHooks - 1 ? .white : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(childIndex == totalHooks - 1)
                }

                Text(childDef.resolvedType ?? "Unknown")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.5))

                Spacer()

                Button(action: {
                    viewModel.setHookEnabled(effectIndex: effectIndex, hookIndex: childIndex, enabled: !isEnabled)
                }) {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isEnabled ? .green : .white.opacity(0.5))
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.removeHookFromChain(effectIndex: effectIndex, hookIndex: childIndex)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
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
            sliderValue = d
            textValue = String(format: "%.2f", d)
        case .int(let i):
            sliderValue = Double(i)
            textValue = "\(i)"
        default:
            break
        }
    }

    /// Creates a slider with safe step handling
    @ViewBuilder
    private func numericSlider(isInt: Bool) -> some View {
        let range = sliderRange
        let step = safeSliderStep(isInt: isInt, range: range)

        if let step = step {
            Slider(value: $sliderValue, in: range, step: step)
                .frame(minWidth: 100)
                .onChange(of: sliderValue) { _, newVal in
                    if isInt {
                        textValue = "\(Int(newVal))"
                        onChange(.int(Int(newVal)))
                    } else {
                        textValue = String(format: "%.2f", newVal)
                        onChange(.double(newVal))
                    }
                }
        } else {
            Slider(value: $sliderValue, in: range)
                .frame(minWidth: 100)
                .onChange(of: sliderValue) { _, newVal in
                    if isInt {
                        textValue = "\(Int(newVal))"
                        onChange(.int(Int(newVal)))
                    } else {
                        textValue = String(format: "%.2f", newVal)
                        onChange(.double(newVal))
                    }
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

                Button(action: {
                    editedName = name
                    isEditing = true
                }) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func saveAndClose() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onSave(trimmed)
        }
        isEditing = false
    }
}

