import SwiftUI
import HypnoCore

struct PlayerControlsPanel: View {
    let isPaused: Bool
    let isLoopCompositionEnabled: Bool
    let isLoopSequenceEnabled: Bool
    let isGenerateAtEndEnabled: Bool
    let selectedLayerIndex: Int
    let compositionLengthSeconds: Double
    let currentCompositionTimeSeconds: Double?
    let isShowingFullClips: Bool
    let panelToolbarItems: [StudioPanelToolbarItem]
    let isPanelVisible: (String) -> Bool
    let liveModeSelection: Binding<Int>?
    let sequenceEntries: [CompositionEntry]
    let layerTrimContexts: [LayerTrimContext]
    let renderQueueCount: Int
    let visualOpacity: Double
    @Binding var panelOpacity: Double
    @Binding var volume: Double
    let onTogglePanel: (String) -> Void
    let onJumpToComposition: (Int) -> Void
    let onDeleteCompositionEntry: (Int) -> Void
    let onMoveComposition: (UUID, UUID) -> Void
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onSelectLayer: (Int) -> Void
    let onMoveLayerUp: (Int) -> Void
    let onMoveLayerDown: (Int) -> Void
    let onDeleteLayer: (Int) -> Void
    let onSetLayerBlendMode: (Int, String) -> Void
    let onSetLayerOpacity: (Int, Double) -> Void
    let onToggleLayerMute: (Int) -> Void
    let onToggleLayerSolo: (Int) -> Void
    let onToggleLayerVisibility: (Int) -> Void
    let onAddSourceFromFiles: () -> Void
    let onAddSourceFromPhotos: () -> Void
    let onAddSourceFromRandom: () -> Void
    let onToggleShowFullClips: () -> Void
    let onToggleGenerateAtEnd: () -> Void
    let onCyclePlaybackLoopMode: () -> Void
    let onSnapshotCurrent: () -> Void
    let onRenderCurrent: () -> Void
    let onRenderSequence: () -> Void
    let onCommitLayerTrimRange: (Int, ClosedRange<Double>) -> Void

    @State private var previousVolumeBeforeMute: Double = 0.8
    @State private var draggedCompositionID: UUID?

    private var totalSequenceDurationSeconds: Double {
        sequenceEntries.reduce(0) { partial, entry in
            partial + entry.composition.effectiveDuration.seconds
        }
    }

    private var chromeOpacity: Double {
        visualOpacity.clamped(to: 0.32...0.92)
    }

