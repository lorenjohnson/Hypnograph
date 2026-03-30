//
//  EffectsEditorView.swift
//  Hypnograph
//
//  Semi-transparent panel for editing effect parameters.
//  Toggle with Shift+E. Changes are live and persist to JSON.
//

import SwiftUI
import HypnoCore
import HypnoUI

// MARK: - Studio View

struct EffectsEditorView: View {
    @ObservedObject var viewModel: EffectsEditorViewModel
    @ObservedObject var recentStore: RecentEffectChainsStore
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    private let listColumnWidth: CGFloat = 240

    /// SwiftUI focus state - tracks which field has keyboard focus
    @FocusState private var focusedField: EffectsEditorField?

    /// Track which effects in the chain are expanded (multiple allowed)
    @State private var expandedEffectIndices: Set<Int> = []

    /// Currently dragged effect index for reordering
    @State private var draggingEffectIndex: Int?

    /// Show confirmation dialog for restoring default effects library
    @State private var showRestoreConfirmation = false

    @State private var listSelection: EffectsListSelection?

    /// Current layer being edited (-1 = global, 0+ = source)
    private var currentLayer: Int {
        main.activePlayer.currentLayerIndex
    }

    /// Target rows to show in CURRENT (Global + sources in the active recipe)
    private var currentTargets: [Int] {
        [-1] + Array(0..<main.activePlayer.layers.count)
    }

    private var selectedChainContext: SelectedChainContext? {
        guard let selection = listSelection else { return nil }
        switch selection {
        case .current(let layer):
            guard let chain = main.activeEffectManager.effectChain(for: layer) else { return nil }
            return SelectedChainContext(chain: chain, editableLayer: layer, title: chainDisplayName(chain))

        case .recent(let id):
            guard let entry = recentStore.entries.first(where: { $0.id == id }) else { return nil }
            return SelectedChainContext(chain: entry.chain, editableLayer: nil, title: chainDisplayName(entry.chain))

        case .library(let id):
            guard let chain = viewModel.effectChains.first(where: { $0.id == id }) else { return nil }
            return SelectedChainContext(chain: chain, editableLayer: nil, title: templateDisplayName(chain))
        }
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
        main.activeEffectManager.applyTemplate(template, to: currentLayer)
        listSelection = .current(currentLayer)
    }

    private func chainHeaderName(_ chain: EffectChain) -> String {
        chain.effects.isEmpty ? "None" : (chain.name ?? "Unnamed")
    }

    private func chainNameSaveHandler(for selection: EffectsListSelection?) -> ((String) -> Void)? {
        guard let selection else { return nil }
        switch selection {
        case .current(let layer):
            return { newName in
                main.activeEffectManager.updateChainName(for: layer, name: newName)
            }

        case .recent(let id):
            return { newName in
                recentStore.updateChainName(id: id, name: newName)
                AppNotifications.show("Renamed recent entry", flash: true)
            }

        case .library(let id):
            return { newName in
                guard let session = viewModel.session,
                      let chainIndex = session.chainIndex(id: id)
                else { return }
                session.updateChainName(chainIndex: chainIndex, name: newName)
                AppNotifications.show("Renamed template", flash: true)
            }
        }
    }

