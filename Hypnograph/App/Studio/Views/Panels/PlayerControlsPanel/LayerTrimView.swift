import SwiftUI
import AVFoundation
import AppKit
import HypnoCore

struct LayerTrimContext: Equatable {
    let layerIndex: Int
    let fileID: UUID
    let source: MediaSource
    let mediaKind: MediaKind
    let clipLabel: String
    let blendMode: String
    let opacity: Double
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let isMuted: Bool
    let isVisible: Bool
    let isSoloActive: Bool
    let totalDurationSeconds: Double
    let maxSelectionDurationSeconds: Double
    let selectedRangeSeconds: ClosedRange<Double>

    var stableID: String {
        "\(layerIndex)-\(fileID.uuidString)"
    }
}

struct LayerTrimView: View {
    let contexts: [LayerTrimContext]
    let selectedLayerIndex: Int
    let visualOpacity: Double
    let onSelectLayer: (Int) -> Void
    let onMoveLayerUp: (Int) -> Void
    let onMoveLayerDown: (Int) -> Void
    let onDeleteLayer: (Int) -> Void
    let onSetBlendMode: (Int, String) -> Void
    let onSetOpacity: (Int, Double) -> Void
    let onToggleMute: (Int) -> Void
    let onToggleSolo: (Int) -> Void
    let onToggleVisibility: (Int) -> Void
    let onCommit: (Int, ClosedRange<Double>) -> Void

    var body: some View {
        if !contexts.isEmpty {
            VStack(spacing: 6) {
                ForEach(contexts, id: \.stableID) { context in
                    LayerTrimRangeStrip(
                        context: context,
                        isSelected: context.layerIndex == selectedLayerIndex,
                        visualOpacity: visualOpacity,
                        onSelect: {
                            onSelectLayer(context.layerIndex)
                        },
                        onMoveUp: {
                            onMoveLayerUp(context.layerIndex)
                        },
                        onMoveDown: {
                            onMoveLayerDown(context.layerIndex)
                        },
                        onDelete: {
                            onDeleteLayer(context.layerIndex)
                        },
                        onSetBlendMode: { blendMode in
                            onSetBlendMode(context.layerIndex, blendMode)
                        },
                        onSetOpacity: { opacity in
                            onSetOpacity(context.layerIndex, opacity)
                        },
                        onToggleMute: {
                            onToggleMute(context.layerIndex)
                        },
                        onToggleSolo: {
                            onToggleSolo(context.layerIndex)
                        },
                        onToggleVisibility: {
                            onToggleVisibility(context.layerIndex)
                        },
                        onCommit: { range in
                            onCommit(context.layerIndex, range)
                        }
                    )
                }
            }

            Divider()
                .background(Color.white.opacity(0.16))
        }
    }
}

private struct LayerTrimRangeStrip: View {
    let context: LayerTrimContext
    let isSelected: Bool
    let visualOpacity: Double
    let onSelect: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onSetBlendMode: (String) -> Void
    let onSetOpacity: (Double) -> Void
    let onToggleMute: () -> Void
    let onToggleSolo: () -> Void
    let onToggleVisibility: () -> Void
    let onCommit: (ClosedRange<Double>) -> Void

    @StateObject private var thumbnailStore = LayerTrimThumbnailStripStore()
    @State private var draftRange: ClosedRange<Double>
    @State private var draftOpacity: Double?

    private let trackHeight: CGFloat = 48
    private let handleWidth: CGFloat = 10
    private let minimumDurationSeconds: Double = 0.1

