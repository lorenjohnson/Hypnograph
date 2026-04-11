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

            PanelInlineFieldRowView(title: "Sequence Transition Style") {
                Picker("", selection: Binding(
                    get: { main.currentHypnogramTransitionStyle },
                    set: { newValue in
                        main.setTransitionStyle(newValue)
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
                title: "Sequence Transition Duration",
                valueText: String(format: "%.1fs", main.currentHypnogramTransitionDuration)
            ) {
                PanelSliderView(
                    value: Binding(
                        get: { main.currentHypnogramTransitionDuration },
                        set: { newValue in
                            main.setTransitionDuration(newValue)
                        }
                    ),
                    bounds: 0.1...3.0,
                    step: 0.1
                )
            }

            PanelGlassDividerView()
                .padding(.vertical, 4)

            // Hidden for now while we simplify the output/display controls.
            // Keep the fit-mode control implementation here so it can be restored quickly
            // if we decide the distinction needs to come back into the panel.
            // PanelInlineFieldRowView(title: "Fit Mode") {
            //     sourceFramingButtons
            // }

            Text("Aspect Ratio")
                .font(.callout)
                .foregroundStyle(.primary)

            aspectRatioButtons
                .disabled(isLiveMode)
                .opacity(isLiveMode ? 0.55 : 1.0)

            PanelGlassDividerView()
                .padding(.vertical, 4)

            EffectChainSectionView(
                state: state,
                main: main,
                target: .hypnogram,
                title: "Sequence Effects",
                isCollapsible: true
            )
            .disabled(isLiveMode)
            .opacity(isLiveMode ? 0.55 : 1.0)
        }
        .padding(14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.96).ignoresSafeArea())
    }

    @ViewBuilder
    private var sourceFramingButtons: some View {
        HStack(spacing: 5) {
            ForEach(SourceFraming.allCases, id: \.self) { framing in
                let isSelected = main.currentHypnogramSourceFraming == framing
                Button {
                    main.setSourceFraming(framing)
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
        let selectedRatio = main.currentHypnogramAspectRatio

        HStack(spacing: 4) {
            ForEach(AspectRatio.menuPresets, id: \.displayString) { ratio in
                let isSelected = selectedRatio == ratio
                Button {
                    guard !isLiveMode else { return }
                    main.setAspectRatio(ratio)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: aspectRatioSystemImage(for: ratio))
                            .font(.caption.weight(.semibold))
                        Text(shortAspectRatioLabel(for: ratio))
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.86) : Color.white.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
                .help(ratio.menuLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func aspectRatioSystemImage(for ratio: AspectRatio) -> String {
        switch ratio.displayString {
        case "fill":
            return "aspectratio"
        case "16:9":
            return "rectangle.ratio.16.to.9"
        case "9:16":
            return "rectangle.portrait"
        case "4:3":
            return "rectangle.ratio.4.to.3"
        case "1:1":
            return "square"
        default:
            return "aspectratio"
        }
    }
}
