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
                Text("Global")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Clip Length")
                        Spacer()
                        Text("\(Int(state.settings.clipLengthMinSeconds.rounded()))–\(Int(state.settings.clipLengthMaxSeconds.rounded()))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

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
                    ForEach(Array(dream.activePlayer.layers.enumerated()), id: \.offset) { index, layer in
                        layerRow(index: index, layer: layer)
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

    @ViewBuilder
    private func layerRow(index: Int, layer: HypnogramLayer) -> some View {
        let isSelected = (dream.activePlayer.currentSourceIndex == index)
        let label = layerLabel(layer)

        Button {
            if isSelected {
                dream.activePlayer.selectGlobalLayer()
            } else {
                dream.activePlayer.selectSource(index)
            }
        } label: {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 22, alignment: .trailing)

                Text(label)
                    .font(.callout)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.0 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func layerLabel(_ layer: HypnogramLayer) -> String {
        switch layer.mediaClip.file.source {
        case .url(let url):
            return url.lastPathComponent
        case .external(let identifier):
            return identifier
        }
    }
}

