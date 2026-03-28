import SwiftUI
import CoreMedia
import UniformTypeIdentifiers
import HypnoCore

struct CompositionWindowView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    @State private var expandedLayerIDs: Set<UUID> = []
    @State private var showAddLayerPhotosPicker = false
    @State private var draggedLayerID: UUID?
    @StateObject private var thumbnailStore = LayerThumbnailStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                globalSection

                GlassDivider()
                    .padding(.vertical, 4)

                HStack {
                    Text("Layers")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Menu {
                            Button {
                                main.addSourceFromFilesPanel()
                            } label: {
                                Label("From Files...", systemImage: "doc")
                            }

                            Button {
                                showAddLayerPhotosPicker = true
                            } label: {
                                Label("From Photos...", systemImage: "photo")
                            }
                        } label: {
                            Label("Select Source...", systemImage: "photo.on.rectangle")
                        }

                        Button {
                            main.addSource()
                        } label: {
                            Label("Random Source", systemImage: "dice")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 6) {
                    let snapshot = main.activePlayer.layers
                    ForEach(snapshot, id: \.mediaClip.file.id) { snapshotLayer in
                        let id = snapshotLayer.mediaClip.file.id
                        let currentIndex = layerIndex(for: id)

                        if let currentIndex {
                            LayerRowView(
                                state: state,
                                main: main,
                                thumbnailStore: thumbnailStore,
                                index: currentIndex,
                                layer: bindingForLayer(id: id, fallback: snapshotLayer),
                                isSelected: main.activePlayer.currentSourceIndex == currentIndex,
                                isExpanded: expandedLayerIDs.contains(id),
                                onSelect: {
                                    if let idx = layerIndex(for: id) {
                                        main.activePlayer.selectSource(idx)
                                    }
                                },
                                onToggleExpanded: {
                                    toggleExpanded(id: id)
                                },
                                onDuplicate: {
                                    if let idx = layerIndex(for: id) {
                                        main.activePlayer.selectSource(idx)
                                    }
                                    main.duplicateCurrentLayer()
                                },
                                onDelete: {
                                    if let idx = layerIndex(for: id) {
                                        main.activePlayer.selectSource(idx)
                                    }
                                    main.removeCurrentLayer()
                                }
                            )
                            .contentShape(Rectangle())
                            .onDrag {
                                draggedLayerID = id
                                return NSItemProvider(object: id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: CompositionLayerReorderDropDelegate(
                                    targetID: id,
                                    draggedLayerID: $draggedLayerID,
                                    moveLayer: { sourceID, targetID in
                                        moveLayer(sourceID: sourceID, targetID: targetID)
                                    }
                                )
                            )
                            .animation(.easeInOut(duration: 0.2), value: expandedLayerIDs)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.black.opacity(0.96).ignoresSafeArea())
        .sheet(isPresented: $showAddLayerPhotosPicker) {
            PhotosPickerSheet(
                isPresented: $showAddLayerPhotosPicker,
                preselectedIdentifiers: [],
                selectionLimit: 1,
                onSelection: { identifiers in
                    guard let selectedIdentifier = identifiers.first else { return }
                    _ = main.addSource(fromPhotosAssetIdentifier: selectedIdentifier)
                }
            )
        }
    }

    private var globalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Global")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Clip Length")
                        .font(.callout)
                    Spacer()
                    Text("\(Int(main.activePlayer.targetDuration.seconds.rounded()))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: {
                            let seconds = main.activePlayer.targetDuration.seconds
                            return max(1, min(seconds, 60))
                        },
                        set: { newValue in
                            let seconds = max(1, min(newValue.rounded(), 60))
                            main.activePlayer.targetDuration = CMTime(seconds: seconds, preferredTimescale: 600)
                            main.activePlayer.notifySessionMutated()
                        }
                    ),
                    in: 1...60,
                    step: 1
                )
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Play Rate")
                        .font(.callout)
                    Spacer()
                    Text(String(format: "%.0f%%", main.activePlayer.playRate * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { main.activePlayer.playRate },
                        set: { main.activePlayer.playRate = $0 }
                    ),
                    in: 0.2...2.0,
                    step: 0.2
                )
            }
            .padding(.horizontal, 4)
            .disabled(main.isLiveMode)
            .opacity(main.isLiveMode ? 0.55 : 1.0)

            EffectChainView(
                state: state,
                main: main,
                layer: -1,
                title: "Effects"
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            main.activePlayer.selectGlobalLayer()
        }
    }

    private func bindingForLayer(id: UUID, fallback: HypnogramLayer) -> Binding<HypnogramLayer> {
        Binding(
            get: { main.activePlayer.layers.first(where: { $0.mediaClip.file.id == id }) ?? fallback },
            set: { updated in
                var layers = main.activePlayer.layers
                guard let index = layers.firstIndex(where: { $0.mediaClip.file.id == id }) else { return }
                layers[index] = updated
                main.activePlayer.layers = layers
                main.activePlayer.notifySessionMutated()
            }
        )
    }

    private func layerIndex(for id: UUID) -> Int? {
        main.activePlayer.layers.firstIndex(where: { $0.mediaClip.file.id == id })
    }

    private func toggleExpanded(id: UUID) {
        if expandedLayerIDs.contains(id) {
            expandedLayerIDs.remove(id)
        } else {
            expandedLayerIDs.insert(id)
        }
    }

    private func moveLayer(sourceID: UUID, targetID: UUID) {
        guard sourceID != targetID else { return }

        var layers = main.activePlayer.layers
        guard let fromIndex = layers.firstIndex(where: { $0.mediaClip.file.id == sourceID }) else { return }
        guard let toIndex = layers.firstIndex(where: { $0.mediaClip.file.id == targetID }) else { return }
        guard fromIndex != toIndex else { return }

        let selectedID: UUID? = {
            let selectedIndex = main.activePlayer.currentSourceIndex
            guard selectedIndex >= 0, selectedIndex < layers.count else { return nil }
            return layers[selectedIndex].mediaClip.file.id
        }()

        withAnimation(.easeInOut(duration: 0.15)) {
            let movedLayer = layers.remove(at: fromIndex)
            var destination = toIndex
            if fromIndex < toIndex {
                destination -= 1
            }
            layers.insert(movedLayer, at: max(0, min(destination, layers.count)))
            main.activePlayer.layers = layers
        }

        if let selectedID, let newIndex = layers.firstIndex(where: { $0.mediaClip.file.id == selectedID }) {
            main.activePlayer.selectSource(newIndex)
        }

        main.activePlayer.notifySessionChanged()
    }
}

private struct CompositionLayerReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedLayerID: UUID?
    let moveLayer: (UUID, UUID) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggedLayerID else { return }
        guard sourceID != targetID else { return }
        moveLayer(sourceID, targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedLayerID = nil
        return true
    }

    func dropExited(info: DropInfo) {
    }
}
