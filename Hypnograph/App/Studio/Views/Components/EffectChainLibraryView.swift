import SwiftUI
import UniformTypeIdentifiers
import HypnoCore
import HypnoUI

struct EffectChainLibraryView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio
    @ObservedObject var session: EffectsSession

    @State private var renameTargetID: UUID?
    @State private var renameText: String = ""

    @State private var deleteTargetID: UUID?
    @State private var showDeleteConfirm: Bool = false

    @State private var expandedChainIDs: Set<UUID> = []
    @State private var expandedEffectIndicesByChainID: [UUID: Set<Int>] = [:]
    @State private var draggedChainID: UUID?

    private var selectedLayerIndex: Int? {
        let idx = main.activePlayer.currentLayerIndex
        guard idx >= 0, idx < main.activePlayer.layers.count else { return nil }
        return idx
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Library")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                if session.chains.isEmpty {
                    Text("No saved effect chains.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    let snapshot = session.chains
                    ForEach(snapshot, id: \.id) { chain in
                        if let chainIndex = session.chainIndex(id: chain.id) {
                            EffectChainLibraryRow(
                                main: main,
                                session: session,
                                chainIndex: chainIndex,
                                chain: chain,
                                selectedLayerIndex: selectedLayerIndex,
                                isExpanded: expandedChainIDs.contains(chain.id),
                                expandedEffectIndices: Binding(
                                    get: { expandedEffectIndicesByChainID[chain.id] ?? [] },
                                    set: { expandedEffectIndicesByChainID[chain.id] = $0 }
                                ),
                                onToggleExpanded: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if expandedChainIDs.contains(chain.id) {
                                            expandedChainIDs.remove(chain.id)
                                        } else {
                                            expandedChainIDs.insert(chain.id)
                                        }
                                    }
                                },
                                onRename: {
                                    renameTargetID = chain.id
                                    renameText = chain.name ?? ""
                                },
                                onDuplicate: {
                                    _ = session.duplicateTemplate(id: chain.id)
                                    AppNotifications.show("Duplicated", flash: true)
                                },
                                onDelete: {
                                    deleteTargetID = chain.id
                                    showDeleteConfirm = true
                                }
                            )
                            .contentShape(Rectangle())
                            .onDrag {
                                draggedChainID = chain.id
                                return NSItemProvider(object: chain.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: EffectChainReorderDropDelegate(
                                    targetID: chain.id,
                                    draggedChainID: $draggedChainID,
                                    moveChain: { sourceID, targetID in
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            session.moveChain(fromID: sourceID, toID: targetID)
                                        }
                                    }
                                )
                            )
                        }
                    }
                }
            }
            .padding(12)
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
                deleteTargetID = nil
            }
            Button("Cancel", role: .cancel) {
                deleteTargetID = nil
            }
        }
    }
}

private struct EffectChainReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedChainID: UUID?
    let moveChain: (UUID, UUID) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggedChainID else { return }
        guard sourceID != targetID else { return }
        moveChain(sourceID, targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedChainID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        // Keep current drag state; it will clear on performDrop.
    }
}

private struct EffectChainLibraryRow: View {
    @ObservedObject var main: Studio
    @ObservedObject var session: EffectsSession

    let chainIndex: Int
    let chain: EffectChain
    let selectedLayerIndex: Int?

    let isExpanded: Bool
    @Binding var expandedEffectIndices: Set<Int>
    let onToggleExpanded: () -> Void

    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var displayName: String { chain.name ?? "Unnamed" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text("\(chain.effects.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleExpanded)
            .contextMenu {
                Button {
                    main.activeEffectManager.applyTemplate(chain, to: -1)
                    AppNotifications.show("Applied to Composition", flash: true)
                } label: {
                    Label("Apply to Composition", systemImage: "globe")
                }

                Button {
                    guard let layer = selectedLayerIndex else { return }
                    main.activeEffectManager.applyTemplate(chain, to: layer)
                    AppNotifications.show("Applied to Layer \(layer + 1)", flash: true)
                } label: {
                    Label("Apply to Selected Layer", systemImage: "square.stack.3d.up")
                }
                .disabled(selectedLayerIndex == nil)

                Divider()

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }

                Button(action: onRename) {
                    Label("Rename...", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(chain.effects.enumerated()), id: \.offset) { index, effect in
                        EffectDefinitionSessionRow(
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
                        .animation(.easeInOut(duration: 0.15), value: expandedEffectIndices)
                    }

                    Menu {
                        ForEach(EffectRegistry.availableEffectTypes, id: \.type) { entry in
                            Button(entry.displayName) {
                                session.addEffectToChain(chainIndex: chainIndex, effectType: entry.type)
                            }
                        }
                    } label: {
                        Label("Add Effect", systemImage: "plus")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

private struct EffectDefinitionSessionRow: View {
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
            HStack {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(displayName)
                            .font(.callout)
                            .foregroundStyle(effect.isEnabled ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { effect.isEnabled },
                    set: { enabled in
                        session.setEffectEnabled(chainIndex: chainIndex, effectIndex: effectIndex, enabled: enabled)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

                Button(role: .destructive) {
                    session.removeEffectFromChain(chainIndex: chainIndex, effectIndex: effectIndex)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    let specs = EffectRegistry.parameterSpecs(for: effect.type)
                    let keys = EffectRegistry.parameterNames(for: effect.type).filter { $0 != "_enabled" }

                    ForEach(keys, id: \.self) { key in
                        let spec = specs[key]
                        let value = effect.params?[key] ?? spec?.defaultValue ?? .double(0)
                        EffectParameterRowView(
                            name: key,
                            value: value,
                            spec: spec,
                            onChange: { newValue in
                                session.updateParameter(chainIndex: chainIndex, effectIndex: effectIndex, key: key, value: newValue)
                            }
                        )
                    }
                }
                .padding(.leading, 16)
                .opacity(effect.isEnabled ? 1.0 : 0.5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
        )
    }
}
