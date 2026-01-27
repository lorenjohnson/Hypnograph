import SwiftUI
import HypnoCore
import HypnoUI

struct EffectChainLibraryView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream
    @ObservedObject var session: EffectsSession

    @State private var selectedID: UUID?
    @State private var expandedEffectIndices: Set<Int> = []

    @State private var renameTargetID: UUID?
    @State private var renameText: String = ""

    @State private var deleteTargetID: UUID?
    @State private var showDeleteConfirm: Bool = false

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return session.chainIndex(id: selectedID)
    }

    private var selectedChain: EffectChain? {
        guard let selectedIndex else { return nil }
        return session.chains[selectedIndex]
    }

    private var selectedLayerIndex: Int? {
        let idx = dream.activePlayer.currentSourceIndex
        guard idx >= 0, idx < dream.activePlayer.layers.count else { return nil }
        return idx
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                if session.chains.isEmpty {
                    Text("No saved effect chains.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(session.chains, id: \.id) { chain in
                            EffectChainLibraryRowView(
                                chain: chain,
                                isSelected: chain.id == selectedID,
                                onSelect: {
                                    selectedID = chain.id
                                    expandedEffectIndices.removeAll()
                                },
                                onApplyToGlobal: {
                                    dream.activeEffectManager.applyTemplate(chain, to: -1)
                                    AppNotifications.show("Applied to Global", flash: true)
                                },
                                onApplyToSelectedLayer: selectedLayerIndex == nil ? nil : {
                                    guard let layer = selectedLayerIndex else { return }
                                    dream.activeEffectManager.applyTemplate(chain, to: layer)
                                    AppNotifications.show("Applied to Layer \(layer + 1)", flash: true)
                                },
                                onRename: {
                                    renameTargetID = chain.id
                                    renameText = chain.name ?? ""
                                },
                                onDuplicate: {
                                    if let newID = session.duplicateTemplate(id: chain.id) {
                                        selectedID = newID
                                        AppNotifications.show("Duplicated", flash: true)
                                    }
                                },
                                onDelete: {
                                    deleteTargetID = chain.id
                                    showDeleteConfirm = true
                                }
                            )
                        }
                    }
                }

                if let selectedIndex, let chain = selectedChain {
                    GlassDivider()
                        .padding(.vertical, 4)

                    EffectChainLibraryEditor(
                        dream: dream,
                        session: session,
                        chainIndex: selectedIndex,
                        chain: chain,
                        expandedEffectIndices: $expandedEffectIndices
                    )
                }
            }
            .padding(12)
        }
        .onAppear {
            if selectedID == nil {
                selectedID = session.chains.first?.id
            }
        }
        .alert("Rename Effect Chain", isPresented: Binding(
            get: { renameTargetID != nil },
            set: { if !$0 { renameTargetID = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameTargetID = nil
            }
            Button("Save") {
                guard let id = renameTargetID, let idx = session.chainIndex(id: id) else { return }
                session.updateChainName(chainIndex: idx, name: renameText)
                renameTargetID = nil
            }
        } message: {
            Text("Enter a new name.")
        }
        .confirmationDialog("Delete this effect chain?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let id = deleteTargetID else { return }
                session.deleteChain(id: id)
                if selectedID == id {
                    selectedID = session.chains.first?.id
                }
                deleteTargetID = nil
            }
            Button("Cancel", role: .cancel) {
                deleteTargetID = nil
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Library")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                let index = session.createNewChain()
                if index >= 0, index < session.chains.count {
                    selectedID = session.chains[index].id
                    expandedEffectIndices.removeAll()
                }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("New chain")
        }
    }
}

private struct EffectChainLibraryEditor: View {
    @ObservedObject var dream: Dream
    @ObservedObject var session: EffectsSession

    let chainIndex: Int
    let chain: EffectChain

    @Binding var expandedEffectIndices: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Selected")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply to Global") {
                    dream.activeEffectManager.applyTemplate(chain, to: -1)
                    AppNotifications.show("Applied to Global", flash: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Name")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)

                    TextField("Name", text: Binding(
                        get: { chain.name ?? "" },
                        set: { session.updateChainName(chainIndex: chainIndex, name: $0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                HStack(spacing: 8) {
                    Menu {
                        ForEach(EffectRegistry.availableEffectTypes, id: \.type) { entry in
                            Button(entry.displayName) {
                                session.addEffectToChain(chainIndex: chainIndex, effectType: entry.type)
                            }
                        }
                    } label: {
                        Label("Add Effect", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)

                    Spacer()

                    Button("Expand All") {
                        expandedEffectIndices = Set(0..<chain.effects.count)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .disabled(chain.effects.isEmpty)

                    Button("Collapse") {
                        expandedEffectIndices.removeAll()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .disabled(expandedEffectIndices.isEmpty)
                }

                if chain.effects.isEmpty {
                    Text("No effects")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(chain.effects.enumerated()), id: \.offset) { index, effect in
                            LibraryEffectRow(
                                session: session,
                                chainIndex: chainIndex,
                                effectIndex: index,
                                effect: effect,
                                isExpanded: expandedEffectIndices.contains(index),
                                onToggleExpanded: {
                                    if expandedEffectIndices.contains(index) {
                                        expandedEffectIndices.remove(index)
                                    } else {
                                        expandedEffectIndices.insert(index)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct LibraryEffectRow: View {
    @ObservedObject var session: EffectsSession

    let chainIndex: Int
    let effectIndex: Int
    let effect: EffectDefinition

    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    private var displayName: String {
        EffectRegistry.formatEffectTypeName(effect.type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: Binding(
                    get: { effect.isEnabled },
                    set: { enabled in
                        session.setEffectEnabled(chainIndex: chainIndex, effectIndex: effectIndex, enabled: enabled)
                    }
                ))
                .toggleStyle(.darkModeCheckbox)
                .labelsHidden()

                Text(displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Button {
                    session.randomizeEffect(chainIndex: chainIndex, effectIndex: effectIndex)
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Randomize")

                Button {
                    session.resetEffectToDefaults(chainIndex: chainIndex, effectIndex: effectIndex)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reset")

                Button(role: .destructive) {
                    session.removeEffectFromChain(chainIndex: chainIndex, effectIndex: effectIndex)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    let specs = EffectRegistry.parameterSpecs(for: effect.type)
                    let keys = EffectRegistry.parameterNames(for: effect.type).filter { $0 != "_enabled" }

                    if keys.isEmpty {
                        Text("No parameters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(keys, id: \.self) { key in
                            let spec = specs[key]
                            let value = effect.params?[key] ?? spec?.defaultValue ?? .double(0)
                            ParameterSliderRow(
                                name: key,
                                value: value,
                                effectType: effect.type,
                                spec: spec,
                                onChange: { newValue in
                                    session.updateParameter(chainIndex: chainIndex, effectIndex: effectIndex, key: key, value: newValue)
                                }
                            )
                        }
                    }
                }
                .padding(.leading, 14)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
