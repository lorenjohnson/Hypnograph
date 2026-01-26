import SwiftUI
import HypnoCore

struct LeftSidebarView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream
    @ObservedObject var player: DreamPlayerState

    @StateObject private var audioManager = AudioDeviceManager.shared

    private var isLiveMode: Bool { dream.isLiveMode }

    var body: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            GlassDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("Watch")

                    row {
                        Text("Watch")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { state.settings.watchMode },
                            set: { _ in state.toggleWatchMode() }
                        ))
                        .labelsHidden()
                        .controlSize(.small)
                    }

                    PlayRateControl(playRate: $player.playRate)
                        .disabled(isLiveMode)
                        .opacity(isLiveMode ? 0.55 : 1.0)

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
                        .fixedSize()
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

                    sectionTitle("Display")

                    row {
                        Text("Source Framing")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { state.settings.sourceFraming },
                            set: { newValue in
                                state.settingsStore.update { $0.sourceFraming = newValue }
                            }
                        )) {
                            ForEach(SourceFraming.allCases, id: \.self) { framing in
                                Text(framing.displayName).tag(framing)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }

                    row {
                        Text("Aspect Ratio")
                        Spacer()
                        Picker("", selection: isLiveMode ? .constant(dream.livePlayer.config.aspectRatio) : $player.config.aspectRatio) {
                            ForEach(AspectRatio.menuPresets, id: \.displayString) { ratio in
                                Text(ratio.menuLabel).tag(ratio)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .disabled(isLiveMode)
                        .opacity(isLiveMode ? 0.55 : 1.0)
                    }

                    sectionTitle("Audio")

                    audioDeviceRow(
                        title: "Preview",
                        selection: Binding(
                            get: { dream.previewAudioDevice },
                            set: { dream.previewAudioDevice = $0 }
                        ),
                        volume: Binding(
                            get: { Double(dream.previewVolume) },
                            set: { dream.previewVolume = Float($0) }
                        )
                    )

                    audioDeviceRow(
                        title: "Live",
                        selection: Binding(
                            get: { dream.liveAudioDevice },
                            set: { dream.liveAudioDevice = $0 }
                        ),
                        volume: Binding(
                            get: { Double(dream.liveVolume) },
                            set: { dream.liveVolume = Float($0) }
                        )
                    )

                    GlassDivider()
                        .padding(.vertical, 4)

                    sectionTitle("Generation")

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
                }
                .padding(12)
            }
        }
        .frame(width: 280)
        .glassPanel(cornerRadius: 16)
    }

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(@ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 8) {
            content()
        }
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
    private func audioDeviceRow(
        title: String,
        selection: Binding<AudioOutputDevice?>,
        volume: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row {
                Text(title)
                Spacer()
                Picker("", selection: selection) {
                    ForEach(audioManager.outputDevices) { device in
                        Text(device.name).tag(device as AudioOutputDevice?)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            HStack(spacing: 8) {
                Image(systemName: volume.wrappedValue <= 0.001 ? "speaker.slash.fill" : "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(value: volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func clipLengthRangeRow() -> some View {
        let minSeconds = Binding(
            get: { state.settings.clipLengthMinSeconds },
            set: { newValue in
                let clamped = max(1, min(newValue, state.settings.clipLengthMaxSeconds))
                state.settingsStore.update { $0.clipLengthMinSeconds = clamped }
            }
        )

        let maxSeconds = Binding(
            get: { state.settings.clipLengthMaxSeconds },
            set: { newValue in
                let clamped = max(newValue, state.settings.clipLengthMinSeconds)
                state.settingsStore.update { $0.clipLengthMaxSeconds = clamped }
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Clip Length")
                Spacer()
                Text("\(Int(minSeconds.wrappedValue.rounded()))–\(Int(maxSeconds.wrappedValue.rounded()))s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                Slider(value: minSeconds, in: 1...60, step: 1) {
                    Text("Min")
                }
                .disabled(isLiveMode)
                .opacity(isLiveMode ? 0.55 : 1.0)

                Slider(value: maxSeconds, in: minSeconds.wrappedValue...120, step: 1) {
                    Text("Max")
                }
                .disabled(isLiveMode)
                .opacity(isLiveMode ? 0.55 : 1.0)
            }
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
                .padding(.leading, 18)
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
