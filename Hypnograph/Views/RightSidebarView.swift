import SwiftUI
import CoreMedia
import HypnoCore

enum RightSidebarTab: Int, Hashable {
    case composition = 0
    case effectChains = 1
}

struct RightSidebarView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream
    @ObservedObject var effectsSession: EffectsSession

    @State private var selectedTab: RightSidebarTab = .composition
    @State private var expandedLayerIDs: Set<UUID> = []

    @StateObject private var thumbnailStore = LayerThumbnailStore()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Composition").tag(RightSidebarTab.composition)
                Text("Effect Chains").tag(RightSidebarTab.effectChains)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            GlassDivider()

            switch selectedTab {
            case .composition:
                compositionTab()
            case .effectChains:
                effectChainsTab()
            }
        }
        .frame(width: SidebarMetrics.rightWidth)
        .glassPanel(cornerRadius: 16)
    }

    @ViewBuilder
    private func compositionTab() -> some View {
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
                        Button {
                            // Not implemented yet (kept for mockup parity)
                        } label: {
                            Label("Select Source...", systemImage: "photo.on.rectangle")
                        }
                        .disabled(true)

                        Button {
                            dream.addSource()
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
                    let snapshot = dream.activePlayer.layers
                    ForEach(snapshot, id: \.mediaClip.file.id) { snapshotLayer in
                        let id = snapshotLayer.mediaClip.file.id
                        let currentIndex = layerIndex(for: id)

                        if let currentIndex {
                            LayerRowView(
                                state: state,
                                dream: dream,
                                thumbnailStore: thumbnailStore,
                                index: currentIndex,
                                layer: bindingForLayer(id: id, fallback: snapshotLayer),
                                isSelected: dream.activePlayer.currentSourceIndex == currentIndex,
                                isExpanded: expandedLayerIDs.contains(id),
                                onSelect: {
                                    if let idx = layerIndex(for: id) {
                                        dream.activePlayer.selectSource(idx)
                                    }
                                },
                                onToggleExpanded: {
                                    toggleExpanded(id: id)
                                },
                                onDelete: {
                                    if let idx = layerIndex(for: id) {
                                        dream.activePlayer.selectSource(idx)
                                    }
                                    dream.removeCurrentLayer()
                                }
                            )
                            .animation(.easeInOut(duration: 0.2), value: expandedLayerIDs)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func effectChainsTab() -> some View {
        EffectChainLibraryView(
            state: state,
            dream: dream,
            session: effectsSession
        )
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
                    Text("\(Int(dream.activePlayer.targetDuration.seconds.rounded()))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: {
                            let seconds = dream.activePlayer.targetDuration.seconds
                            return max(1, min(seconds, 60))
                        },
                        set: { newValue in
                            let seconds = max(1, min(newValue.rounded(), 60))
                            dream.activePlayer.targetDuration = CMTime(seconds: seconds, preferredTimescale: 600)
                            dream.activePlayer.notifySessionMutated()
                        }
                    ),
                    in: 1...60,
                    step: 1
                )
            }
            .padding(.horizontal, 4)

            EffectChainView(
                state: state,
                dream: dream,
                layer: -1,
                title: "Effects"
            )
        }
    }

    private func bindingForLayer(id: UUID, fallback: HypnogramLayer) -> Binding<HypnogramLayer> {
        Binding(
            get: { dream.activePlayer.layers.first(where: { $0.mediaClip.file.id == id }) ?? fallback },
            set: { updated in
                var layers = dream.activePlayer.layers
                guard let index = layers.firstIndex(where: { $0.mediaClip.file.id == id }) else { return }
                layers[index] = updated
                dream.activePlayer.layers = layers
                dream.activePlayer.notifySessionMutated()
            }
        )
    }

    private func layerIndex(for id: UUID) -> Int? {
        dream.activePlayer.layers.firstIndex(where: { $0.mediaClip.file.id == id })
    }

    private func toggleExpanded(id: UUID) {
        if expandedLayerIDs.contains(id) {
            expandedLayerIDs.remove(id)
        } else {
            expandedLayerIDs.insert(id)
        }
    }

}