    private func applyRecentEntry(_ entry: RecentEntry) {
        recentStore.addToFront(entry.chain)
        main.activeEffectManager.applyChainSnapshot(
            entry.chain,
            sourceTemplateId: entry.sourceTemplateId,
            to: currentLayer
        )
        listSelection = .current(currentLayer)
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

                Text(main.activePlayer.editingLayerDisplay)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(main.activePlayer.isOnGlobalLayer ? .cyan : .orange)

                Spacer()

                // Close button
                Button(action: {
                    main.windows.setWindowVisible("effectsEditor", visible: false)
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
            guard focusedField == .effectList, case .some(.current(_)) = listSelection else { return .ignored }
            handleUpDown(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !isTextEditing else { return .ignored }
            guard focusedField == .effectList, case .some(.current(_)) = listSelection else { return .ignored }
            handleUpDown(delta: 1)
            return .handled
        }
        // Left/right arrow and Tab/Shift-Tab handled natively by SwiftUI focus system
        .onAppear {
            // Connect view model to the active session
            viewModel.session = main.effectsSession
            // Set initial focus to effect list immediately
            focusedField = .effectList
            viewModel.activeSection = .effectList
            listSelection = .current(currentLayer)
        }
        .onChange(of: main.isLiveMode) { _, _ in
            // Update session when live mode changes (Edit ↔ Live)
            viewModel.session = main.effectsSession
        }
        .onChange(of: focusedField) { _, newField in
            // Sync active section when focus changes
            if let field = newField {
                viewModel.activeSection = field
            }
        }
        .onChange(of: main.activePlayer.currentLayerIndex) { _, newValue in
            // Keep CURRENT selection in sync when the active layer changes externally.
            guard case .some(.current(_)) = listSelection else { return }
            listSelection = .current(newValue)
        }
        .onChange(of: listSelection) { _, newValue in
            // Clear effect expansion state when changing which chain is being inspected.
            expandedEffectIndices.removeAll()
            draggingEffectIndex = nil

            // Selecting a CURRENT row should switch the active layer (works for keyboard selection too).
            guard case let .some(.current(layer)) = newValue else { return }
            main.activePlayer.selectSource(layer)
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
        // Move CURRENT target selection up/down with wrap-around
        let targets = currentTargets
        guard !targets.isEmpty else { return }
        let currentIndex = targets.firstIndex(of: main.activePlayer.currentLayerIndex) ?? 0
        let nextIndex = (currentIndex + delta + targets.count) % targets.count
        let nextLayer = targets[nextIndex]
        main.activePlayer.selectSource(nextLayer)
        listSelection = .current(nextLayer)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Effects")
                .font(.headline)

            effectsList

            Spacer()

            // Library action buttons
            effectLibraryButtons
        }
        .padding(.trailing, 12)
    }

    private var effectsList: some View {
        List(selection: $listSelection) {
            currentSection
            recentSection
            librariesSection
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity)
    }

    private func effectsListSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.85))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private var currentSection: some View {
        Section {
            ForEach(currentTargets, id: \.self) { layer in
                currentRow(layer: layer)
            }
        } header: {
            effectsListSectionHeader("CURRENT")
        }
    }

