import SwiftUI
import HypnoCore

struct NewClipsWindowView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio
    @ObservedObject var player: PlayerState
    @ObservedObject private var externalLoadHarness = ExternalMediaLoadHarness.shared

    private var isLiveMode: Bool { main.isLiveMode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelInlineFieldRow(title: "Max Layers", valueText: "\(player.config.maxLayers)") {
                    Stepper("", value: $player.config.maxLayers, in: 1...20)
                        .labelsHidden()
                        .disabled(isLiveMode)
                        .opacity(isLiveMode ? 0.55 : 1.0)
                }

                compositionLengthRangeRow()
                playRateRangeRow()

                randomizationRow(
                    title: "Randomize Composition Effect",
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

                PanelSectionHeader(title: "Debug")

                PanelInlineFieldRow(title: "Load Scenario") {
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(windowPanelBackground)
    }

    @ViewBuilder
    private func sectionDivider() -> some View {
        GlassDivider()
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func compositionLengthRangeRow() -> some View {
        let bounds: ClosedRange<Double> = 1...60
        let minDistance: Double = 2

        let range = Binding<ClosedRange<Double>>(
            get: {
                let lower = state.settings.compositionLengthMinSeconds.clamped(to: bounds)
                let upper = state.settings.compositionLengthMaxSeconds.clamped(to: bounds)
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
                    $0.compositionLengthMinSeconds = fixedLower
                    $0.compositionLengthMaxSeconds = fixedUpper
                }
            }
        )

        PanelFieldRow(
            title: "Composition Length (Range)",
            valueText: "\(Int(range.wrappedValue.lowerBound))–\(Int(range.wrappedValue.upperBound))s"
        ) {
            RangeSliderView(range: range, bounds: bounds, step: 1, minimumDistance: minDistance)
                .disabled(isLiveMode)
                .opacity(isLiveMode ? 0.55 : 1.0)
        }
    }

    @ViewBuilder
    private func playRateRangeRow() -> some View {
        let bounds: ClosedRange<Double> = 0.2...2.0

        let range = Binding<ClosedRange<Double>>(
            get: {
                let lower = state.settings.compositionPlayRateMin.clamped(to: bounds)
                let upper = state.settings.compositionPlayRateMax.clamped(to: bounds)
                return min(lower, upper)...max(lower, upper)
            },
            set: { newRange in
                let lower = (newRange.lowerBound * 10).rounded() / 10
                let upper = (newRange.upperBound * 10).rounded() / 10
                let fixedLower = lower.clamped(to: bounds)
                let fixedUpper = upper.clamped(to: bounds)
                state.settingsStore.update {
                    $0.compositionPlayRateMin = min(fixedLower, fixedUpper)
                    $0.compositionPlayRateMax = max(fixedLower, fixedUpper)
                }
            }
        )

        let lowerPercent = Int((range.wrappedValue.lowerBound * 100).rounded())
        let upperPercent = Int((range.wrappedValue.upperBound * 100).rounded())
        let valueText = lowerPercent == upperPercent ? "\(lowerPercent)%" : "\(lowerPercent)–\(upperPercent)%"

        PanelFieldRow(title: "Play Rate (Range)", valueText: valueText) {
            RangeSliderView(range: range, bounds: bounds, step: 0.1, minimumDistance: 0)
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
            PanelInlineFieldRow(title: title) {
                PanelToggleView(isOn: isOn)
                    .fixedSize()
            }

            PanelFieldRow(
                title: "Frequency",
                valueText: "\(Int((frequency.wrappedValue * 100).rounded()))%"
            ) {
                PanelSliderView(value: frequency, bounds: 0...1, step: 0.01)
            }
        }
    }
}

private var windowPanelBackground: some View {
    Color.black.opacity(0.96)
        .ignoresSafeArea()
}
