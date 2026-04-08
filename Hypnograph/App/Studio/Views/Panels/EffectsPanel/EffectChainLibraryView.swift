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
        guard idx >= 0, idx < main.currentLayers.count else { return nil }
        return idx
    }

    private func commitActiveRename() {
        guard let targetID = renameTargetID else { return }
        guard let chainIndex = session.chainIndex(id: targetID) else {
            renameTargetID = nil
            return
        }
        session.updateChainName(chainIndex: chainIndex, name: renameText)
        renameTargetID = nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if session.chains.isEmpty {
                    Text("No saved effect chains.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    let snapshot = session.chains
                    ForEach(snapshot, id: \.id) { chain in
                        if let chainIndex = session.chainIndex(id: chain.id) {
                    EffectChainLibraryRowView(
                                main: main,
                                session: session,
                                chainIndex: chainIndex,
                                chain: chain,
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
                                isRenaming: renameTargetID == chain.id,
                                renameText: Binding(
                                    get: { renameTargetID == chain.id ? renameText : chain.name ?? "" },
                                    set: { renameText = $0 }
                                ),
                                onInteractionOutsideRename: {
                                    if renameTargetID != nil, renameTargetID != chain.id {
                                        commitActiveRename()
                                    }
                                },
                                onRename: {
                                    renameTargetID = chain.id
                                    renameText = chain.name ?? ""
                                },
                                onCommitRename: {
                                    guard renameTargetID == chain.id else { return }
                                    commitActiveRename()
                                },
                                onCancelRename: {
                                    guard renameTargetID == chain.id else { return }
                                    renameTargetID = nil
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

                Color.clear
                    .frame(height: 1)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: commitActiveRename)
            }
            .padding(12)
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
