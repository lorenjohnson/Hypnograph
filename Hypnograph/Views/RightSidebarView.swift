import SwiftUI
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
        .frame(width: 300)
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
                            Label("Select Source…", systemImage: "photo.on.rectangle")
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

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(dream.activePlayer.layers.indices, id: \.self) { index in
                        LayerRowView(
                            state: state,
                            dream: dream,
                            thumbnailStore: thumbnailStore,
                            index: index,
                            layer: bindingForLayer(index: index),
                            isSelected: dream.activePlayer.currentSourceIndex == index,
                            isExpanded: expandedLayerIDs.contains(dream.activePlayer.layers[index].mediaClip.file.id),
                            onSelect: {
                                dream.activePlayer.selectSource(index)
                            },
                            onToggleExpanded: {
                                toggleExpanded(id: dream.activePlayer.layers[index].mediaClip.file.id)
                            }
                        )
                        .animation(.easeInOut(duration: 0.2), value: expandedLayerIDs)
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

            HStack {
                Text("Clip Length")
                Spacer()
                Text("\(Int(state.settings.clipLengthMinSeconds.rounded()))–\(Int(state.settings.clipLengthMaxSeconds.rounded()))s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            EffectChainView(
                state: state,
                dream: dream,
                layer: -1,
                title: "Effects"
            )
        }
    }

    private func bindingForLayer(index: Int) -> Binding<HypnogramLayer> {
        Binding(
            get: { dream.activePlayer.layers[index] },
            set: { updated in
                var layers = dream.activePlayer.layers
                guard index < layers.count else { return }
                layers[index] = updated
                dream.activePlayer.layers = layers
                dream.activePlayer.notifySessionMutated()
            }
        )
    }

    private func toggleExpanded(id: UUID) {
        if expandedLayerIDs.contains(id) {
            expandedLayerIDs.remove(id)
        } else {
            expandedLayerIDs.insert(id)
        }
    }

}
