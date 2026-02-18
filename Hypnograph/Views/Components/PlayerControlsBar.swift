import SwiftUI

struct PlayerControlsBar: View {
    let isPaused: Bool
    let isLoopCurrentClipEnabled: Bool
    let currentClipText: String
    let clipLengthSeconds: Double
    let clipTrimContexts: [ClipTrimContext]
    @Binding var previewVolume: Double
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
            deckButton(
                id: "play_pause",
                systemName: isPaused ? "play.fill" : "pause.fill",
                tooltip: isPaused ? "Play (SPACE)" : "Pause (SPACE)",
                action: onPlayPause
            )
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
