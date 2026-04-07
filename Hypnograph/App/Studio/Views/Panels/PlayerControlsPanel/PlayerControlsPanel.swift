import SwiftUI

struct PlayerControlsPanel: View {
    let isPaused: Bool
    let isLoopCompositionEnabled: Bool
    let isLoopSequenceEnabled: Bool
    let compositionLengthSeconds: Double
    let layerTrimContexts: [LayerTrimContext]
    @Binding var volume: Double
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onCyclePlaybackLoopMode: () -> Void
    let onSnapshotCurrent: () -> Void
    let onSaveCurrent: () -> Void
    let onRenderCurrent: () -> Void
    let onCommitLayerTrimRange: (Int, ClosedRange<Double>) -> Void

    @State private var pendingTooltipWorkItem: DispatchWorkItem?
    @State private var visibleTooltipControlID: String?
    @State private var visibleTooltipText: String?
    @State private var previousVolumeBeforeMute: Double = 0.8

    private let tooltipDelay: TimeInterval = 0.85

    var body: some View {
        VStack(spacing: 8) {
            LayerTrimView(
                contexts: layerTrimContexts,
                onCommit: onCommitLayerTrimRange
            )

            controlsRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
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

    private var controlsRow: some View {
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

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Button(action: toggleMute) {
                    Image(systemName: volume <= 0.001 ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }

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
                systemName: "film.stack",
                tooltip: "Save & Render Current (CMD+OPT+S)",
                action: onRenderCurrent
            )
        }
    }

    private func playPauseButton() -> some View {
        let tooltip = isPaused ? "Play (SPACE)" : "Pause (SPACE)"

        return Button(action: onPlayPause) {
            Image(systemName: playPauseSystemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .buttonStyle(DeckBarButtonStyle())
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
                .foregroundStyle(tint)
        }
        .buttonStyle(DeckBarButtonStyle(activeBackground: activeBackground))
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
            return isPressed ? activeBackground.opacity(0.82) : activeBackground
        }
        return isPressed ? Color.white.opacity(0.24) : Color.white.opacity(0.1)
    }
}
