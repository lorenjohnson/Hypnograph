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
                sectionTitle("New Compositions")

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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(windowPanelBackground)
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
    private func row(@ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Composition Length")
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

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Play Rate Range")
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

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
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: isOn)
            HStack {
                Text("Frequency")
                Spacer()
                Text("\(Int((frequency.wrappedValue * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: frequency, in: 0...1)
        }
    }
}

private var windowPanelBackground: some View {
    Color.black.opacity(0.96)
        .ignoresSafeArea()
}
