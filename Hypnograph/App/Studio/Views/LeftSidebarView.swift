import SwiftUI
import HypnoCore

struct LeftSidebarView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio
    @ObservedObject var player: PlayerState
    @ObservedObject private var externalLoadHarness = ExternalMediaLoadHarness.shared

    private var isLiveMode: Bool { main.isLiveMode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Playback")

                    row {
                        Text("Transition Style")
                        Spacer()
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
                        .frame(width: 140, alignment: .trailing)
                    }

                    labeledSliderRow(
                        title: "Transition Duration",
                        valueText: String(format: "%.1fs", state.settings.transitionDuration),
                        slider: {
                            Slider(value: Binding(
                                get: { state.settings.transitionDuration },
                                set: { newValue in
                                    state.settingsStore.update { $0.transitionDuration = newValue }
                                }
                            ), in: 0.1...3.0, step: 0.1)
                        }
                    )

                    sectionDivider()

                    sectionTitle("Display")

                    row {
                        Text("Source Framing")
                        Spacer()
                        sourceFramingButtons
                    }

                    row {
                        Text("Aspect Ratio")
                        Spacer()
                        aspectRatioButtons
                            .frame(width: 170, alignment: .trailing)
                        .disabled(isLiveMode)
                        .opacity(isLiveMode ? 0.55 : 1.0)
                    }

                    sectionDivider()

                    sectionTitle("New Clips")

                    row {
                        Text("Max Layers")
                        Spacer()
                        Text("\(player.config.maxLayers)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Stepper("", value: $player.config.maxLayers, in: 1...20)
                            .labelsHidden()
                            .disabled(isLiveMode)
                            .opacity(isLiveMode ? 0.55 : 1.0)
                    }

                    clipLengthRangeRow()
                    playRateRangeRow()

                    randomizationRow(
                        title: "Randomize Global Effect",
                        isOn: Binding(
                            get: { state.settings.randomGlobalEffect },
                            set: { newValue in
                                state.settingsStore.update { $0.randomGlobalEffect = newValue }
                            }
                        ),
                        frequency: Binding(
                            get: { state.settings.randomGlobalEffectFrequency },
                            set: { newValue in
                                state.settingsStore.update { $0.randomGlobalEffectFrequency = newValue }
                            }
                        )
                    )
                    .disabled(isLiveMode)
                    .opacity(isLiveMode ? 0.55 : 1.0)

                    randomizationRow(
                        title: "Randomize Layer Effects",
                        isOn: Binding(
                            get: { state.settings.randomLayerEffect },
                            set: { newValue in
                                state.settingsStore.update { $0.randomLayerEffect = newValue }
                            }
                        ),
                        frequency: Binding(
                            get: { state.settings.randomLayerEffectFrequency },
                            set: { newValue in
                                state.settingsStore.update { $0.randomLayerEffectFrequency = newValue }
                            }
                        )
                    )
                    .disabled(isLiveMode)
                    .opacity(isLiveMode ? 0.55 : 1.0)

#if DEBUG
                    sectionDivider()

                    sectionTitle("Debug")

                    row {
                        Text("Load Scenario")
                        Spacer()
                        Picker("", selection: $externalLoadHarness.scenario) {
                            ForEach(ExternalMediaLoadHarness.Scenario.allCases) { scenario in
                                Text(scenario.displayName).tag(scenario)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 190, alignment: .trailing)
                    }
#endif

            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: SidebarMetrics.leftWidth)
        .glassPanel(cornerRadius: 16)
    }

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sectionDivider() -> some View {
        GlassDivider()
            .padding(.vertical, 4)
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

    @ViewBuilder
    private func row(@ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func labeledSliderRow(
        title: String,
        valueText: String,
        @ViewBuilder slider: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            slider()
        }
    }

    @ViewBuilder
    private func clipLengthRangeRow() -> some View {
        let bounds: ClosedRange<Double> = 1...60
        let minDistance: Double = 2

        let range = Binding<ClosedRange<Double>>(
            get: {
                let lower = state.settings.clipLengthMinSeconds.clamped(to: bounds)
                let upper = state.settings.clipLengthMaxSeconds.clamped(to: bounds)
                let fixedLower = min(lower, bounds.upperBound - minDistance)
                let fixedUpper = max(upper, fixedLower + minDistance).clamped(to: bounds)
                return fixedLower...fixedUpper
            },
            set: { newRange in
                let lower = newRange.lowerBound.rounded().clamped(to: bounds)
                let upper = newRange.upperBound.rounded().clamped(to: bounds)
                let fixedLower = min(lower, upper - minDistance).clamped(to: bounds)
                let fixedUpper = max(upper, fixedLower + minDistance).clamped(to: bounds)
                state.settingsStore.update {
                    $0.clipLengthMinSeconds = fixedLower
                    $0.clipLengthMaxSeconds = fixedUpper
                }
            }
        )

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Clip Length")
                Spacer()
                Text("\(Int(range.wrappedValue.lowerBound))–\(Int(range.wrappedValue.upperBound))s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            RangeSliderView(range: range, bounds: bounds, step: 1, minimumDistance: minDistance)
                .disabled(isLiveMode)
                .opacity(isLiveMode ? 0.55 : 1.0)
        }
    }

    @ViewBuilder
    private func playRateRangeRow() -> some View {
        let bounds: ClosedRange<Double> = 0.2...2.0
        let minDistance: Double = 0

        let range = Binding<ClosedRange<Double>>(
            get: {
                let lower = state.settings.clipPlayRateMin.clamped(to: bounds)
                let upper = state.settings.clipPlayRateMax.clamped(to: bounds)
                return min(lower, upper)...max(lower, upper)
            },
            set: { newRange in
                let lower = (newRange.lowerBound * 10).rounded() / 10
                let upper = (newRange.upperBound * 10).rounded() / 10
                let fixedLower = lower.clamped(to: bounds)
                let fixedUpper = upper.clamped(to: bounds)
                state.settingsStore.update {
                    $0.clipPlayRateMin = min(fixedLower, fixedUpper)
                    $0.clipPlayRateMax = max(fixedLower, fixedUpper)
                }
            }
        )

        let lowerPercent = Int((range.wrappedValue.lowerBound * 100).rounded())
        let upperPercent = Int((range.wrappedValue.upperBound * 100).rounded())
        let valueText = lowerPercent == upperPercent ? "\(lowerPercent)%" : "\(lowerPercent)–\(upperPercent)%"

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Play Rate Range")
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            RangeSliderView(range: range, bounds: bounds, step: 0.1, minimumDistance: minDistance)
                .disabled(isLiveMode)
                .opacity(isLiveMode ? 0.55 : 1.0)
        }
    }

    @ViewBuilder
    private func randomizationRow(
        title: String,
        isOn: Binding<Bool>,
        frequency: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row {
                Text(title)
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if isOn.wrappedValue {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Frequency")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((frequency.wrappedValue.clamped(to: 0...1)) * 100))%")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: Binding(
                        get: { frequency.wrappedValue.clamped(to: 0...1) },
                        set: { frequency.wrappedValue = $0.clamped(to: 0...1) }
                    ), in: 0...1)
                }
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
