import SwiftUI
import HypnoCore

struct OutputSettingsPanel: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    private var isLiveMode: Bool { main.isLiveMode }
    private var player: PlayerState { main.activePlayer }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelSectionHeaderView(title: "Playback")

            PanelInlineFieldRowView(title: "Transition Style") {
                Picker("", selection: Binding(
                    get: { state.settings.transitionStyle },
                    set: { newValue in
                        state.settingsStore.update { $0.transitionStyle = newValue }
                    }
                )) {
                    ForEach(TransitionRenderer.TransitionType.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160, alignment: .trailing)
            }

            PanelFieldRowView(
                title: "Transition Duration",
                valueText: String(format: "%.1fs", state.settings.transitionDuration)
            ) {
                PanelSliderView(
                    value: Binding(
                        get: { state.settings.transitionDuration },
                        set: { newValue in
                            state.settingsStore.update { $0.transitionDuration = newValue }
                        }
                    ),
                    bounds: 0.1...3.0,
                    step: 0.1
                )
            }

            PanelGlassDividerView()
                .padding(.vertical, 4)

            PanelSectionHeaderView(title: "Display")

            PanelInlineFieldRowView(title: "Source Framing") {
                sourceFramingButtons
            }

            PanelInlineFieldRowView(title: "Aspect Ratio") {
                aspectRatioButtons
                    .frame(width: 170, alignment: .trailing)
                    .disabled(isLiveMode)
                    .opacity(isLiveMode ? 0.55 : 1.0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.96).ignoresSafeArea())
    }

    @ViewBuilder
    private var sourceFramingButtons: some View {
        HStack(spacing: 5) {
            ForEach(SourceFraming.allCases, id: \.self) { framing in
                let isSelected = state.settings.sourceFraming == framing
                Button {
                    state.settingsStore.update { $0.sourceFraming = framing }
                } label: {
                    Text(shortFramingLabel(for: framing))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .frame(width: 34, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.86) : Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .help(framing.displayName)
            }
        }
    }

    @ViewBuilder
    private var aspectRatioButtons: some View {
        let selectedRatio = isLiveMode ? main.livePlayer.config.aspectRatio : player.config.aspectRatio

        HStack(spacing: 4) {
            ForEach(AspectRatio.menuPresets, id: \.displayString) { ratio in
                let isSelected = selectedRatio == ratio
                Button {
                    guard !isLiveMode else { return }
                    player.config.aspectRatio = ratio
                } label: {
                    Text(shortAspectRatioLabel(for: ratio))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .frame(width: 30, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.86) : Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .help(ratio.menuLabel)
            }
        }
    }

    private func shortFramingLabel(for framing: SourceFraming) -> String {
        let key = framing.displayName.lowercased()
        if key.contains("fit") { return "Fit" }
        if key.contains("fill") { return "Fill" }
        return framing.displayName
    }

    private func shortAspectRatioLabel(for ratio: AspectRatio) -> String {
        ratio.isFillWindow ? "Fill" : ratio.displayString
    }
}
