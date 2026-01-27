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
                    Text("\(dream.activePlayer.layers.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if effectsSession.chains.isEmpty {
                    Text("No saved effect chains.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(effectsSession.chains.enumerated()), id: \.offset) { _, chain in
                        HStack(spacing: 8) {
                            Text(chain.name?.isEmpty == false ? (chain.name ?? "") : "Untitled")
                                .lineLimit(1)
                            Spacer()
                            Text("\(chain.effects.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.white.opacity(0.08))
                                )
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(12)
        }
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

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Global Effects")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(effectChainSummary(dream.activePlayer.effectChain))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Edit") {
                    state.windowState.set("effectsEditor", visible: true)
                    dream.activePlayer.selectGlobalLayer()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
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

    private func effectChainSummary(_ chain: EffectChain) -> String {
        if chain.effects.isEmpty { return "None" }
        let name = chain.name?.isEmpty == false ? (chain.name ?? "") : "Unnamed"
        return "\(name) (\(chain.effects.count))"
    }
}
