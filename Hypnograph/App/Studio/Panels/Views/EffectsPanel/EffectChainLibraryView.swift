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
    @State private var previewChainOrder: [UUID]?

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

    private var displayedChains: [EffectChain] {
        let chains = session.chains
        guard let previewChainOrder else { return chains }

        let chainsByID = Dictionary(uniqueKeysWithValues: chains.map { ($0.id, $0) })
        let ordered = previewChainOrder.compactMap { chainsByID[$0] }
        let previewSet = Set(previewChainOrder)
        let remaining = chains.filter { !previewSet.contains($0.id) }
        return ordered + remaining
    }

    private func reorderPreviewChain(from sourceID: UUID, to targetID: UUID) {
        if previewChainOrder == nil {
            previewChainOrder = session.chains.map(\.id)
        }

        guard var order = previewChainOrder,
              let fromIndex = order.firstIndex(of: sourceID),
              let toIndex = order.firstIndex(of: targetID),
              fromIndex != toIndex else { return }

        let moved = order.remove(at: fromIndex)
        var destination = toIndex
        if fromIndex < toIndex {
            destination -= 1
        }
        order.insert(moved, at: max(0, min(destination, order.count)))
        previewChainOrder = order
    }

    private func commitPreviewChainOrder() {
        defer {
            draggedChainID = nil
            previewChainOrder = nil
        }

        guard let previewChainOrder else { return }
        let currentChains = session.chains
        let currentOrder = currentChains.map(\.id)
        guard previewChainOrder != currentOrder else { return }

        let chainsByID = Dictionary(uniqueKeysWithValues: currentChains.map { ($0.id, $0) })
        let reordered = previewChainOrder.compactMap { chainsByID[$0] }
        let previewSet = Set(previewChainOrder)
        let remaining = currentChains.filter { !previewSet.contains($0.id) }
        session.replaceChains(reordered + remaining)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if session.chains.isEmpty {
                    Text("No saved effect chains.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    let snapshot = displayedChains
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
                                previewChainOrder = session.chains.map(\.id)
                                return DragCleanupItemProvider(
                                    object: chain.id.uuidString as NSString,
                                    onDeinit: { [draggedChainID = $draggedChainID, previewChainOrder = $previewChainOrder] in
                                        if draggedChainID.wrappedValue == chain.id {
                                            draggedChainID.wrappedValue = nil
                                            previewChainOrder.wrappedValue = nil
                                        }
                                    }
                                )
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: EffectChainReorderDropDelegate(
                                    targetID: chain.id,
                                    draggedChainID: $draggedChainID,
                                    previewMoveChain: { sourceID, targetID in
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            reorderPreviewChain(from: sourceID, to: targetID)
                                        }
                                    },
                                    commitDrop: {
                                        commitPreviewChainOrder()
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
    let previewMoveChain: (UUID, UUID) -> Void
    let commitDrop: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggedChainID else { return }
        guard sourceID != targetID else { return }
        previewMoveChain(sourceID, targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        commitDrop()
        return true
    }

    func dropExited(info: DropInfo) {
        // Keep current drag state; it will clear on performDrop.
    }
}

private final class DragCleanupItemProvider: NSItemProvider {
    private let onDeinit: @MainActor () -> Void

    init(object: NSItemProviderWriting, onDeinit: @escaping @MainActor () -> Void) {
        self.onDeinit = onDeinit
        super.init(object: object)
    }

    deinit {
        Task { @MainActor in
            onDeinit()
        }
    }
}
