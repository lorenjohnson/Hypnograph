import SwiftUI
import HypnoCore

struct PropertiesPanel: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio
    @ObservedObject private var settingsStore: StudioSettingsStore

    @State private var draftPlayRate: Double?
    @State private var draftTransitionDuration: Double?
    @State private var draftLayerOpacity: Double?

    init(state: HypnographState, main: Studio) {
        self.state = state
        self.main = main
        _settingsStore = ObservedObject(initialValue: state.settingsStore)
    }

    private var isLiveMode: Bool { main.isLiveMode }

    private var scopeBinding: Binding<PropertiesPanelScope> {
        Binding(
            get: { settingsStore.value.propertiesPanelScope },
            set: { newValue in
                settingsStore.update { settings in
                    settings.propertiesPanelScope = newValue
                }
            }
        )
    }

    private var selectedLayerIndex: Int? {
        let index = main.activePlayer.currentLayerIndex
        guard index >= 0, index < main.currentLayers.count else { return nil }
        return index
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: scopeBinding) {
                Text("Sequence").tag(PropertiesPanelScope.sequence)
                Text("Composition").tag(PropertiesPanelScope.composition)
                Text("Layer").tag(PropertiesPanelScope.layer)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            Group {
                switch settingsStore.value.propertiesPanelScope {
                case .sequence:
                    sequenceContent
                case .composition:
                    compositionContent
                case .layer:
                    layerContent
                }
            }
        }
        .padding(14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.96).ignoresSafeArea())
    }

    private var sequenceContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelSectionHeaderView(title: "Sequence")

            PanelInlineFieldRowView(title: "Transition Style") {
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
                title: "Transition Duration",
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

            // Hidden for now while we simplify the sequence-level framing controls.
            // Keep the fit-mode implementation nearby so it can be restored quickly
            // if we decide the distinction needs to come back into the Properties panel.
            // PanelInlineFieldRowView(title: "Fit Mode") {
            //     sourceFramingButtons
            // }

            Text("Aspect Ratio")
                .font(.callout)
                .foregroundStyle(.primary)

            aspectRatioButtons

            PanelGlassDividerView()
                .padding(.vertical, 4)

            EffectChainSectionView(
                state: state,
                main: main,
                target: .hypnogram,
                title: "Effects",
                isCollapsible: true
            )
        }
        .disabled(isLiveMode)
        .opacity(isLiveMode ? 0.55 : 1.0)
    }

    private var compositionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelSectionHeaderView(title: "Composition")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Play Rate")
                        .font(.callout)
                    Spacer()
                    Text(String(format: "%.0f%%", (draftPlayRate ?? Double(main.playRate)) * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                PanelSliderView(
                    value: Binding(
                        get: { draftPlayRate ?? Double(main.playRate) },
                        set: { draftPlayRate = $0 }
                    ),
                    bounds: 0.2...2.0,
                    step: 0.1,
                    onEditingChanged: { isEditing in
                        if isEditing {
                            draftPlayRate = Double(main.playRate)
                        } else {
                            if let draftPlayRate {
                                main.playRate = Float(draftPlayRate)
                            }
                            draftPlayRate = nil
                        }
                    }
                )
            }

            PanelInlineFieldRowView(title: "Transition Style") {
                Picker(
                    "",
                    selection: Binding(
                        get: { main.currentCompositionTransitionStyleOverride },
                        set: { newValue in
                            main.setCurrentCompositionTransitionStyle(newValue)
                        }
                    )
                ) {
                    Text("Sequence Default (\(main.currentHypnogramTransitionStyle.displayName))")
                        .tag(Optional<TransitionRenderer.TransitionType>.none)

                    ForEach(TransitionRenderer.TransitionType.allCases, id: \.self) { style in
                        Text(style.displayName)
                            .tag(style as TransitionRenderer.TransitionType?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180, alignment: .trailing)
            }

            if main.currentCompositionTransitionStyleOverride != nil {
                PanelFieldRowView(
                    title: "Transition Duration",
                    valueText: String(format: "%.1fs", draftTransitionDuration ?? main.currentCompositionTransitionDuration)
                ) {
                    PanelSliderView(
                        value: Binding(
                            get: { draftTransitionDuration ?? main.currentCompositionTransitionDuration },
                            set: { draftTransitionDuration = $0 }
                        ),
                        bounds: 0.1...3.0,
                        step: 0.1,
                        onEditingChanged: { isEditing in
                            if isEditing {
                                draftTransitionDuration = main.currentCompositionTransitionDuration
                            } else {
                                if let draftTransitionDuration {
                                    main.setCurrentCompositionTransitionDuration(draftTransitionDuration)
                                }
                                draftTransitionDuration = nil
                            }
                        }
                    )
                }
            }

            EffectChainSectionView(
                state: state,
                main: main,
                target: .composition,
                title: "Effects"
            )
        }
        .disabled(isLiveMode)
        .opacity(isLiveMode ? 0.55 : 1.0)
    }

    @ViewBuilder
    private var layerContent: some View {
        if let layerIndex = selectedLayerIndex {
            let layerBinding = bindingForLayer(at: layerIndex)

            VStack(alignment: .leading, spacing: 16) {
                PanelSectionHeaderView(title: "Layer")

                VStack(alignment: .leading, spacing: 2) {
                    Text(LayerMetadataFormatter.displayLabel(for: layerBinding.wrappedValue))
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text("Layer \(layerIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                PanelInlineFieldRowView(title: "Blend") {
                    Picker("", selection: Binding(
                        get: {
                            if layerIndex == 0 {
                                return BlendMode.sourceOver
                            }
                            return layerBinding.wrappedValue.blendMode ?? BlendMode.defaultMontage
                        },
                        set: { newValue in
                            guard layerIndex != 0 else { return }
                            var updated = layerBinding.wrappedValue
                            updated.blendMode = newValue
                            layerBinding.wrappedValue = updated
                        }
                    )) {
                        Text("Normal").tag(BlendMode.sourceOver)
                        ForEach(BlendMode.all, id: \.self) { mode in
                            Text(blendModeName(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160, alignment: .trailing)
                    .disabled(layerIndex == 0)
                }

                PanelFieldRowView(
                    title: "Opacity",
                    valueText: "\(Int((draftLayerOpacity ?? layerBinding.wrappedValue.opacity).clamped(to: 0...1) * 100))%"
                ) {
                    PanelSliderView(
                        value: Binding(
                            get: { draftLayerOpacity ?? layerBinding.wrappedValue.opacity.clamped(to: 0...1) },
                            set: { draftLayerOpacity = $0 }
                        ),
                        bounds: 0...1,
                        step: 0.01,
                        onEditingChanged: { isEditing in
                            if isEditing {
                                draftLayerOpacity = layerBinding.wrappedValue.opacity.clamped(to: 0...1)
                            } else {
                                if let draftLayerOpacity {
                                    var updated = layerBinding.wrappedValue
                                    updated.opacity = draftLayerOpacity.clamped(to: 0...1)
                                    layerBinding.wrappedValue = updated
                                }
                                draftLayerOpacity = nil
                            }
                        }
                    )
                }

                EffectChainSectionView(
                    state: state,
                    main: main,
                    target: .layer(layerIndex),
                    title: "Effects"
                )
            }
            .disabled(isLiveMode)
            .opacity(isLiveMode ? 0.55 : 1.0)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                PanelSectionHeaderView(title: "Layer")
                Text("No layer selected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bindingForLayer(at index: Int) -> Binding<Layer> {
        let fallback = main.currentLayers[index]
        return Binding(
            get: {
                guard index < main.currentLayers.count else { return fallback }
                return main.currentLayers[index]
            },
            set: { updated in
                guard index < main.currentLayers.count else { return }
                var layers = main.currentLayers
                layers[index] = updated
                main.currentLayers = layers
                main.notifyHypnogramMutated()
            }
        )
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
    private func blendModeName(_ mode: String) -> String {
        if mode == BlendMode.sourceOver {
            return "Normal"
        }
        return blendModeNameFromCoreImageFilter(mode)
    }

    private func blendModeNameFromCoreImageFilter(_ filterName: String) -> String {
        let stripped = filterName
            .replacingOccurrences(of: "CI", with: "")
            .replacingOccurrences(of: "Compositing", with: "")
            .replacingOccurrences(of: "BlendMode", with: "")
        return stripped.replacingOccurrences(of: "(?<!^)([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