    var body: some View {
        VStack(spacing: 10) {
            controlsRow

            if !layerTrimContexts.isEmpty {
                LayerTrimView(
                    contexts: layerTrimContexts,
                    selectedLayerIndex: selectedLayerIndex,
                    compositionTimelineDurationSeconds: compositionLengthSeconds,
                    currentPlayheadSeconds: currentCompositionTimeSeconds,
                    isShowingFullClips: isShowingFullClips,
                    visualOpacity: chromeOpacity,
                    onSelectLayer: onSelectLayer,
                    onMoveLayerUp: onMoveLayerUp,
                    onMoveLayerDown: onMoveLayerDown,
                    onDeleteLayer: onDeleteLayer,
                    onSetBlendMode: onSetLayerBlendMode,
                    onSetOpacity: onSetLayerOpacity,
                    onToggleMute: onToggleLayerMute,
                    onToggleSolo: onToggleLayerSolo,
                    onToggleVisibility: onToggleLayerVisibility,
                    onToggleShowFullClips: onToggleShowFullClips,
                    onCommit: onCommitLayerTrimRange
                )
            }

            if !sequenceEntries.isEmpty {
                SequenceLaneView(
                    compositionEntries: sequenceEntries,
                    summaryText: "\(formatTime(totalSequenceDurationSeconds)) / \(formatTime(compositionLengthSeconds))",
                    draggedCompositionID: $draggedCompositionID,
                    onJumpToComposition: onJumpToComposition,
                    onDeleteCompositionEntry: onDeleteCompositionEntry,
                    onMoveComposition: onMoveComposition
                )
                .padding(.horizontal, 2)
            }

            dockHeader
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.18 + (0.58 * chromeOpacity)))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08 + (0.12 * chromeOpacity)), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.16 + (0.19 * chromeOpacity)), radius: 12, x: 0, y: 6)
        .onChange(of: volume) { _, newValue in
            if newValue > 0.001 {
                previousVolumeBeforeMute = newValue
            }
        }
    }

    private var dockHeader: some View {
        GeometryReader { geometry in
            let showPanelLabels = shouldShowPanelLabels(availableWidth: geometry.size.width)

            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(panelToolbarItems) { item in
                            panelToggleButton(item, showLabel: showPanelLabels)
                        }
                    }

                    PanelSliderView(
                        value: $panelOpacity,
                        bounds: 0.32...0.92,
                        fillColor: NSColor.secondaryLabelColor.withAlphaComponent(0.72)
                    )
                        .frame(width: 92)
                        .help("Adjust all Studio panel transparency.")

                    if let liveModeSelection {
                        Divider()
                            .frame(height: 20)

                        Picker("", selection: liveModeSelection) {
                            Text("Edit").tag(0)
                            Text("Live").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 156)
                    }
                }

                Spacer(minLength: 0)

                bottomActionSection
            }
        }
        .frame(height: 32)
    }

    private var controlsRow: some View {
        HStack(spacing: 12) {
            volumeSection
                .frame(maxWidth: .infinity, alignment: .leading)

            transportSection
                .frame(maxWidth: .infinity, alignment: .center)

            actionSection
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var volumeSection: some View {
        HStack(spacing: 5) {
            Button(action: toggleMute) {
                Image(systemName: volume <= 0.001 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(chromeOpacity))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(volume <= 0.001 ? "Unmute" : "Mute")

            PanelSliderView(value: $volume, bounds: 0...1)
                .frame(width: 96)
                .help("Volume")

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(chromeOpacity))
                .frame(width: 14)
        }
    }

    private var transportSection: some View {
        HStack(spacing: 10) {
            deckButton(
                id: "prev",
                systemName: "backward.fill",
                tooltip: "Previous Composition",
                size: .small,
                action: onPrevious
            )
            playPauseButton()
            deckButton(
                id: "next",
                systemName: "forward.fill",
                tooltip: "Next Composition",
                size: .small,
                action: onNext
            )

            Divider()
                .frame(height: 30)

            deckButton(
                id: "loop",
                label: { loopButtonLabel },
                tooltip: loopTooltip,
                tint: .white,
                activeBackground: (isLoopCompositionEnabled || isLoopSequenceEnabled) ? .blue : nil,
                size: .small,
                action: onCyclePlaybackLoopMode
            )
        }
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            topDockIconButton(
                systemName: "arrow.left.and.right.circle",
                tooltip: "Show Full Clips (F)",
                isActive: isShowingFullClips,
                action: onToggleShowFullClips
            )

            topDockIconButton(
                systemName: "sparkles",
                tooltip: "Generate at End",
                isActive: isGenerateAtEndEnabled,
                action: onToggleGenerateAtEnd
            )

            addLayerMenuButton(size: .large)
        }
    }

    private func playPauseButton() -> some View {
        let tooltip = isPaused ? "Play (SPACE)" : "Pause (SPACE)"

        return Button(action: onPlayPause) {
            Image(systemName: playPauseSystemName)
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(
                    isPaused
                    ? Color.white.opacity(0.78 + (0.18 * chromeOpacity))
                    : Color.blue.opacity(0.92)
                )
                .padding(4)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func toggleMute() {
        if volume <= 0.001 {
            let restored = max(previousVolumeBeforeMute, 0.05)
            volume = min(restored, 1.0)
            return
        }
        previousVolumeBeforeMute = volume
        volume = 0
    }

    private func formatTime(_ seconds: Double) -> String {
        let clampedSeconds = max(0, seconds)
        if clampedSeconds >= 60 {
            let minutes = Int(clampedSeconds) / 60
            let remainder = clampedSeconds.truncatingRemainder(dividingBy: 60)
            return String(format: "%d:%04.1f", minutes, remainder)
        }
        return String(format: "%.1fs", clampedSeconds)
    }

    private var playPauseSystemName: String {
        isPaused ? "play.fill" : "pause.fill"
    }

    private var loopTooltip: String {
        if isLoopCompositionEnabled {
            return "Loop Composition (L)"
        }
        if isLoopSequenceEnabled {
            return "Loop Sequence (SHIFT+L)"
        }
        return "Loop Off"
    }

    private var loopButtonLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 21, height: 21)
                .foregroundStyle(
                    (isLoopCompositionEnabled || isLoopSequenceEnabled)
                    ? Color.blue.opacity(0.92)
                    : Color.white.opacity(0.78 + (0.18 * chromeOpacity))
                )

            if isLoopCompositionEnabled {
                Text("1")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.blue.opacity(0.92))
                    .offset(x: 5, y: -3)
            }
        }
    }

    @ViewBuilder
    private func panelToggleButton(_ item: StudioPanelToolbarItem, showLabel: Bool) -> some View {
        let descriptor = item.descriptor
        let isVisible = isPanelVisible(descriptor.panelID)

        Button {
            onTogglePanel(descriptor.panelID)
        } label: {
            Group {
                if showLabel {
                    Label(descriptor.title, systemImage: descriptor.systemImage)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                } else {
                    Image(systemName: descriptor.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
            }
            .modifier(
                DockControlChrome(
                    chromeOpacity: chromeOpacity,
                    size: .small,
                    isActive: isVisible,
                    horizontalPadding: showLabel ? 10 : nil,
                    verticalPadding: 5
                )
            )
        }
        .buttonStyle(.plain)
        .help("\(descriptor.title) (\(descriptor.shortcutLabel))")
    }

    private func deckButton<Label: View>(
        id: String,
        @ViewBuilder label: () -> Label,
        tooltip: String,
        tint: Color = .white,
        activeBackground: Color? = nil,
        size: DockControlSize = .small,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(
                    activeBackground != nil
                    ? tint.opacity(0.96)
                    : Color.white.opacity(0.78 + (0.18 * chromeOpacity))
                )
                .padding(size == .large ? 5 : 4)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func deckButton(
        id: String,
        systemName: String,
        tooltip: String,
        tint: Color = .white,
        activeBackground: Color? = nil,
        size: DockControlSize = .small,
        action: @escaping () -> Void
    ) -> some View {
        deckButton(
            id: id,
            label: {
                Image(systemName: systemName)
                    .font(.system(size: size == .large ? 22 : 18, weight: .semibold))
                    .frame(width: size == .large ? 26 : 21, height: size == .large ? 26 : 21)
            },
            tooltip: tooltip,
            tint: tint,
            activeBackground: activeBackground,
            size: size,
            action: action
        )
    }

    private var bottomActionSection: some View {
        HStack(spacing: 8) {
            if renderQueueCount > 0 {
                Text("Queue: \(renderQueueCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58 + (0.16 * chromeOpacity)))
                    .padding(.trailing, 2)
            }

            smallDockIconButton(
                systemName: "camera.fill",
                tooltip: "Save Snapshot (S)",
                action: onSnapshotCurrent
            )
            smallDockActionButton(
                tooltip: "Save & Render Current",
                action: onRenderCurrent
            ) {
                exportButtonLabel(badgedCurrent: true)
            }
            smallDockActionButton(
                tooltip: "Save & Render Sequence",
                action: onRenderSequence
            ) {
                exportButtonLabel(badgedCurrent: false)
            }
        }
    }

    private func topDockIconButton(
        systemName: String,
        tooltip: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 21, height: 21)
                .foregroundStyle(
                    isActive
                    ? Color.blue.opacity(0.92)
                    : Color.white.opacity(0.78 + (0.18 * chromeOpacity))
                )
                .padding(4)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func smallDockIconButton(
        systemName: String,
        tooltip: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 16, height: 16)
                .modifier(
                    DockControlChrome(
                        chromeOpacity: chromeOpacity,
                        size: .small,
                        isActive: isActive
                    )
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func smallDockActionButton<Label: View>(
        tooltip: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .modifier(
                    DockControlChrome(
                        chromeOpacity: chromeOpacity,
                        size: .small,
                        isActive: false
                    )
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func addLayerMenuButton(size: DockControlSize) -> some View {
        Menu {
            Button {
                onAddSourceFromFiles()
            } label: {
                Label("From Files...", systemImage: "doc")
            }

            Button {
                onAddSourceFromPhotos()
            } label: {
                Label("From Photos...", systemImage: "photo")
            }

            Button {
                onAddSourceFromRandom()
            } label: {
                Label("Random Source", systemImage: "dice")
            }
        } label: {
            Group {
                if size == .large {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 21, height: 21)
                        .foregroundStyle(Color.white.opacity(0.78 + (0.18 * chromeOpacity)))
                        .padding(4)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .modifier(
                            DockControlChrome(
                                chromeOpacity: chromeOpacity,
                                size: size,
                                isActive: false
                            )
                        )
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Add Layer")
    }

    private func exportButtonLabel(badgedCurrent: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 16, height: 16)

            if badgedCurrent {
                Text("1")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 5, y: -4)
            }
        }
    }

    private func shouldShowPanelLabels(availableWidth: CGFloat) -> Bool {
        let threshold: CGFloat = liveModeSelection == nil ? 980 : 1140
        return availableWidth >= threshold
    }
}

private enum DockControlSize {
    case small
    case large
}

private struct DockControlChrome: ViewModifier {
    let chromeOpacity: Double
    let size: DockControlSize
    let isActive: Bool
    var activeTint: Color = .white
    var activeFill: Color = .accentColor
    var activeStroke: Color = .accentColor
    var horizontalPadding: CGFloat? = nil
    var verticalPadding: CGFloat? = nil

    private var resolvedHorizontalPadding: CGFloat {
        if let horizontalPadding { return horizontalPadding }
        switch size {
        case .small: return 8
        case .large: return 9
        }
    }

    private var resolvedVerticalPadding: CGFloat {
        if let verticalPadding { return verticalPadding }
        switch size {
        case .small: return 5
        case .large: return 7
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .small: return 8
        case .large: return 8
        }
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, resolvedHorizontalPadding)
            .padding(.vertical, resolvedVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var foregroundColor: Color {
        if isActive {
            return activeTint
        }
        return Color.white.opacity(0.78 + (0.18 * chromeOpacity))
    }

    private var backgroundColor: Color {
        if isActive {
            return activeFill.opacity(0.84 + (0.12 * chromeOpacity))
        }
        return Color.white.opacity(0.05 + (0.04 * chromeOpacity))
    }

    private var borderColor: Color {
        if isActive {
            return activeStroke.opacity(0.90 + (0.10 * chromeOpacity))
        }
        return Color.white.opacity(0.12 + (0.10 * chromeOpacity))
    }
}
