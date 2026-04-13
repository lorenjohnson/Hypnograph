import SwiftUI
import HypnoCore

struct PlayerControlsPanel: View {
    let isPaused: Bool
    let isLoopCompositionEnabled: Bool
    let isLoopSequenceEnabled: Bool
    let selectedLayerIndex: Int
    let compositionLengthSeconds: Double
    let currentCompositionTimeSeconds: Double?
    let isShowingFullClips: Bool
    let sequenceEntries: [CompositionEntry]
    let layerTrimContexts: [LayerTrimContext]
    let visualOpacity: Double
    @Binding var volume: Double
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
    let onCyclePlaybackLoopMode: () -> Void
    let onSnapshotCurrent: () -> Void
    let onSaveCurrent: () -> Void
    let onRenderCurrent: () -> Void
    let onRenderSequence: () -> Void
    let onCommitLayerTrimRange: (Int, ClosedRange<Double>) -> Void

    @State private var pendingTooltipWorkItem: DispatchWorkItem?
    @State private var visibleTooltipControlID: String?
    @State private var visibleTooltipText: String?
    @State private var previousVolumeBeforeMute: Double = 0.8
    @State private var draggedCompositionID: UUID?

    private let tooltipDelay: TimeInterval = 0.85

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
            dockHeader

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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Sequence")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.secondary.opacity(chromeOpacity))

                    Spacer(minLength: 0)

                    Text("\(formatTime(totalSequenceDurationSeconds)) / \(formatTime(compositionLengthSeconds))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(chromeOpacity))
                }