    @ViewBuilder
    private func currentRow(layer: Int) -> some View {
        let chain = main.activeEffectManager.effectChain(for: layer)
        let templateId = chain?.sourceTemplateId
        let canUpdate = templateId != nil && (viewModel.session?.chain(id: templateId!) != nil)

        let isSelected = listSelection == .current(layer)

        EffectsEditorHoverRevealControlsRow(isSelected: isSelected) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer == -1 ? "Composition" : "Layer \(layer + 1)")
                        .font(.system(.body, design: .monospaced))
                    Text(chainDisplayName(chain))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.trailing, 24)
            .onTapGesture {
                listSelection = .current(layer)
            }
        } controls: {
            Menu {
                if let chain, !chain.effects.isEmpty, let templateId {
                    Button("Update Library Entry") {
                        updateLibraryEntry(from: chain, templateId: templateId)
                    }
                    .disabled(!canUpdate)
                }

                if let chain, !chain.effects.isEmpty {
                    Button("Copy to Library") {
                        copyCurrentToLibrary(chain: chain, layer: layer)
                    }
                }

                Divider()

                Button("Clear") {
                    main.activeEffectManager.applyTemplate(nil, to: layer)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20, height: 20)
            .fixedSize()
            .simultaneousGesture(TapGesture().onEnded { listSelection = .current(layer) })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tag(EffectsListSelection.current(layer))
    }

    @ViewBuilder
    private var recentSection: some View {
        Section {
            let entries = Array(recentStore.entries.prefix(10))
            if entries.isEmpty {
                Text("No recent effects")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            } else {
                ForEach(entries) { entry in
                    recentRow(entry: entry)
                }
            }
        } header: {
            effectsListSectionHeader("RECENT")
        }
    }

    @ViewBuilder
    private func recentRow(entry: RecentEntry) -> some View {
        let isSelected = listSelection == .recent(entry.id)

        EffectsEditorHoverRevealControlsRow(isSelected: isSelected) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chainDisplayName(entry.chain))
                        .font(.system(.body, design: .monospaced))
                    Text("\(chainSummary(entry.chain)) · \(recentVariantText(entry))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.trailing, 24)
            .onTapGesture {
                listSelection = .recent(entry.id)
            }
        } controls: {
            Menu {
                Button("Apply") {
                    applyRecentEntry(entry)
                }

                Divider()

                Button("Remove from History", role: .destructive) {
                    recentStore.remove(id: entry.id)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20, height: 20)
            .fixedSize()
            .simultaneousGesture(TapGesture().onEnded { listSelection = .recent(entry.id) })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tag(EffectsListSelection.recent(entry.id))
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            applyRecentEntry(entry)
        })
    }

    @ViewBuilder
    private var librariesSection: some View {
        Section {
            ForEach(Array(viewModel.effectChains.enumerated()), id: \.offset) { index, chain in
                libraryRow(index: index, chain: chain)
            }
        } header: {
            effectsListSectionHeader("LIBRARIES")
        }
    }

    @ViewBuilder
    private func libraryRow(index: Int, chain: EffectChain) -> some View {
        let isSelected = listSelection == .library(chain.id)

        EffectsEditorHoverRevealControlsRow(isSelected: isSelected) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(templateDisplayName(chain))
                        .font(.system(.body, design: .monospaced))
                    Text(chainSummary(chain))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.trailing, 24)
            .onTapGesture {
                listSelection = .library(chain.id)
            }
        } controls: {
            Menu {
                Button("Apply") {
                    applyTemplate(chain)
                }

                Divider()

                Button("Duplicate") {
                    duplicateTemplate(chain: chain)
                }

                Divider()

                Button("Delete", role: .destructive) {
                    viewModel.deleteEffect(at: index)
                    AppNotifications.show("Deleted template", flash: true)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20, height: 20)
            .fixedSize()
            .simultaneousGesture(TapGesture().onEnded { listSelection = .library(chain.id) })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tag(EffectsListSelection.library(chain.id))
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            applyTemplate(chain)
        })
    }

    private func updateLibraryEntry(from chain: EffectChain, templateId: UUID) {
        guard let session = viewModel.session else { return }
        session.updateTemplate(id: templateId, from: chain, preserveName: true)
        AppNotifications.show("Updated library entry", flash: true)
    }

    private func copyCurrentToLibrary(chain: EffectChain, layer: Int) {
        guard let session = viewModel.session else { return }
        let baseName = chain.name?.isEmpty == false ? chain.name! : "Effect"
        let newId = session.addTemplate(from: chain, name: "\(baseName) Copy")
        main.activeEffectManager.updateSourceTemplateId(for: layer, sourceTemplateId: newId)
        AppNotifications.show("Copied to library", flash: true)
    }

    private func duplicateTemplate(chain: EffectChain) {
        guard let session = viewModel.session else { return }
        let baseName = chain.name?.isEmpty == false ? chain.name! : "Effect"
        _ = session.addTemplate(from: chain, name: "\(baseName) Copy")
        AppNotifications.show("Duplicated template", flash: true)
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
            if let ctx = selectedChainContext {
                if let onSave = chainNameSaveHandler(for: listSelection) {
                    EditableEffectNameHeader(
                        name: chainHeaderName(ctx.chain),
                        onSave: onSave,
                        focusedField: $focusedField
                    )
                } else {
                    Text(ctx.title)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                }

                Divider()
                    .background(Color.white.opacity(0.3))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let layer = ctx.editableLayer {
                            parametersForChain(ctx.chain, layer: layer)
                        } else {
                            parametersForChainReadOnly(ctx.chain)
                        }
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
                        main.activeEffectManager.reorderEffectsInChain(for: layer, fromIndex: from, toIndex: to)
                    }
                ))
            }

            // Add effect button
            addEffectButton(for: layer)
        }
    }

    @ViewBuilder
    private func parametersForChainReadOnly(_ chain: EffectChain) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chain.effects.enumerated()), id: \.offset) { childIndex, effectDef in
                chainedEffectSectionReadOnly(
                    effectDef: effectDef,
                    childIndex: childIndex,
                    totalEffects: chain.effects.count
                )
            }

            if chain.effects.isEmpty {
                Text("No effects")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func chainedEffectSection(effectDef: EffectDefinition, childIndex: Int, totalEffects: Int, layer: Int) -> some View {
        let isEnabled = effectDef.params?["_enabled"]?.boolValue ?? true
        let isExpanded = expandedEffectIndices.contains(childIndex)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expandedEffectIndices.contains(childIndex) {
                            expandedEffectIndices.remove(childIndex)
                        } else {
                            expandedEffectIndices.insert(childIndex)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 20)

                        Text(formatEffectType(effectDef.type) ?? "Effect \(childIndex + 1)")
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundColor(isEnabled ? .white : .white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // Randomize button
                Button(action: {
                    main.activeEffectManager.randomizeEffect(for: layer, effectDefIndex: childIndex)
                }) {
                    Image(systemName: "dice")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Randomize parameters")

                // Reset to defaults button
                Button(action: {
                    main.activeEffectManager.resetEffectToDefaults(for: layer, effectDefIndex: childIndex)
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Reset to defaults")

                // Delete button
                Button(action: {
                    main.activeEffectManager.removeEffectFromChain(for: layer, effectDefIndex: childIndex)
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
                PanelToggleView(isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        main.activeEffectManager.setEffectEnabled(for: layer, effectDefIndex: childIndex, enabled: newValue)
                    }
                ))
                .fixedSize()
                .help(isEnabled ? "Disable effect" : "Enable effect")
                .focused($focusedField, equals: .effectCheckbox(childIndex))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isExpanded ? Color.white.opacity(0.24) : Color.white.opacity(0.1))
            .cornerRadius(6)

            // Parameters (show when expanded, even if disabled - allows pre-configuration)
            if isExpanded {
                parameterFieldsForEffect(effectDef, layer: layer, effectDefIndex: childIndex)
                    .padding(.top, 8)
                    .opacity(isEnabled ? 1.0 : 0.5)
            }
        }
    }

    @ViewBuilder
    private func chainedEffectSectionReadOnly(effectDef: EffectDefinition, childIndex: Int, totalEffects: Int) -> some View {
        let isEnabled = effectDef.params?["_enabled"]?.boolValue ?? true
        let isExpanded = expandedEffectIndices.contains(childIndex)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expandedEffectIndices.contains(childIndex) {
                            expandedEffectIndices.remove(childIndex)
                        } else {
                            expandedEffectIndices.insert(childIndex)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.25))
                            .frame(width: 20)

                        Text(formatEffectType(effectDef.type) ?? "Effect \(childIndex + 1)")
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundColor(isEnabled ? .white : .white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                PanelToggleView(isOn: .constant(isEnabled))
                    .fixedSize()
                    .disabled(true)
                    .help(isEnabled ? "Enabled" : "Disabled")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isExpanded ? Color.white.opacity(0.24) : Color.white.opacity(0.1))
            .cornerRadius(6)

            if isExpanded {
                parameterFieldsForEffectReadOnly(effectDef)
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
                    main.activeEffectManager.addEffectToChain(for: layer, effectType: effect.type)
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
                            main.activeEffectManager.updateEffectParameter(
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

    @ViewBuilder
    private func parameterFieldsForEffectReadOnly(_ effectDef: EffectDefinition) -> some View {
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
                        onChange: { _ in }
                    )
                    .disabled(true)
                }
            }
        } else {
            Text("No parameters")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }

}
