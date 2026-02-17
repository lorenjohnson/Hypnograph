import SwiftUI

struct PlayerControlsBar: View {
    struct ClipTrimContext: Equatable {
        let layerLabel: String
        let clipLabel: String
        let totalDurationSeconds: Double
        let maxSelectionDurationSeconds: Double
        let selectedRangeSeconds: ClosedRange<Double>
    }

    let isPaused: Bool
    let isLoopCurrentClipEnabled: Bool
    let currentClipText: String
    let clipTrimContext: ClipTrimContext?
    @Binding var previewVolume: Double
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onToggleLoopCurrentClipMode: () -> Void
    let onSaveCurrent: () -> Void
    let onRenderCurrent: () -> Void
    let onCommitClipTrimRange: (ClosedRange<Double>) -> Void

    @State private var pendingTooltipWorkItem: DispatchWorkItem?
    @State private var visibleTooltipControlID: String?
    @State private var visibleTooltipText: String?
    @State private var previousPreviewVolumeBeforeMute: Double = 0.8

    private let tooltipDelay: TimeInterval = 0.85

    var body: some View {
        VStack(spacing: 8) {
            if let clipTrimContext {
                ClipTrimRangeStrip(
                    context: clipTrimContext,
                    onCommit: onCommitClipTrimRange
                )

                Divider()
                    .background(Color.white.opacity(0.16))
            }

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
            deckButton(id: "play_pause", systemName: isPaused ? "play.fill" : "pause.fill", tooltip: isPaused ? "Play" : "Pause", action: onPlayPause)
            deckButton(id: "next", systemName: "forward.fill", tooltip: "Next Clip", action: onNext)

            Divider()
                .frame(height: 30)

            deckButton(
                id: "loop",
                systemName: "arrow.counterclockwise",
                tooltip: isLoopCurrentClipEnabled ? "Loop Current Clip" : "Auto-Advance Clips",
                tint: .white,
                activeBackground: isLoopCurrentClipEnabled ? .blue : nil,
                action: onToggleLoopCurrentClipMode
            )

            Text(currentClipText.uppercased())
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

            deckButton(id: "save", systemName: "square.and.arrow.down", tooltip: "Save Current", action: onSaveCurrent)
            deckButton(id: "render", systemName: "film.stack", tooltip: "Render Current", action: onRenderCurrent)
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

private struct ClipTrimRangeStrip: View {
    enum DragMode {
        case leadingHandle
        case trailingHandle
        case window
    }

    let context: PlayerControlsBar.ClipTrimContext
    let onCommit: (ClosedRange<Double>) -> Void

    @State private var draftRange: ClosedRange<Double>
    @State private var dragStartRange: ClosedRange<Double>?
    @State private var dragMode: DragMode?

    private let trackHeight: CGFloat = 38
    private let handleWidth: CGFloat = 10
    private let handleHitWidth: CGFloat = 28
    private let minimumDurationSeconds: Double = 0.1

    init(
        context: PlayerControlsBar.ClipTrimContext,
        onCommit: @escaping (ClosedRange<Double>) -> Void
    ) {
        self.context = context
        self.onCommit = onCommit
        _draftRange = State(initialValue: context.selectedRangeSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(context.layerLabel) Trim")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(context.clipLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 10)

                Text("\(formatTime(activeRange.lowerBound)) – \(formatTime(activeRange.upperBound))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let trackWidth = max(1, geometry.size.width)
                let startX = xPosition(forSeconds: activeRange.lowerBound, trackWidth: trackWidth)
                let endX = xPosition(forSeconds: activeRange.upperBound, trackWidth: trackWidth)
                let selectedWidth = max(4, endX - startX)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: trackHeight)

                    tickMarks(trackWidth: trackWidth)

                    Rectangle()
                        .fill(Color.black.opacity(0.30))
                        .frame(width: max(0, startX), height: trackHeight)

                    Rectangle()
                        .fill(Color.black.opacity(0.30))
                        .frame(width: max(0, trackWidth - endX), height: trackHeight)
                        .offset(x: endX)

                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: selectedWidth, height: trackHeight)
                        .offset(x: startX)

                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.44), lineWidth: 1.1)
                        .frame(width: selectedWidth, height: trackHeight)
                        .offset(x: startX)

                    trimHandle
                        .offset(x: startX - (handleWidth * 0.5), y: 1)

                    trimHandle
                        .offset(x: endX - (handleWidth * 0.5), y: 1)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(trackWidth: trackWidth))
            }
            .frame(height: trackHeight)

            HStack {
                Text("0s")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Text("Window: \(formatTime(activeRange.upperBound - activeRange.lowerBound)) / Max \(formatTime(maxWindowSeconds))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Text(formatTime(safeTotalSeconds))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .onChange(of: context) { _, newValue in
            guard dragStartRange == nil else { return }
            draftRange = normalized(newValue.selectedRangeSeconds)
        }
        .onDisappear {
            dragStartRange = nil
            dragMode = nil
        }
    }

    private var safeTotalSeconds: Double {
        max(0.1, context.totalDurationSeconds)
    }

