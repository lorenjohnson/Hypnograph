import SwiftUI

struct PlayerControlsBar: View {
    let isPaused: Bool
    let isLoopCurrentClipEnabled: Bool
    let currentClipText: String
    let clipLengthSeconds: Double
    let clipTrimContexts: [ClipTrimContext]
    @Binding var previewVolume: Double
    let timelinePlaybackRate: Double
    @Binding var timelinePlaybackControlValue: Double
    @Binding var isTimelinePlaybackReverse: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onToggleLoopCurrentClipMode: () -> Void
    let onSnapshotCurrent: () -> Void
    let onSaveCurrent: () -> Void
    let onRenderCurrent: () -> Void
    let onCommitClipTrimRange: (Int, ClosedRange<Double>) -> Void

    @State private var pendingTooltipWorkItem: DispatchWorkItem?
    @State private var visibleTooltipControlID: String?
    @State private var visibleTooltipText: String?
    @State private var previousPreviewVolumeBeforeMute: Double = 0.8
    @State private var showTimelineSpeedPopover: Bool = false

    private let tooltipDelay: TimeInterval = 0.85

    var body: some View {
        VStack(spacing: 8) {
            ClipTrimPanelView(
                contexts: clipTrimContexts,
                onCommit: onCommitClipTrimRange
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
        .onChange(of: previewVolume) { _, newValue in
            if newValue > 0.001 {
                previousPreviewVolumeBeforeMute = newValue
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
            deckButton(id: "prev", systemName: "backward.fill", tooltip: "Previous Clip", action: onPrevious)
            playPauseButton()
            deckButton(id: "next", systemName: "forward.fill", tooltip: "Next Clip", action: onNext)

            Divider()
                .frame(height: 30)

            deckButton(
                id: "loop",
                systemName: "arrow.counterclockwise",
                tooltip: isLoopCurrentClipEnabled ? "Loop Current Clip (L)" : "Auto-Advance Clips (L)",
                tint: .white,
                activeBackground: isLoopCurrentClipEnabled ? .blue : nil,
                action: onToggleLoopCurrentClipMode
            )

            Text("\(currentClipText.uppercased()) (\(formattedClipLength))")
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.trailing, 2)

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Button(action: togglePreviewMute) {
                    Image(systemName: previewVolume <= 0.001 ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(previewVolume <= 0.001 ? "Unmute Preview" : "Mute Preview")
                Slider(value: $previewVolume, in: 0...1)
                    .frame(width: 120)
                    .help("Preview Volume")
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
        let tooltip = isPaused
            ? (isTimelineReverse ? "Play Reverse (SPACE)" : "Play (SPACE)")
            : "Pause (SPACE)"

        return Button(action: onPlayPause) {
            Image(systemName: playPauseSystemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .buttonStyle(DeckBarButtonStyle(activeBackground: playButtonBackgroundColor))
        .help(tooltip)
        .hudTooltip(tooltip)
        .onHover { isHovering in
            handleTooltipHover(isHovering: isHovering, controlID: "play_pause", tooltip: tooltip)
        }
        .overlay(alignment: .bottomTrailing) {
            if isTimelineSpeedActive {
                timelineSpeedBadge
                    .offset(x: 8, y: -8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            timelineSpeedButton()
                .offset(x: 6, y: 6)
        }
        .overlay(alignment: .top) {
            if visibleTooltipControlID == "play_pause", let visibleTooltipText {
                tooltipBubble(text: visibleTooltipText)
                    .offset(y: -44)
                    .transition(.opacity)
            }
        }
    }

    private func timelineSpeedButton() -> some View {
        let tooltip = "Timeline Speed (\(formattedTimelinePlaybackRate))"
        return Button {
            showTimelineSpeedPopover.toggle()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 12, height: 12)
                .background(
                    Circle()
                        .fill(timelineAccentColor.opacity(isTimelineSpeedActive ? 0.95 : 0.78))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .hudTooltip(tooltip)
        .onHover { isHovering in
            handleTooltipHover(isHovering: isHovering, controlID: "timeline_speed", tooltip: tooltip)
        }
        .popover(
            isPresented: $showTimelineSpeedPopover,
            attachmentAnchor: .point(.bottom),
            arrowEdge: .top
        ) {
            timelineSpeedPopover
        }
        .overlay(alignment: .top) {
            if visibleTooltipControlID == "timeline_speed", let visibleTooltipText {
                tooltipBubble(text: visibleTooltipText)
                    .offset(y: -44)
                    .transition(.opacity)
            }
        }
    }

    private var timelineSpeedPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History Playback Speed")
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.semibold)

            HStack(spacing: 10) {
                Text("1x")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { timelinePlaybackControlValue },
                        set: { timelinePlaybackControlValue = $0 }
                    ),
                    in: 0...20
                )
                Text("20x")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Current: \(formattedTimelinePlaybackRate)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button("Reset 1x") {
                    timelinePlaybackControlValue = 0
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Toggle("Reverse", isOn: $isTimelinePlaybackReverse)
                .toggleStyle(.checkbox)
                .font(.system(.caption, design: .monospaced))
        }
        .padding(12)
        .frame(width: 300)
    }

    private func togglePreviewMute() {
        if previewVolume <= 0.001 {
            let restored = max(previousPreviewVolumeBeforeMute, 0.05)
            previewVolume = min(restored, 1.0)
            return
        }
        previousPreviewVolumeBeforeMute = previewVolume
        previewVolume = 0
    }

    private var formattedClipLength: String {
        let seconds = max(0.1, clipLengthSeconds)
        let rounded = (seconds * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "\(Int(rounded.rounded()))s"
        }
        return String(format: "%.1fs", rounded)
    }

    private var isTimelineSpeedActive: Bool {
        abs(normalizedTimelinePlaybackRate - 1.0) > 0.0001 || isTimelineReverse
    }

    private var isTimelineReverse: Bool {
        normalizedTimelinePlaybackRate < 0
    }

    private var playPauseSystemName: String {
        if isPaused {
            return isTimelineReverse ? "backward.fill" : "play.fill"
        }
        if isTimelineReverse {
            return "backward.fill"
        }
        if isTimelineSpeedActive {
            return "forward.fill"
        }
        return "pause.fill"
    }

    private var timelineAccentColor: Color {
        isTimelineReverse ? .red : .green
    }

    private var playButtonBackgroundColor: Color? {
        isTimelineSpeedActive ? timelineAccentColor.opacity(0.58) : nil
    }

    private var timelineSpeedBadge: some View {
        Text(formattedTimelinePlaybackRateCompact)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(timelineAccentColor.opacity(0.95))
            )
    }

    private var normalizedTimelinePlaybackRate: Double {
        let direction = timelinePlaybackRate < 0 ? -1.0 : 1.0
        let magnitude = min(max(abs(timelinePlaybackRate), 1.0), 20.0)
        return direction * magnitude
    }

    private var formattedTimelinePlaybackRate: String {
        formatTimelineRate(normalizedTimelinePlaybackRate, compact: false)
    }

    private var formattedTimelinePlaybackRateCompact: String {
        formatTimelineRate(normalizedTimelinePlaybackRate, compact: true)
    }

    private func formatTimelineRate(_ value: Double, compact: Bool) -> String {
        let direction = value < 0 ? -1.0 : 1.0
        let magnitude = min(max(abs(value), 1.0), 20.0)
        if abs(magnitude - 1.0) < 0.0001 {
            return compact ? "1x" : "1.0x"
        }

        let precision: String
        if magnitude >= 10 || abs(magnitude - magnitude.rounded()) < 0.0001 {
            precision = "%.0f"
        } else {
            precision = "%.1f"
        }

        let magnitudeString = String(format: precision, magnitude)
        let signPrefix = direction < 0 ? "-" : ""
        return "\(signPrefix)\(magnitudeString)x"
    }

    private func deckButton(
        id: String,
        systemName: String,
        tooltip: String,
        tint: Color = .white,
        activeBackground: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
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
