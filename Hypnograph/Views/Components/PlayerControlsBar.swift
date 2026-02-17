import SwiftUI

struct PlayerControlsBar: View {
    let isPaused: Bool
    let isWatchModeEnabled: Bool
    let currentClipText: String
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onToggleWatchMode: () -> Void
    let onSaveCurrent: () -> Void
    let onRenderCurrent: () -> Void

    @State private var pendingTooltipWorkItem: DispatchWorkItem?
    @State private var visibleTooltipControlID: String?
    @State private var visibleTooltipText: String?

    private let tooltipDelay: TimeInterval = 0.85

    var body: some View {
        HStack(spacing: 14) {
            deckButton(id: "prev", systemName: "backward.fill", tooltip: "Previous Clip", action: onPrevious)
            deckButton(id: "play_pause", systemName: isPaused ? "play.fill" : "pause.fill", tooltip: isPaused ? "Play" : "Pause", action: onPlayPause)
            deckButton(
                id: "watch",
                systemName: "arrow.counterclockwise",
                tooltip: isWatchModeEnabled ? "Continuous Playback" : "Loop Current Clip",
                tint: .white,
                activeBackground: isWatchModeEnabled ? nil : .blue,
                action: onToggleWatchMode
            )
            deckButton(id: "next", systemName: "forward.fill", tooltip: "Next Clip", action: onNext)

            Divider()
                .frame(height: 30)

            Text(currentClipText.uppercased())
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.trailing, 2)

            Spacer(minLength: 6)

            deckButton(id: "save", systemName: "square.and.arrow.down", tooltip: "Save Current", action: onSaveCurrent)
            deckButton(id: "render", systemName: "film.stack", tooltip: "Render Current", action: onRenderCurrent)
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
        .onDisappear {
            pendingTooltipWorkItem?.cancel()
            pendingTooltipWorkItem = nil
            visibleTooltipControlID = nil
            visibleTooltipText = nil
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
