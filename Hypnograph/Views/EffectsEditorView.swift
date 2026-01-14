//
//  EffectsEditorView.swift
//  Hypnograph
//
//  Semi-transparent panel for editing effect parameters.
//  Toggle with Shift+E. Changes are live and persist to JSON.
//

import SwiftUI
import Combine
import HypnoCore

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

// MARK: - Main View

struct EffectsEditorView: View {
    @ObservedObject var viewModel: EffectsEditorViewModel
    @ObservedObject var recentStore: RecentEffectChainsStore
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream

    private let listColumnWidth: CGFloat = 220

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

    /// Target rows to show in CURRENT (Global + sources in the active recipe)
    private var currentTargets: [Int] {
        [-1] + Array(0..<dream.activePlayer.sources.count)
    }

    /// Selection lives in CURRENT: binds List(selection:) to the active target layer.
    private var selectedTargetBinding: Binding<Int?> {
        Binding(
            get: { Optional(dream.activePlayer.currentSourceIndex) },
            set: { newValue in
                guard let layer = newValue else { return }
                dream.activePlayer.selectSource(layer)
            }
        )
    }

    /// Computed selected chain from current layer's effect
    /// Reads from the recipe's stored chain (per-hypnogram), not the library
    private var selectedDefinition: EffectChain? {
        dream.activeEffectManager.effectChain(for: currentLayer)
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

    private func applyTemplate(_ template: EffectChain?) {
        dream.activeEffectManager.applyTemplate(template, to: currentLayer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header showing which layer is being edited
            HStack {
                // Toggle effects list sidebar button (icon only with tooltip)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.settingsStore.update { $0.effectsListCollapsed.toggle() }
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
                        .frame(width: listColumnWidth)
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
        .frame(width: 620)
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
            // Set initial focus to effect list immediately
            focusedField = .effectList
            viewModel.activeSection = .effectList
        }
        .onChange(of: dream.isLiveMode) { _, _ in
            // Update session when live mode changes (Edit ↔ Live)
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
            // Move CURRENT target selection up/down with wrap-around
            let targets = currentTargets
            guard !targets.isEmpty else { return }
            let currentIndex = targets.firstIndex(of: dream.activePlayer.currentSourceIndex) ?? 0
            let nextIndex = (currentIndex + delta + targets.count) % targets.count
            dream.activePlayer.selectSource(targets[nextIndex])

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

    private func chainSummary(_ chain: EffectChain) -> String {
        guard !chain.effects.isEmpty else { return "None" }
        return chain.effects
            .map { formatEffectType($0.type) ?? $0.type }
            .joined(separator: " + ")
    }

    private func recentVariantText(_ entry: RecentEntry) -> String {
        let suffix = entry.variantHint ?? String(entry.chain.paramsHash.prefix(6))
        if entry.sourceTemplateId != nil, let name = entry.templateNameHint, !name.isEmpty {
            return "\(name) · \(suffix)"
        }
        return "Variant · \(suffix)"
    }

    private func chainDisplayName(_ chain: EffectChain?) -> String {
        guard let chain else { return "None" }
        if let name = chain.name, !name.isEmpty { return name }
        return chainSummary(chain)
    }

    private func templateDisplayName(_ chain: EffectChain) -> String {
        chain.name?.isEmpty == false ? chain.name! : chainSummary(chain)
    }

    // MARK: - Effect List Column

    private var effectListColumn: some View {
        return VStack(alignment: .leading, spacing: 8) {
            Text("Effects")
                .font(.headline)

            List(selection: selectedTargetBinding) {
                Section("CURRENT") {
                    ForEach(currentTargets, id: \.self) { layer in
                        let chain = dream.activeEffectManager.effectChain(for: layer)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(layer == -1 ? "Global" : "Source \(layer + 1)")
                                    .font(.system(.body, design: .monospaced))
                                Text(chainDisplayName(chain))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Menu {
                                if let chain, !chain.effects.isEmpty, let templateId = chain.sourceTemplateId {
                                    let canUpdate = viewModel.session?.chain(id: templateId) != nil
                                    Button("Update Library Entry") {
                                        guard let session = viewModel.session else { return }
                                        session.updateTemplate(id: templateId, from: chain, preserveName: true)
                                        AppNotifications.show("Updated library entry", flash: true)
                                    }
                                    .disabled(!canUpdate)
                                }

                                if let chain, !chain.effects.isEmpty {
                                    Button("Copy to Library") {
                                        guard let session = viewModel.session else { return }
                                        let baseName = chain.name?.isEmpty == false ? chain.name! : "Effect"
                                        let newId = session.addTemplate(from: chain, name: "\(baseName) Copy")
                                        dream.activeEffectManager.updateSourceTemplateId(for: layer, sourceTemplateId: newId)
                                        AppNotifications.show("Copied to library", flash: true)
                                    }
                                }

                                Divider()

                                Button("Clear") {
                                    dream.activeEffectManager.applyTemplate(nil, to: layer)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: 20, height: 20)
                            }
                            .menuStyle(.borderlessButton)
                        }
                        .tag(Optional(layer))
                    }
                }

                Section("RECENT") {
                    let entries = Array(recentStore.entries.prefix(10))
                    if entries.isEmpty {
                        Text("No recent effects")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        ForEach(entries) { entry in
                            HStack(spacing: 8) {
                                Button {
                                    recentStore.addToFront(entry.chain)
                                    dream.activeEffectManager.applyChainSnapshot(
                                        entry.chain,
                                        sourceTemplateId: entry.sourceTemplateId,
                                        to: currentLayer
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chainDisplayName(entry.chain))
                                            .font(.system(.body, design: .monospaced))
                                        Text("\(chainSummary(entry.chain)) · \(recentVariantText(entry))")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer(minLength: 0)

                                Menu {
                                    Button("Remove from History", role: .destructive) {
                                        recentStore.remove(id: entry.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                        .frame(width: 20, height: 20)
                                }
                                .menuStyle(.borderlessButton)
                            }
                        }
                    }
                }

                Section("LIBRARIES") {
                    ForEach(Array(viewModel.effectChains.enumerated()), id: \.offset) { index, chain in
                        HStack(spacing: 8) {
                            Button {
                                applyTemplate(chain)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(templateDisplayName(chain))
                                        .font(.system(.body, design: .monospaced))
                                    Text(chainSummary(chain))
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer(minLength: 0)

                            Menu {
                                Button("Duplicate") {
                                    guard let session = viewModel.session else { return }
                                    let baseName = chain.name?.isEmpty == false ? chain.name! : "Effect"
                                    _ = session.addTemplate(from: chain, name: "\(baseName) Copy")
                                    AppNotifications.show("Duplicated template", flash: true)
                                }

                                Divider()

                                Button("Delete", role: .destructive) {
                                    viewModel.deleteEffect(at: index)
                                    AppNotifications.show("Deleted template", flash: true)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: 20, height: 20)
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

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

    // MARK: - Parameters Column

    private var parametersColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let def = selectedDefinition {
                // Editable name header
                EditableEffectNameHeader(
                    name: def.effects.isEmpty ? "None" : (def.name ?? "Unnamed"),
                    onSave: { newName in
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
                Text("Select a target")
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
                    onReorder: { from, to in
                        dream.activeEffectManager.reorderEffectsInChain(for: layer, fromIndex: from, toIndex: to)
                    }
                ))
            }

            // Add effect button
            addEffectButton(for: layer)
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

                // Randomize button
                Button(action: {
                    dream.activeEffectManager.randomizeEffect(for: layer, effectDefIndex: childIndex)
                }) {
                    Image(systemName: "dice")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Randomize parameters")

                // Reset to defaults button
                Button(action: {
                    dream.activeEffectManager.resetEffectToDefaults(for: layer, effectDefIndex: childIndex)
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Reset to defaults")

                // Delete button
                Button(action: {
                    dream.activeEffectManager.removeEffectFromChain(for: layer, effectDefIndex: childIndex)
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

                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        dream.activeEffectManager.setEffectEnabled(for: layer, effectDefIndex: childIndex, enabled: newValue)
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
    private func addEffectButton(for layer: Int) -> some View {
        Menu {
            ForEach(viewModel.availableEffectTypes, id: \.type) { effect in
                Button(effect.displayName) {
                    dream.activeEffectManager.addEffectToChain(for: layer, effectType: effect.type)
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
                            dream.activeEffectManager.updateEffectParameter(
                                for: layer,
                                effectDefIndex: effectDefIndex,
                                key: key,
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