                SequenceLaneView(
                    compositionEntries: sequenceEntries,
                    draggedCompositionID: $draggedCompositionID,
                    onJumpToComposition: onJumpToComposition,
                    onDeleteCompositionEntry: onDeleteCompositionEntry,
                    onMoveComposition: onMoveComposition
                )
                .padding(.horizontal, 2)
            }

            controlsRow
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
        .onDisappear {
            pendingTooltipWorkItem?.cancel()
            pendingTooltipWorkItem = nil
            visibleTooltipControlID = nil
            visibleTooltipText = nil
        }
    }

    private var dockHeader: some View {
        HStack(spacing: 8) {
            Text("Composition")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.secondary.opacity(chromeOpacity))

            Spacer(minLength: 0)

            Button(action: onToggleShowFullClips) {
                Image(systemName: "arrow.left.and.right.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(
                        isShowingFullClips
                        ? Color.accentColor
                        : Color.white.opacity(0.72 + (0.2 * chromeOpacity))
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                isShowingFullClips
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear
                            )
                    )
            }
            .buttonStyle(.plain)
            .help("Show Full Clips (F)")

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
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.72 + (0.2 * chromeOpacity)))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("Add Layer")
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 16) {
            volumeSection
                .frame(maxWidth: .infinity, alignment: .leading)

            transportSection
                .frame(maxWidth: .infinity, alignment: .center)

            actionSection
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var volumeSection: some View {
        HStack(spacing: 6) {
            Button(action: toggleMute) {
                Image(systemName: volume <= 0.001 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(chromeOpacity))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(volume <= 0.001 ? "Unmute" : "Mute")

            PanelSliderView(value: $volume, bounds: 0...1)
                .frame(width: 120)
                .help("Volume")

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(chromeOpacity))
                .frame(width: 16)
        }
    }

    private var transportSection: some View {
        HStack(spacing: 14) {
            deckButton(id: "prev", systemName: "backward.fill", tooltip: "Previous Composition", action: onPrevious)
            playPauseButton()
            deckButton(id: "next", systemName: "forward.fill", tooltip: "Next Composition", action: onNext)

            Divider()
                .frame(height: 30)

            deckButton(
                id: "loop",
                label: { loopButtonLabel },
                tooltip: loopTooltip,
                tint: .white,
                activeBackground: (isLoopCompositionEnabled || isLoopSequenceEnabled) ? .blue : nil,
                action: onCyclePlaybackLoopMode
            )
        }
    }

    private var actionSection: some View {
        HStack(spacing: 14) {
            deckButton(
                id: "snapshot",
                systemName: "camera.fill",
                tooltip: "Save Snapshot (S)",
                action: onSnapshotCurrent
            )
            deckButton(
                id: "save",
                systemName: "square.and.arrow.down",
                tooltip: "Save Current (CMD+S)",
                action: onSaveCurrent
            )
            deckButton(
                id: "render",
                systemName: "film",
                tooltip: "Save & Render Current (CMD+OPT+S)",
                action: onRenderCurrent
            )
            deckButton(
                id: "render-sequence",
                systemName: "film.stack",
                tooltip: "Save & Render Sequence (CTRL+CMD+SHIFT+S)",
                action: onRenderSequence
            )
        }
    }

    private func playPauseButton() -> some View {
        let tooltip = isPaused ? "Play (SPACE)" : "Pause (SPACE)"

        return Button(action: onPlayPause) {
            Image(systemName: playPauseSystemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.68 + (0.32 * chromeOpacity)))
                .frame(width: 28, height: 28)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .buttonStyle(DeckBarButtonStyle(chromeOpacity: chromeOpacity))
        .help(tooltip)
        .hudTooltip(tooltip)
        .onHover { isHovering in
            handleTooltipHover(isHovering: isHovering, controlID: "play_pause", tooltip: tooltip)
        }
        .overlay(alignment: .top) {
            if visibleTooltipControlID == "play_pause", let visibleTooltipText {
                tooltipBubble(text: visibleTooltipText)
                    .offset(y: -44)
                    .transition(.opacity)
            }
        }
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
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)

            if isLoopCompositionEnabled {
                Text("1")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.65))
                    )
                    .offset(x: 6, y: -4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func deckButton<Label: View>(
        id: String,
        @ViewBuilder label: () -> Label,
        tooltip: String,
        tint: Color = .white,
        activeBackground: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(tint.opacity(0.68 + (0.32 * chromeOpacity)))
        }
        .buttonStyle(DeckBarButtonStyle(activeBackground: activeBackground, chromeOpacity: chromeOpacity))
        .help(tooltip)
        .hudTooltip(tooltip)
        .onHover { isHovering in
            handleTooltipHover(isHovering: isHovering, controlID: id, tooltip: tooltip)
        }
        .overlay(alignment: .top) {
            if visibleTooltipControlID == id, let visibleTooltipText {
                tooltipBubble(text: visibleTooltipText)
                    .offset(y: -44)
                    .transition(.opacity)
            }
        }
    }

    private func deckButton(
        id: String,
        systemName: String,
        tooltip: String,
        tint: Color = .white,
        activeBackground: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        deckButton(
            id: id,
            label: {
                Image(systemName: systemName)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            },
            tooltip: tooltip,
            tint: tint,
            activeBackground: activeBackground,
            action: action
        )
    }

    private func handleTooltipHover(isHovering: Bool, controlID: String, tooltip: String) {
        pendingTooltipWorkItem?.cancel()
        pendingTooltipWorkItem = nil

        if isHovering {
            if visibleTooltipControlID != controlID {
                visibleTooltipControlID = nil
                visibleTooltipText = nil
            }
            let workItem = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.12)) {
                    visibleTooltipControlID = controlID
                    visibleTooltipText = tooltip
                }
            }
            pendingTooltipWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + tooltipDelay, execute: workItem)
            return
        }

        if visibleTooltipControlID == controlID {
            withAnimation(.easeInOut(duration: 0.08)) {
                visibleTooltipControlID = nil
                visibleTooltipText = nil
            }
        }
    }

    private func tooltipBubble(text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .fixedSize(horizontal: true, vertical: true)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.76))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
            )
    }
}

private struct DeckBarButtonStyle: ButtonStyle {
    var activeBackground: Color?
    var chromeOpacity: Double = 1.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if let activeBackground {
            return isPressed ? activeBackground.opacity(0.46 + (0.36 * chromeOpacity)) : activeBackground.opacity(0.62 + (0.38 * chromeOpacity))
        }
        return isPressed ? Color.white.opacity(0.10 + (0.14 * chromeOpacity)) : Color.white.opacity(0.04 + (0.06 * chromeOpacity))
    }
}