    private var activeRange: ClosedRange<Double> {
        normalized(draftRange)
    }

    private var minimumWindowSeconds: Double {
        min(minimumDurationSeconds, safeTotalSeconds)
    }

    private var maxWindowSeconds: Double {
        max(minimumWindowSeconds, min(context.maxSelectionDurationSeconds, safeTotalSeconds))
    }

    private func normalized(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        let total = safeTotalSeconds
        let minWindow = minimumWindowSeconds
        let maxWindow = maxWindowSeconds

        var lower = max(0, min(range.lowerBound, total))
        var upper = max(0, min(range.upperBound, total))

        if upper < lower {
            swap(&lower, &upper)
        }

        if (upper - lower) < minWindow {
            if lower + minWindow <= total {
                upper = lower + minWindow
            } else {
                upper = total
                lower = max(0, upper - minWindow)
            }
        }

        if (upper - lower) > maxWindow {
            upper = lower + maxWindow
            if upper > total {
                upper = total
                lower = max(0, upper - maxWindow)
            }
        }

        return lower...upper
    }

    private func xPosition(forSeconds seconds: Double, trackWidth: CGFloat) -> CGFloat {
        guard safeTotalSeconds > 0 else { return 0 }
        let fraction = max(0, min(seconds / safeTotalSeconds, 1))
        return CGFloat(fraction) * trackWidth
    }

    private func secondsDelta(forTranslationX translationX: CGFloat, trackWidth: CGFloat) -> Double {
        guard trackWidth > 0 else { return 0 }
        return Double(translationX / trackWidth) * safeTotalSeconds
    }

    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if value.translation == .zero {
                    dragStartRange = activeRange

                    let startX = xPosition(forSeconds: activeRange.lowerBound, trackWidth: trackWidth)
                    let endX = xPosition(forSeconds: activeRange.upperBound, trackWidth: trackWidth)
                    let leftDistance = abs(value.startLocation.x - startX)
                    let rightDistance = abs(value.startLocation.x - endX)

                    if leftDistance <= handleHitWidth * 0.5 {
                        dragMode = .leadingHandle
                    } else if rightDistance <= handleHitWidth * 0.5 {
                        dragMode = .trailingHandle
                    } else if value.startLocation.x >= startX, value.startLocation.x <= endX {
                        dragMode = .window
                    } else {
                        dragMode = leftDistance < rightDistance ? .leadingHandle : .trailingHandle
                    }
                }

                guard let mode = dragMode, let origin = dragStartRange else { return }

                let delta = secondsDelta(forTranslationX: value.translation.width, trackWidth: trackWidth)
                let minWindow = minimumWindowSeconds
                let maxWindow = maxWindowSeconds
                let total = safeTotalSeconds

                switch mode {
                case .leadingHandle:
                    let minLower = origin.upperBound - maxWindow
                    let maxLower = origin.upperBound - minWindow
                    let newLower = max(minLower, min(origin.lowerBound + delta, maxLower))
                    draftRange = newLower...origin.upperBound

                case .trailingHandle:
                    let minUpper = origin.lowerBound + minWindow
                    let maxUpper = min(total, origin.lowerBound + maxWindow)
                    let newUpper = max(minUpper, min(origin.upperBound + delta, maxUpper))
                    draftRange = origin.lowerBound...newUpper

                case .window:
                    let windowWidth = origin.upperBound - origin.lowerBound
                    let proposedLower = origin.lowerBound + delta
                    let clampedLower = max(0, min(proposedLower, total - windowWidth))
                    draftRange = clampedLower...(clampedLower + windowWidth)
                }

                draftRange = normalized(draftRange)
            }
            .onEnded { _ in
                let committed = normalized(draftRange)
                draftRange = committed
                onCommit(committed)
                dragStartRange = nil
                dragMode = nil
            }
    }

    @ViewBuilder
    private func tickMarks(trackWidth: CGFloat) -> some View {
        let maxTicks = 10
        let candidateCount = Int(safeTotalSeconds.rounded(.down))
        let divisions = max(2, min(maxTicks, max(2, candidateCount)))

        ForEach(0...divisions, id: \.self) { index in
            let fraction = CGFloat(Double(index) / Double(divisions))
            Rectangle()
                .fill(Color.white.opacity(index == 0 || index == divisions ? 0.35 : 0.18))
                .frame(width: 1, height: index == 0 || index == divisions ? 14 : 9)
                .offset(x: max(0, min(trackWidth * fraction - 0.5, trackWidth - 1)), y: 10)
        }
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

    private var trimHandle: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.88, green: 0.90, blue: 0.96).opacity(0.88),
                        Color(red: 0.74, green: 0.78, blue: 0.88).opacity(0.86)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
            )
            .overlay {
                VStack(spacing: 3) {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.36))
                        .frame(width: 5, height: 1)
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.32))
                        .frame(width: 5, height: 1)
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .frame(width: 5, height: 1)
                }
            }
            .frame(width: handleWidth, height: trackHeight - 2)
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
