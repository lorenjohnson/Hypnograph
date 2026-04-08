import SwiftUI
import CoreMedia
import UniformTypeIdentifiers
import HypnoCore

struct CompositionPanel: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    @State private var expandedLayerIDs: Set<UUID> = []
    @State private var draggedLayerID: UUID?
    @StateObject private var thumbnailStore = TimelineThumbnailStore()
    @SwiftUI.Environment(\.panelLayoutInvalidator) private var panelLayoutInvalidator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            compositionSection

            PanelGlassDividerView()
                .padding(.vertical, 4)

            HStack {
                Text("Layers")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button {
                        main.addSourceFromFilesPanel()
                    } label: {
                        Label("From Files...", systemImage: "doc")
                    }

                    Button {
                        main.addSourceFromPhotosPicker()
                    } label: {
                        Label("From Photos...", systemImage: "photo")
                    }
                    .disabled(!state.photosAuthorizationStatus.canRead)

                    Button {
                        main.addSourceFromRandom()
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
                let snapshot = main.currentLayers
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
                            isSelected: main.activePlayer.currentLayerIndex == currentIndex,
                            isExpanded: expandedLayerIDs.contains(id),
                            onSelect: {
                                if let idx = layerIndex(for: id) {
                                    main.selectSource(idx)
                                }
                            },
                            onToggleExpanded: {
                                toggleExpanded(id: id)
                            },
                            onDuplicate: {
                                if let idx = layerIndex(for: id) {
                                    main.selectSource(idx)
                                }
                                main.duplicateCurrentLayer()
                            },
                            onDelete: {
                                if let idx = layerIndex(for: id) {
                                    main.selectSource(idx)
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
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.96).ignoresSafeArea())
        .onChange(of: expandedLayerIDs) { _, _ in
            panelLayoutInvalidator()
        }
    }

    private var compositionSection: some View {
        let isSelected = main.activePlayer.currentLayerIndex == -1

        return VStack(alignment: .leading, spacing: 10) {
            Text("Composition")
                .font(.headline)
                .foregroundStyle(isSelected ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Play Rate")
                        .font(.callout)
                    Spacer()
                    Text(String(format: "%.0f%%", main.playRate * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                PanelSliderView(
                    value: Binding(
                        get: { Double(main.playRate) },
                        set: { main.playRate = Float($0) }
                    ),
                    bounds: 0.2...2.0,
                    step: 0.1
                )
            }
            .disabled(main.isLiveMode)
            .opacity(main.isLiveMode ? 0.55 : 1.0)

            EffectChainSectionView(
                state: state,
                main: main,
                layer: -1,
                title: "Effects"
            )
        }
        .padding(10)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.0 : 0.5)
        )
        .onTapGesture {
            main.selectCompositionLayer()
        }
    }

    private func bindingForLayer(id: UUID, fallback: Layer) -> Binding<Layer> {
        Binding(
            get: { main.currentLayers.first(where: { $0.mediaClip.file.id == id }) ?? fallback },
            set: { updated in
                var layers = main.currentLayers
                guard let index = layers.firstIndex(where: { $0.mediaClip.file.id == id }) else { return }
                layers[index] = updated
                main.currentLayers = layers
                main.notifyHypnogramMutated()
            }
        )
    }

    private func layerIndex(for id: UUID) -> Int? {
        main.currentLayers.firstIndex(where: { $0.mediaClip.file.id == id })
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

        var layers = main.currentLayers
        guard let fromIndex = layers.firstIndex(where: { $0.mediaClip.file.id == sourceID }) else { return }
        guard let toIndex = layers.firstIndex(where: { $0.mediaClip.file.id == targetID }) else { return }
        guard fromIndex != toIndex else { return }

        let selectedID: UUID? = {
            let selectedIndex = main.activePlayer.currentLayerIndex
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
            main.currentLayers = layers
        }

        if let selectedID, let newIndex = layers.firstIndex(where: { $0.mediaClip.file.id == selectedID }) {
            main.selectSource(newIndex)
        }

        main.notifyHypnogramChanged()
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