    init(
        context: LayerTrimContext,
        isSelected: Bool,
        visualOpacity: Double,
        onSelect: @escaping () -> Void,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSetBlendMode: @escaping (String) -> Void,
        onSetOpacity: @escaping (Double) -> Void,
        onToggleMute: @escaping () -> Void,
        onToggleSolo: @escaping () -> Void,
        onToggleVisibility: @escaping () -> Void,
        onCommit: @escaping (ClosedRange<Double>) -> Void
    ) {
        self.context = context
        self.isSelected = isSelected
        self.visualOpacity = visualOpacity
        self.onSelect = onSelect
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onDelete = onDelete
        self.onSetBlendMode = onSetBlendMode
        self.onSetOpacity = onSetOpacity
        self.onToggleMute = onToggleMute
        self.onToggleSolo = onToggleSolo
        self.onToggleVisibility = onToggleVisibility
        self.onCommit = onCommit
        _draftRange = State(initialValue: context.selectedRangeSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                if context.canMoveUp || context.canMoveDown {
                    reorderControlCluster
                }

                Text(context.clipLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.secondary.opacity(visualOpacity))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onSelect)

                if context.layerIndex != 0 {
                    blendModeMenu
                }

                compactOpacitySlider

                Text("\(formatTime(safeTotalSeconds)) / \(formatTime(activeRange.upperBound - activeRange.lowerBound))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(visualOpacity))
                    .frame(height: 22)

                layerControlCluster
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

                    if !thumbnailStore.thumbnails.isEmpty {
                        thumbnailTrack(trackWidth: trackWidth)
                    }

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

                    LayerTrimInteractionOverlay(
                        range: $draftRange,
                        totalDurationSeconds: safeTotalSeconds,
                        maxSelectionDurationSeconds: maxWindowSeconds,
                        minimumDurationSeconds: minimumWindowSeconds,
                        onSelect: onSelect,
                        onCommit: { committed in
                            let normalizedRange = normalized(committed)
                            draftRange = normalizedRange
                            onCommit(normalizedRange)
                        }
                    )
                }
                .contentShape(Rectangle())
            }
            .frame(height: trackHeight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.95))
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.leading, 4)
            }
        }
        .onTapGesture(perform: onSelect)
        .padding(.horizontal, 2)
        .onChange(of: context) { _, newValue in
            draftRange = normalized(newValue.selectedRangeSeconds)
        }
        .onAppear {
            thumbnailStore.loadIfNeeded(context: context)
        }
        .onChange(of: context.fileID) { _, _ in
            thumbnailStore.loadIfNeeded(context: context)
        }
        .onChange(of: context.source) { _, _ in
            thumbnailStore.loadIfNeeded(context: context)
        }
        .onChange(of: context.totalDurationSeconds) { _, _ in
            thumbnailStore.loadIfNeeded(context: context)
        }
        .onDisappear {
        }
    }

    private var blendModeMenu: some View {
        Menu {
            Button("Normal") {
                onSetBlendMode(BlendMode.sourceOver)
            }

            ForEach(BlendMode.all, id: \.self) { mode in
                Button(blendModeName(mode)) {
                    onSetBlendMode(mode)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(blendModeName(context.layerIndex == 0 ? BlendMode.sourceOver : context.blendMode))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(
                context.layerIndex == 0
                ? Color.secondary.opacity(0.45)
                : Color.secondary.opacity(visualOpacity)
            )
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.10 + (0.15 * visualOpacity)), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .disabled(context.layerIndex == 0)
    }

    private var compactOpacitySlider: some View {
        HStack(spacing: 3) {
            Button {
                draftOpacity = nil
                onSetOpacity(0)
            } label: {
                Image(systemName: "eye.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(visualOpacity))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Set Layer to 0% Opacity")

            PanelSliderView(
                value: Binding(
                    get: { draftOpacity ?? context.opacity.clamped(to: 0...1) },
                    set: { draftOpacity = $0 }
                ),
                bounds: 0...1,
                step: 0.01,
                thumbDiameter: 12,
                onEditingChanged: { isEditing in
                    if isEditing {
                        draftOpacity = context.opacity.clamped(to: 0...1)
                    } else {
                        if let draftOpacity {
                            onSetOpacity(draftOpacity.clamped(to: 0...1))
                        }
                        draftOpacity = nil
                    }
                }
            )
            .frame(width: 72, height: 22, alignment: .center)

            Button {
                draftOpacity = nil
                onSetOpacity(1.0)
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(visualOpacity))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Set Layer to 100% Opacity")
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

    @ViewBuilder
    private func thumbnailTrack(trackWidth: CGFloat) -> some View {
        let thumbnails = thumbnailStore.thumbnails
        let count = max(1, thumbnails.count)
        let tileWidth = trackWidth / CGFloat(count)

        HStack(spacing: 0) {
            ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: tileWidth, height: trackHeight)
                    .clipped()
            }
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .saturation(0.84)
        .contrast(0.98)
        .opacity(0.58)
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
        return stripped
            .replacingOccurrences(of: "(?<!^)([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var layerControlCluster: some View {
        HStack(spacing: 6) {
            layerIconButton(
                systemName: "trash",
                isEnabled: context.canDelete,
                foreground: context.canDelete ? Color.red.opacity(0.82) : Color.secondary.opacity(0.28),
                tooltip: "Delete Layer",
                action: onDelete
            )

            layerToggleButton(
                label: {
                    Image(systemName: context.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption.weight(.medium))
                },
                isActive: context.isMuted,
                activeFill: Color.red,
                activeForeground: .white,
                inactiveForeground: Color.secondary.opacity(visualOpacity),
                tooltip: context.isMuted ? "Unmute Layer" : "Mute Layer",
                action: onToggleMute
            )

            layerToggleButton(
                label: { Text("S").font(.caption.weight(.bold)) },
                isActive: context.isSoloActive,
                activeFill: Color.yellow,
                activeForeground: .black,
                inactiveForeground: Color.secondary.opacity(visualOpacity),
                tooltip: context.isSoloActive ? "Clear Solo" : "Solo Layer",
                action: onToggleSolo
            )
        }
    }

    private var reorderControlCluster: some View {
        HStack(spacing: 6) {
            layerIconButton(
                systemName: "chevron.up",
                isEnabled: context.canMoveUp,
                tooltip: "Move Layer Up",
                action: onMoveUp
            )

            layerIconButton(
                systemName: "chevron.down",
                isEnabled: context.canMoveDown,
                tooltip: "Move Layer Down",
                action: onMoveDown
            )
        }
    }

    private func layerIconButton(
        systemName: String,
        isEnabled: Bool,
        foreground: Color? = nil,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.clear)
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.white.opacity(0.10 + (0.15 * visualOpacity)), lineWidth: 1)
                    )

                Image(systemName: systemName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        isEnabled
                        ? (foreground ?? Color.secondary.opacity(visualOpacity))
                        : Color.secondary.opacity(0.28)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(tooltip)
    }

    private func layerToggleButton<Label: View>(
        @ViewBuilder label: () -> Label,
        isActive: Bool,
        activeFill: Color,
        activeForeground: Color,
        inactiveForeground: Color,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label()
                .frame(width: 20, height: 20)
                .background(isActive ? activeFill : Color.clear)
                .foregroundStyle(isActive ? activeForeground : inactiveForeground)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.10 + (0.15 * visualOpacity)), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
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

private struct LayerTrimInteractionOverlay: NSViewRepresentable {
    @Binding var range: ClosedRange<Double>
    let totalDurationSeconds: Double
    let maxSelectionDurationSeconds: Double
    let minimumDurationSeconds: Double
    let onSelect: () -> Void
    let onCommit: (ClosedRange<Double>) -> Void

    func makeNSView(context: Context) -> LayerTrimInteractionView {
        let view = LayerTrimInteractionView()
        view.onSelect = onSelect
        view.onRangeChanged = { newRange in
            range = newRange
        }
        view.onRangeCommitted = { committedRange in
            onCommit(committedRange)
        }
        return view
    }

    func updateNSView(_ nsView: LayerTrimInteractionView, context: Context) {
        nsView.totalDurationSeconds = totalDurationSeconds
        nsView.maxSelectionDurationSeconds = maxSelectionDurationSeconds
        nsView.minimumDurationSeconds = minimumDurationSeconds
        nsView.currentRange = range
        nsView.onSelect = onSelect
        nsView.onRangeChanged = { newRange in
            range = newRange
        }
        nsView.onRangeCommitted = { committedRange in
            onCommit(committedRange)
        }
    }
}

private final class LayerTrimInteractionView: NSView {
    private enum DragMode {
        case leadingHandle
        case trailingHandle
        case window
    }

    var totalDurationSeconds: Double = 0.1
    var maxSelectionDurationSeconds: Double = 0.1
    var minimumDurationSeconds: Double = 0.1
    var currentRange: ClosedRange<Double> = 0...0.1
    var onSelect: (() -> Void)?
    var onRangeChanged: ((ClosedRange<Double>) -> Void)?
    var onRangeCommitted: ((ClosedRange<Double>) -> Void)?

    private var dragStartPoint: CGPoint?
    private var dragStartRange: ClosedRange<Double>?
    private var dragMode: DragMode?

    private let handleHitWidth: CGFloat = 20

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        let point = convert(event.locationInWindow, from: nil)
        dragStartPoint = point
        dragStartRange = normalized(currentRange)
        dragMode = dragModeForStartPoint(point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPoint, let dragStartRange, let dragMode else { return }

        let point = convert(event.locationInWindow, from: nil)
        let delta = secondsDelta(forTranslationX: point.x - dragStartPoint.x, trackWidth: bounds.width)
        let total = safeTotalSeconds
        let minWindow = safeMinimumDurationSeconds
        let maxWindow = safeMaxSelectionDurationSeconds

        let updatedRange: ClosedRange<Double>
        switch dragMode {
        case .leadingHandle:
            let minLower = dragStartRange.upperBound - maxWindow
            let maxLower = dragStartRange.upperBound - minWindow
            let newLower = max(minLower, min(dragStartRange.lowerBound + delta, maxLower))
            updatedRange = newLower...dragStartRange.upperBound

        case .trailingHandle:
            let minUpper = dragStartRange.lowerBound + minWindow
            let maxUpper = min(total, dragStartRange.lowerBound + maxWindow)
            let newUpper = max(minUpper, min(dragStartRange.upperBound + delta, maxUpper))
            updatedRange = dragStartRange.lowerBound...newUpper

        case .window:
            let windowWidth = dragStartRange.upperBound - dragStartRange.lowerBound
            let proposedLower = dragStartRange.lowerBound + delta
            let clampedLower = max(0, min(proposedLower, total - windowWidth))
            updatedRange = clampedLower...(clampedLower + windowWidth)
        }

        let normalizedRange = normalized(updatedRange)
        currentRange = normalizedRange
        onRangeChanged?(normalizedRange)
    }

    override func mouseUp(with event: NSEvent) {
        let committedRange = normalized(currentRange)
        currentRange = committedRange
        onRangeCommitted?(committedRange)
        dragStartPoint = nil
        dragStartRange = nil
        dragMode = nil
    }

    private var safeTotalSeconds: Double {
        max(0.1, totalDurationSeconds)
    }

    private var safeMinimumDurationSeconds: Double {
        min(max(0.1, minimumDurationSeconds), safeTotalSeconds)
    }

    private var safeMaxSelectionDurationSeconds: Double {
        max(
            safeMinimumDurationSeconds,
            min(maxSelectionDurationSeconds, safeTotalSeconds)
        )
    }

    private func normalized(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        let total = safeTotalSeconds
        let minWindow = safeMinimumDurationSeconds
        let maxWindow = safeMaxSelectionDurationSeconds

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
        guard safeTotalSeconds > 0, trackWidth > 0 else { return 0 }
        let fraction = max(0, min(seconds / safeTotalSeconds, 1))
        return CGFloat(fraction) * trackWidth
    }

    private func secondsDelta(forTranslationX translationX: CGFloat, trackWidth: CGFloat) -> Double {
        guard trackWidth > 0 else { return 0 }
        return Double(translationX / trackWidth) * safeTotalSeconds
    }

    private func dragModeForStartPoint(_ point: CGPoint) -> DragMode {
        let trackWidth = max(1, bounds.width)
        let range = normalized(currentRange)
        let startX = xPosition(forSeconds: range.lowerBound, trackWidth: trackWidth)
        let endX = xPosition(forSeconds: range.upperBound, trackWidth: trackWidth)
        let selectedWidth = max(0, endX - startX)
        let leftDistance = abs(point.x - startX)
        let rightDistance = abs(point.x - endX)
        let insideSelectedRange = point.x >= startX && point.x <= endX
        let edgeGrabTolerance = min(
            handleHitWidth * 0.5,
            max(3, selectedWidth * 0.25)
        )

        if insideSelectedRange {
            if leftDistance <= edgeGrabTolerance || rightDistance <= edgeGrabTolerance {
                return leftDistance <= rightDistance ? .leadingHandle : .trailingHandle
            }
            return .window
        }

        if leftDistance <= handleHitWidth * 0.5 {
            return .leadingHandle
        }
        if rightDistance <= handleHitWidth * 0.5 {
            return .trailingHandle
        }
        return leftDistance < rightDistance ? .leadingHandle : .trailingHandle
    }
}

private final class LayerTrimThumbnailStripStore: ObservableObject {
    @Published private(set) var thumbnails: [NSImage] = []

    private static var cache: [UUID: [NSImage]] = [:]
    private static var cacheOrder: [UUID] = []
    private static let maxCacheEntries = 36

    private var currentFileID: UUID?
    private var loadTask: Task<Void, Never>?

    func loadIfNeeded(context: LayerTrimContext) {
        if currentFileID == context.fileID, !thumbnails.isEmpty {
            return
        }

        if let cached = Self.cache[context.fileID], !cached.isEmpty {
            currentFileID = context.fileID
            thumbnails = cached
            return
        }

        currentFileID = context.fileID
        thumbnails = []
        loadTask?.cancel()

        let fileID = context.fileID
        let source = context.source
        let mediaKind = context.mediaKind
        let duration = context.totalDurationSeconds

        loadTask = Task(priority: .utility) { [weak self] in
            let generated = await Self.generateThumbnails(
                source: source,
                mediaKind: mediaKind,
                durationSeconds: duration
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                guard self.currentFileID == fileID else { return }
                self.thumbnails = generated
                Self.storeInCache(fileID: fileID, thumbnails: generated)
            }
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private static func storeInCache(fileID: UUID, thumbnails: [NSImage]) {
        guard !thumbnails.isEmpty else { return }
        cache[fileID] = thumbnails
        cacheOrder.removeAll(where: { $0 == fileID })
        cacheOrder.append(fileID)

        while cacheOrder.count > maxCacheEntries {
            let removedID = cacheOrder.removeFirst()
            cache.removeValue(forKey: removedID)
        }
    }

    private static func generateThumbnails(
        source: MediaSource,
        mediaKind: MediaKind,
        durationSeconds: Double
    ) async -> [NSImage] {
        if mediaKind == .image {
            guard let image = await resolveStillImage(for: source) else { return [] }
            let totalDuration = max(0.2, durationSeconds)
            let frameCount = min(24, max(6, Int(totalDuration.rounded(.up))))
            return Array(repeating: image, count: frameCount)
        }

        guard let asset = await resolveAsset(for: source) else { return [] }

        let totalDuration = max(0.2, durationSeconds)
        // Aim for roughly one thumbnail per second on longer clips, but keep a hard cap
        // so thumbnail generation stays cheap and unlikely to interfere with playback.
        let frameCount = min(24, max(6, Int(totalDuration.rounded(.up))))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 112, height: 68)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.12, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)

        var images: [NSImage] = []
        images.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            if Task.isCancelled { return [] }

            let fraction = (Double(index) + 0.5) / Double(frameCount)
            let sampleSeconds = min(totalDuration - 0.033, max(0, totalDuration * fraction))
            let sampleTime = CMTime(seconds: sampleSeconds, preferredTimescale: 600)

            if let cgImage = try? generator.copyCGImage(at: sampleTime, actualTime: nil) {
                images.append(NSImage(cgImage: cgImage, size: .zero))
            }
        }

        if images.isEmpty,
           let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            images.append(NSImage(cgImage: cgImage, size: .zero))
        }

        return images
    }

    private static func resolveAsset(for source: MediaSource) async -> AVAsset? {
        switch source {
        case .url(let url):
            return AVURLAsset(url: url)
        case .external(let identifier):
            return await HypnoCoreHooks.shared.resolveExternalVideo?(identifier)
        }
    }

    private static func resolveStillImage(for source: MediaSource) async -> NSImage? {
        switch source {
        case .url(let url):
            if let image = NSImage(contentsOf: url) {
                return image
            }
            guard let cgImage = StillImageCache.cgImage(for: url) else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        case .external(let identifier):
            guard let cgImage = await MediaFile(
                source: .external(identifier: identifier),
                mediaKind: .image,
                duration: .zero
            ).loadCGImage() else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: .zero)
        }
    }
}
