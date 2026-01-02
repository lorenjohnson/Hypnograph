//
//  EffectsEditorView.swift
//  Hypnograph
//
//  Semi-transparent panel for editing effect parameters.
//  Toggle with Shift+E. Changes are live and persist to JSON.
//

import SwiftUI
import Combine

/// Focus fields for the effects editor
/// Uses SwiftUI's native focus system for tab/shift-tab navigation
enum EffectsEditorField: Hashable {
    case effectList           // Effect selection list
    case parameterList        // Parameter sliders area
    case effectName           // Effect name text field
    case parameterText(Int)   // Parameter text field at index
    case effectCheckbox(Int)  // Effect enable/disable checkbox at index
}

/// View model for the effects editor
/// Handles data operations and effect management.
/// Focus state is managed by SwiftUI's @FocusState in the view.
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

        // Subscribe to session's $chains publisher to sync AFTER chains change
        // (Not objectWillChange which fires BEFORE the change)
        sessionCancellable = session.$chains
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

    /// Legacy: Sync from config loader (for backwards compatibility during migration)
    func syncFromConfig() {
        syncFromSession()
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

    /// Get selected effect index from global effect name (-1 = None) - legacy for compatibility
    func selectedEffectIndex(for globalEffectName: String?) -> Int {
        guard let name = globalEffectName, name != "None" else { return -1 }
        return effectChains.firstIndex(where: { $0.name == name }) ?? -1
    }

    /// Currently selected effect chain (nil for "None")
    func selectedChain(for globalEffectName: String?, layer: Int) -> EffectChain? {
        let index = selectedEffectIndex(for: globalEffectName, layer: layer)
        guard index >= 0 && index < effectChains.count else { return nil }
        return effectChains[index]
    }

    /// Currently selected effect chain - legacy for compatibility
    func selectedChain(for globalEffectName: String?) -> EffectChain? {
        let index = selectedEffectIndex(for: globalEffectName)
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
                var updatedChain = chain
                var params = updatedChain.effects[defIndex].params ?? [:]
                params[paramName] = value
                updatedChain.effects[defIndex].params = params
                return updatedChain
            } else {
                // Update parameter on the chain itself (future: chain-level params)
                var updatedChain = chain
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

// MARK: - Main View

struct EffectsEditorView: View {
    @ObservedObject var viewModel: EffectsEditorViewModel
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream

    /// SwiftUI focus state - tracks which field has keyboard focus
    @FocusState private var focusedField: EffectsEditorField?

    /// Track which effects in the chain are expanded (multiple allowed)
    @State private var expandedEffectIndices: Set<Int> = []

    /// Currently dragged effect index for reordering
    @State private var draggingEffectIndex: Int?

    /// Show confirmation dialog for restoring default effects library
    @State private var showRestoreConfirmation = false

    /// Current layer being edited (-1 = global, 0+ = source)
    private var currentLayer: Int {
        dream.activePlayer.currentSourceIndex
    }

    /// Effect name for the current layer (from active effects - edit or live mode)
    private var currentLayerEffectName: String {
        dream.activeEffectManager.effectName(for: currentLayer)
    }

    /// Computed selected effect index from current layer's effect (-1 = None)
    /// Uses pending selection for immediate UI feedback
    private var selectedEffectIndex: Int {
        viewModel.selectedEffectIndex(for: currentLayerEffectName, layer: currentLayer)
    }

    /// Computed selected chain from current layer's effect
    /// Reads from the recipe's stored chain (per-hypnogram), not the library
    private var selectedDefinition: EffectChain? {
        dream.activeEffectManager.effectChain(for: currentLayer)
    }

    /// Number of effects in the current effect chain
    private var currentEffectsCount: Int {
        selectedDefinition?.effects.count ?? 0
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
    /// Copies the library chain into the recipe and instantiates the effect
    private func selectEffect(at index: Int) {
        // Update UI immediately via pending selection
        viewModel.setPendingSelection(effectIndex: index, for: currentLayer)

        // Get the library chain to copy into the recipe
        let libraryChains = viewModel.effectChains
        let chain: EffectChain? = (index >= 0 && index < libraryChains.count)
            ? libraryChains[index]
            : nil

        // Defer the recipe update to next run loop to allow UI to update first
        // Use activeEffectManager so effects go to performance display in live mode
        let layer = currentLayer
        let effectManager = dream.activeEffectManager
        let isLive = dream.isLiveMode
        print("🎨 EffectsEditor: selectEffect(\(index)) for layer \(layer), isLive=\(isLive)")
        DispatchQueue.main.async {
            // Set effect from chain - this copies the chain into the recipe
            // and instantiates the effect from it
            effectManager.setEffect(from: chain, for: layer)
            if let c = chain {
                print("🎨 EffectsEditor: Set effect '\(c.name ?? "unnamed")' for layer \(layer)")
            } else {
                print("🎨 EffectsEditor: Cleared effect for layer \(layer)")
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
                // Toggle effects list sidebar button (icon only with tooltip)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.settings.effectsListCollapsed.toggle()
                        state.saveSettings()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(state.settings.effectsListCollapsed ? Color.gray.opacity(0.4) : Color.blue.opacity(0.6))
                .cornerRadius(4)
                .hudTooltip(state.settings.effectsListCollapsed ? "Show Effects List" : "Hide Effects List")

                Text(dream.activePlayer.editingLayerDisplay)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(dream.activePlayer.isOnGlobalLayer ? .cyan : .orange)

                Spacer()

                // Close button
                Button(action: {
                    state.windowState.set("effectsEditor", visible: false)
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
            // Connect view model to the active session
            viewModel.session = dream.effectsSession

            // Auto-expand list when no effect is selected (None)
            if selectedEffectIndex == -1 && state.settings.effectsListCollapsed {
                state.settings.effectsListCollapsed = false
                state.saveSettings()
            }
            // Set initial focus to effect list immediately
            focusedField = .effectList
            viewModel.activeSection = .effectList
        }
        .onChange(of: dream.isLiveMode) { _, _ in
            // Update session when performance mode changes (Edit ↔ Live)
            viewModel.session = dream.effectsSession
        }
        .onChange(of: dream.mode) { _, _ in
            // Update session when dream mode changes (Montage ↔ Sequence)
            viewModel.session = dream.effectsSession
        }
        .onChange(of: focusedField) { _, newField in
            // Sync active section when focus changes
            if let field = newField {
                viewModel.activeSection = field
            }
        }
        .confirmationDialog(
            "Restore Default Effects Library?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                guard let session = viewModel.session else { return }
                EffectChainLibraryActions.restoreDefaultLibrary(session: session) {
                    viewModel.syncFromSession()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your current effects library with the built-in defaults. This cannot be undone.")
        }
    }

    // MARK: - Navigation Helpers

    private func handleUpDown(delta: Int) {
        switch focusedField {
        case .effectList:
            // Move effect selection up/down with wrap-around
            let chains = viewModel.effectChains
            let currentIndex = selectedEffectIndex  // -1 = None, 0+ = effects
            var newIndex = currentIndex + delta

            // Total items: None (-1) + effects (0 to chains.count-1)
            // Wrap around: going up from None wraps to last effect, going down from last wraps to None
            if newIndex < -1 {
                // Wrap to last effect
                newIndex = chains.count - 1
            } else if newIndex >= chains.count {
                // Wrap to None
                newIndex = -1
            }

            // Select new effect with immediate UI feedback
            selectEffect(at: newIndex)

        default:
            // In text fields, let native focus handle navigation
            break
        }
    }

    /// Format effect type for display: "FrameDifferenceEffect" -> "Frame Difference"
    private func formatEffectType(_ type: String?) -> String? {
        guard let type = type else { return nil }
        return EffectRegistry.formatEffectTypeName(type)
    }

    // MARK: - Effect List Column

    private var effectListColumn: some View {
        // Cache selected index once to avoid recomputing for every row
        let currentlySelected = selectedEffectIndex

        return VStack(alignment: .leading, spacing: 8) {
            // Effects header with add button
            HStack {
                Text("Effects")
                    .font(.headline)

                Spacer()

                // Add new effect button
                Button(action: {
                    let newIndex = viewModel.createNewEffect()
                    selectEffect(at: newIndex)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .background(Color.cyan.opacity(0.6))
                .cornerRadius(4)
                .hudTooltip("Add New Effect")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    // None option (always first)
                    effectNoneRow(isSelected: currentlySelected == -1)

                    ForEach(Array(viewModel.effectChains.enumerated()), id: \.offset) { index, chain in
                        effectRowCached(index: index, chain: chain, isSelected: index == currentlySelected)
                    }
                }
            }

            Spacer()

            // Library action buttons
            effectLibraryButtons
        }
        .padding(.trailing, 12)
    }

    // MARK: - Effect Library Buttons

    /// Buttons for saving and loading effect chain libraries
    private var effectLibraryButtons: some View {
        HStack(alignment: .center, spacing: 8) {
            // Restore Default Effects Library
            Button(action: restoreDefaultLibrary) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .hudTooltip("Restore Default Effects Library")

            // Save to Default Library
            Button(action: saveToDefaultLibrary) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .hudTooltip("Save to Default Effects Library")

            // Save to File (with file picker)
            Button(action: saveLibraryToFile) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .hudTooltip("Save Effects Library to File")

            // Load from File (JSON or Hypnogram)
            Button(action: loadLibraryFromFile) {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .hudTooltip("Load Effects from File (.json, .hypno, or .hypnogram)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Library Actions

    private func restoreDefaultLibrary() {
        showRestoreConfirmation = true
    }

    /// Save current effect chains to the default library location
    private func saveToDefaultLibrary() {
        guard let session = viewModel.session else { return }
        EffectChainLibraryActions.saveToDefaultLibrary(session: session)
    }

    /// Save current effect chains to a user-chosen file
    private func saveLibraryToFile() {
        guard let session = viewModel.session else { return }
        EffectChainLibraryActions.saveLibraryToFile(session: session)
    }

    /// Load effect chain library from a file (.json, .hypno, or .hypnogram)
    private func loadLibraryFromFile() {
        guard let session = viewModel.session else { return }
        EffectChainLibraryActions.loadLibraryFromFile(session: session) {
            viewModel.syncFromSession()
            // Restore window and responder chain after panel closes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Force window to reclaim key status and reset responder chain
                if let window = NSApp.mainWindow {
                    window.makeKeyAndOrderFront(nil)
                    // Clear first responder to reset the responder chain
                    window.makeFirstResponder(nil)
                }
                focusedField = .effectList
            }
        }
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

    private func effectRowCached(index: Int, chain: EffectChain, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(chain.name ?? "Unnamed")
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
                        // Update session (for persistence)
                        viewModel.updateEffectName(effectIndex: selectedEffectIndex, name: newName)
                        // Also update the recipe's chain directly (reapplyActiveEffects can't
                        // find the chain by old name after a rename)
                        dream.activeEffectManager.updateChainName(for: currentLayer, name: newName)
                    },
                    focusedField: $focusedField
                )

                Divider()
                    .background(Color.white.opacity(0.3))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        parametersForChain(def, layer: currentLayer)
                    }
                }
            } else {
                Text("Select an effect")
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.leading, state.settings.effectsListCollapsed ? 0 : 12)
    }

    @ViewBuilder
    private func parametersForChain(_ chain: EffectChain, layer: Int) -> some View {
        // Effect chain: show each effect with heading and controls
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chain.effects.enumerated()), id: \.offset) { childIndex, effectDef in
                chainedEffectSection(
                    effectDef: effectDef,
                    childIndex: childIndex,
                    totalEffects: chain.effects.count,
                    layer: layer
                )
                .opacity(draggingEffectIndex == childIndex ? 0.5 : 1.0)
                .onDrag {
                    draggingEffectIndex = childIndex
                    return NSItemProvider(object: String(childIndex) as NSString)
                }
                .onDrop(of: [.text], delegate: EffectDropDelegate(
                    currentIndex: childIndex,
                    draggingIndex: $draggingEffectIndex,
                    effectIndex: selectedEffectIndex,
                    onReorder: { from, to in
                        // Update session (for persistence) - the session's onChainUpdated callback
                        // will trigger effectManager.reapplyActiveEffects() for immediate preview
                        viewModel.reorderEffects(effectIndex: selectedEffectIndex, fromIndex: from, toIndex: to)
                    }
                ))
            }

            // Add effect button
            addEffectButton
        }
    }

    @ViewBuilder
    private func chainedEffectSection(effectDef: EffectDefinition, childIndex: Int, totalEffects: Int, layer: Int) -> some View {
        let isEnabled = effectDef.params?["_enabled"]?.boolValue ?? true
        let isExpanded = expandedEffectIndices.contains(childIndex)

        VStack(alignment: .leading, spacing: 0) {
            // Header with controls - tap anywhere (except buttons) to expand/collapse
            HStack(spacing: 6) {
                // Drag handle indicator
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 20)

                // Effect name
                Text(formatEffectType(effectDef.type) ?? "Effect \(childIndex + 1)")
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.5))

                Spacer()

                // Delete button
                Button(action: {
                    // Update session (for persistence) - the session's onChainUpdated callback
                    // will trigger effectManager.reapplyActiveEffects() for immediate preview
                    viewModel.removeEffectFromChain(effectIndex: selectedEffectIndex, effectDefIndex: childIndex)
                    // Clean up expanded indices
                    expandedEffectIndices.remove(childIndex)
                    // Shift down indices above the deleted one
                    expandedEffectIndices = Set(expandedEffectIndices.map { $0 > childIndex ? $0 - 1 : $0 })
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Remove from chain")

                // Reset to defaults button
                Button(action: {
                    // Update session (for persistence) - the session's onChainUpdated callback
                    // will trigger effectManager.reapplyActiveEffects() for immediate preview
                    viewModel.resetEffectToDefaults(effectIndex: selectedEffectIndex, effectDefIndex: childIndex)
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Reset to defaults")

                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        // Update session (for persistence) - the session's onChainUpdated callback
                        // will trigger effectManager.reapplyActiveEffects() for immediate preview
                        viewModel.updateParameter(
                            effectIndex: selectedEffectIndex,
                            effectDefIndex: childIndex,
                            paramName: "_enabled",
                            value: .bool(newValue)
                        )
                    }
                ))
                .toggleStyle(.darkModeSwitchCompact)
                .labelsHidden()
                .help(isEnabled ? "Disable effect" : "Enable effect")
                .focused($focusedField, equals: .effectCheckbox(childIndex))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isExpanded ? Color.white.opacity(0.24) : Color.white.opacity(0.1))
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture {
                // Toggle expand/collapse on tap (buttons have higher priority)
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedEffectIndices.contains(childIndex) {
                        expandedEffectIndices.remove(childIndex)
                    } else {
                        expandedEffectIndices.insert(childIndex)
                    }
                }
            }

            // Parameters (show when expanded, even if disabled - allows pre-configuration)
            if isExpanded {
                parameterFieldsForEffect(effectDef, layer: layer, effectDefIndex: childIndex)
                    .padding(.top, 8)
                    .opacity(isEnabled ? 1.0 : 0.5)
            }
        }
    }

    @ViewBuilder
    private var addEffectButton: some View {
        Menu {
            ForEach(viewModel.availableEffectTypes, id: \.type) { effect in
                Button(effect.displayName) {
                    // Update session (for persistence) - the session's onChainUpdated callback
                    // will trigger effectManager.reapplyActiveEffects() for immediate preview
                    viewModel.addEffectToChain(effectIndex: selectedEffectIndex, effectType: effect.type)
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
    private func parameterFieldsForEffect(_ effectDef: EffectDefinition, layer: Int, effectDefIndex: Int) -> some View {
        // Use effect's parameterSpecs as source of truth, merged with JSON values
        let mergedParams = EffectsEditorViewModel.mergedParametersForEffect(effectDef)
        let specs = EffectRegistry.parameterSpecs(for: effectDef.type)

        if !mergedParams.isEmpty {
            ForEach(Array(mergedParams.keys.sorted()), id: \.self) { key in
                if let value = mergedParams[key] {
                    ParameterSliderRow(
                        name: key,
                        value: value,
                        effectType: effectDef.type,
                        spec: specs[key],
                        onChange: { newValue in
                            // Update session (for persistence) - the session's onChainUpdated callback
                            // will trigger effectManager.reapplyActiveEffects() for immediate preview
                            viewModel.updateParameter(
                                effectIndex: selectedEffectIndex,
                                effectDefIndex: effectDefIndex,
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
                    .toggleStyle(.darkModeCheckbox)
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
                        // Use textValue @State to buffer input and prevent focus loss
                        // textValue is initialized from s in onAppear/onChange
                        TextField("", text: $textValue)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(isTextFieldFocused ? Color.white : Color.white.opacity(0.1))
                            .foregroundColor(isTextFieldFocused ? .black : .white)
                            .cornerRadius(3)
                            .focused($isTextFieldFocused)
                            .onChange(of: textValue) { _, newValue in
                                // Update the model when text changes
                                onChange(.string(newValue))
                            }
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
        case .string(let s):
            // Only initialize if not currently focused (preserve typing)
            if !isTextFieldFocused {
                textValue = s
            }
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
    var focusedField: FocusState<EffectsEditorField?>.Binding

    @State private var isEditing = false
    @State private var editedName: String = ""

    var body: some View {
        HStack {
            if isEditing {
                TextField("Effect Name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(6)
                    .focused(focusedField, equals: .effectName)
                    .onSubmit {
                        saveAndClose()
                    }
                    .onAppear {
                        // Auto-focus the text field when editing starts
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focusedField.wrappedValue = .effectName
                        }
                    }

                Button(action: saveAndClose) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)

                Button(action: {
                    isEditing = false
                    focusedField.wrappedValue = nil
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
        .onChange(of: name) { _, _ in
            if isEditing {
                isEditing = false
                focusedField.wrappedValue = nil
            }
        }
    }

    private func saveAndClose() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onSave(trimmed)
        }
        isEditing = false
        focusedField.wrappedValue = nil
    }
}

// MARK: - Effect Drag and Drop Delegate

/// Delegate for handling drag and drop reordering of effects in a chain
struct EffectDropDelegate: DropDelegate {
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
