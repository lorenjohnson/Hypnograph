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
    let sourceDurationSeconds: Double
    let maxSelectionDurationSeconds: Double
    let selectedRangeSeconds: ClosedRange<Double>

    var stableID: String {
        "\(layerIndex)-\(fileID.uuidString)"
    }

}

struct LayerTrimView: View {
    let contexts: [LayerTrimContext]
    let selectedLayerIndex: Int
    let compositionTimelineDurationSeconds: Double
    let currentPlayheadSeconds: Double?
    let isShowingFullClips: Bool
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
    let onToggleShowFullClips: () -> Void
    let onCommit: (Int, ClosedRange<Double>) -> Void

    private func snapTargetDurations(for context: LayerTrimContext) -> [Double] {
        let otherLayerDurations = contexts
            .filter { $0.layerIndex != context.layerIndex }
            .map { max(0.1, $0.selectedRangeSeconds.upperBound - $0.selectedRangeSeconds.lowerBound) }

        let currentCompositionDuration = max(0.1, compositionTimelineDurationSeconds)
        let longestOtherLayerDuration = otherLayerDurations.max()

        return [currentCompositionDuration, longestOtherLayerDuration]
            .compactMap { $0 }
            .map { max(0.1, $0) }
            .reduce(into: [Double]()) { result, duration in
                if !result.contains(where: { abs($0 - duration) < 0.0001 }) {
                    result.append(duration)
                }
            }
    }

    var body: some View {
        if !contexts.isEmpty {
            VStack(spacing: 0) {
                ForEach(contexts, id: \.stableID) { context in
                    LayerTrimRangeStrip(
                        context: context,
                        isSelected: context.layerIndex == selectedLayerIndex,
                        compositionTimelineDurationSeconds: compositionTimelineDurationSeconds,
                        currentPlayheadSeconds: currentPlayheadSeconds,
                        isShowingFullClips: isShowingFullClips,
                        snapTargetDurationsSeconds: snapTargetDurations(for: context),
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
                        onToggleShowFullClips: onToggleShowFullClips,
                        onCommit: { range in
                            onCommit(context.layerIndex, range)
                        }
                    )
                }
            }
        }
    }
}

private struct LayerTrimRangeStrip: View {
    let context: LayerTrimContext
    let isSelected: Bool
    let compositionTimelineDurationSeconds: Double
    let currentPlayheadSeconds: Double?
    let isShowingFullClips: Bool
    let snapTargetDurationsSeconds: [Double]
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
    let onToggleShowFullClips: () -> Void
    let onCommit: (ClosedRange<Double>) -> Void

    @StateObject private var thumbnailStore = LayerTrimThumbnailStripStore()
    @State private var draftRange: ClosedRange<Double>
    @State private var draftOpacity: Double?

    private let trackHeight: CGFloat = 62
    private let headerOverlayHeight: CGFloat = 24
    private let trimInteractionBottomInset: CGFloat = 28
    private let minimumDurationSeconds: Double = 0.1

    init(
        context: LayerTrimContext,
        isSelected: Bool,
        compositionTimelineDurationSeconds: Double,
        currentPlayheadSeconds: Double?,
        isShowingFullClips: Bool,
        snapTargetDurationsSeconds: [Double],
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
        onToggleShowFullClips: @escaping () -> Void,
        onCommit: @escaping (ClosedRange<Double>) -> Void
    ) {
        self.context = context
        self.isSelected = isSelected
        self.compositionTimelineDurationSeconds = compositionTimelineDurationSeconds
        self.currentPlayheadSeconds = currentPlayheadSeconds
        self.isShowingFullClips = isShowingFullClips
        self.snapTargetDurationsSeconds = snapTargetDurationsSeconds
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
        self.onToggleShowFullClips = onToggleShowFullClips
        self.onCommit = onCommit
        _draftRange = State(initialValue: context.selectedRangeSeconds)
    }

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(1, geometry.size.width)
            let trimHeight = max(18, trackHeight - trimInteractionBottomInset)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: trackHeight)

                tickMarks(trackWidth: trackWidth)

                clipBody(trackWidth: trackWidth)

                LayerTrimInteractionOverlay(
                    range: $draftRange,
                    totalDurationSeconds: sourceTotalSeconds,
                    timelineDurationSeconds: isShowingFullClips ? sourceTotalSeconds : timelineDurationSeconds,
                    snapTargetDurationsSeconds: snapTargetDurationsSeconds,
                    maxSelectionDurationSeconds: maxWindowSeconds,
                    minimumDurationSeconds: minimumWindowSeconds,
                    usesSourceSelectionMode: isShowingFullClips,
                    onSelect: onSelect,
                    onCommit: { committed in
                        let normalizedRange = normalized(committed)
                        draftRange = normalizedRange
                        onCommit(normalizedRange)
                    }
                )
                .frame(width: trackWidth, height: trimHeight, alignment: .leading)
                .frame(height: trimHeight)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.95))
                        .frame(width: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .frame(height: trackHeight)
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2) {
            onSelect()
            onToggleShowFullClips()
        }
        .onChange(of: context) { _, newValue in
            draftRange = normalized(newValue.selectedRangeSeconds)
            thumbnailStore.loadIfNeeded(context: newValue)
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
        .onChange(of: context.sourceDurationSeconds) { _, _ in
            thumbnailStore.loadIfNeeded(context: context)
        }
        .onDisappear {
        }
    }

    @ViewBuilder
    private func clipBody(trackWidth: CGFloat) -> some View {
        if isShowingFullClips {
            sourceSelectionBody(trackWidth: trackWidth)
        } else {
            let selectedWindowWidth = selectedWindowWidth(for: trackWidth)
            let trailingShadeWidth = max(0, trackWidth - selectedWindowWidth)

            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.06))
                    .frame(width: trackWidth, height: trackHeight)

                if !thumbnailStore.baseThumbnails.isEmpty {
                    HStack(spacing: 0) {
                        selectedTimelineThumbnailTrack(trackWidth: selectedWindowWidth)

                        if trailingShadeWidth > 0.5 {
                            trailingContextThumbnailTrack(trackWidth: trailingShadeWidth)
                        }
                    }
                    .frame(width: trackWidth, height: trackHeight, alignment: .leading)
                }

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.06 : 0.03))
                        .frame(width: selectedWindowWidth, height: trackHeight - 2)
                        .frame(height: trackHeight)

                    Rectangle()
                        .fill(Color.black.opacity(0.42))
                        .frame(width: trailingShadeWidth)
                }
                .frame(width: trackWidth, height: trackHeight)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.44 : 0.28), lineWidth: 1.0)
                    .frame(width: selectedWindowWidth, height: trackHeight - 2)
                    .frame(width: trackWidth, height: trackHeight, alignment: .leading)

                resizeHandleOverlay(trackWidth: trackWidth, selectedWindowWidth: selectedWindowWidth)
                compositionPlayheadOverlay(trackWidth: trackWidth)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.62)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: headerOverlayHeight + 14)
                    .overlay(alignment: .bottomLeading) {
                        headerOverlay
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                    }
                }
                .frame(width: trackWidth, height: trackHeight)
                .clipShape(Rectangle())
            }
            .clipShape(Rectangle())
        }
    }

    @ViewBuilder
    private func sourceSelectionBody(trackWidth: CGFloat) -> some View {
        let total = max(0.1, sourceTotalSeconds)
        let lowerFraction = max(0, min(activeRange.lowerBound / total, 1))
        let upperFraction = max(lowerFraction, min(activeRange.upperBound / total, 1))
        let leadingShadeWidth = trackWidth * lowerFraction
        let selectedWidth = max(24, trackWidth * (upperFraction - lowerFraction))
        let trailingShadeWidth = max(0, trackWidth - leadingShadeWidth - selectedWidth)

        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.white.opacity(isSelected ? 0.10 : 0.06))
                .frame(width: trackWidth, height: trackHeight)

            if !thumbnailStore.baseThumbnails.isEmpty {
                sourceThumbnailTrack(trackWidth: trackWidth)
            }

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: leadingShadeWidth)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.06 : 0.03))
                    .frame(width: selectedWidth, height: trackHeight - 2)
                    .frame(height: trackHeight)

                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: trailingShadeWidth)
            }
            .frame(width: trackWidth, height: trackHeight)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.44 : 0.28), lineWidth: 1.0)
                .frame(width: selectedWidth, height: trackHeight - 2)
                .frame(width: trackWidth, height: trackHeight, alignment: .leading)
                .offset(x: leadingShadeWidth)

            sourceSelectionHandleOverlay(trackWidth: trackWidth, leadingShadeWidth: leadingShadeWidth, selectedWidth: selectedWidth)
            sourcePlayheadOverlay(trackWidth: trackWidth)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.62)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: headerOverlayHeight + 14)
                .overlay(alignment: .bottomLeading) {
                    headerOverlay
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: trackWidth, height: trackHeight)
            .clipShape(Rectangle())
        }
        .clipShape(Rectangle())
    }

    @ViewBuilder
    private func resizeHandleOverlay(trackWidth: CGFloat, selectedWindowWidth: CGFloat) -> some View {
        let edgeInset: CGFloat = 8
        let rightX = min(trackWidth - edgeInset, selectedWindowWidth - edgeInset)

        resizeHandle
            .offset(x: rightX)
            .frame(width: trackWidth, height: trackHeight, alignment: .topLeading)
    }

    private var resizeHandle: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.58))
            .frame(width: 2, height: 14)
            .padding(.top, 8)
    }

    @ViewBuilder
    private func sourceSelectionHandleOverlay(trackWidth: CGFloat, leadingShadeWidth: CGFloat, selectedWidth: CGFloat) -> some View {
        let edgeInset: CGFloat = 8
        let leftX = leadingShadeWidth + edgeInset
        let rightX = leadingShadeWidth + max(edgeInset, selectedWidth - edgeInset)

        ZStack(alignment: .topLeading) {
            resizeHandle
                .offset(x: leftX)

            resizeHandle
                .offset(x: rightX)
        }
        .frame(width: trackWidth, height: trackHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func compositionPlayheadOverlay(trackWidth: CGFloat) -> some View {
        if !isShowingFullClips, let currentPlayheadSeconds {
            let clampedTime = max(0, min(currentPlayheadSeconds, timelineDurationSeconds))
            let fraction = timelineDurationSeconds > 0 ? clampedTime / timelineDurationSeconds : 0
            let x = trackWidth * fraction

            Rectangle()
                .fill(Color.accentColor.opacity(0.95))
                .frame(width: 1.5, height: trackHeight)
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func sourcePlayheadOverlay(trackWidth: CGFloat) -> some View {
        if isShowingFullClips, let currentPlayheadSeconds {
            let windowDuration = max(0.0001, activeDurationSeconds)
            let loopOffset = currentPlayheadSeconds.truncatingRemainder(dividingBy: windowDuration)
            let sourceSeconds = min(sourceTotalSeconds, activeRange.lowerBound + loopOffset)
            let fraction = sourceTotalSeconds > 0 ? sourceSeconds / sourceTotalSeconds : 0
            let x = trackWidth * fraction

            Rectangle()
                .fill(Color.accentColor.opacity(0.95))
                .frame(width: 1.5, height: trackHeight)
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }

    private var headerOverlay: some View {
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

            Text(formatTime(activeRange.upperBound - activeRange.lowerBound))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.secondary.opacity(visualOpacity))
                .frame(height: 22)

            layerControlCluster
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

    private var sourceTotalSeconds: Double {
        max(0.1, context.sourceDurationSeconds)
    }

    private var timelineDurationSeconds: Double {
        max(0.1, compositionTimelineDurationSeconds)
    }

    private var activeDurationSeconds: Double {
        max(0.1, activeRange.upperBound - activeRange.lowerBound)
    }

    private var activeRange: ClosedRange<Double> {
        normalized(draftRange)
    }

    private var minimumWindowSeconds: Double {
        min(minimumDurationSeconds, sourceTotalSeconds)
    }

    private var maxWindowSeconds: Double {
        max(minimumWindowSeconds, min(context.maxSelectionDurationSeconds, sourceTotalSeconds))
    }

    private func normalized(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        let total = sourceTotalSeconds
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

    @ViewBuilder
    private func tickMarks(trackWidth: CGFloat) -> some View {
        let maxTicks = 10
        let candidateCount = Int(timelineDurationSeconds.rounded(.down))
        let divisions = max(2, min(maxTicks, max(2, candidateCount)))

        ForEach(0...divisions, id: \.self) { index in
            let fraction = CGFloat(Double(index) / Double(divisions))
                Rectangle()
                    .fill(Color.white.opacity(index == 0 || index == divisions ? 0.35 : 0.18))
                    .frame(width: 1, height: index == 0 || index == divisions ? 14 : 9)
                    .offset(x: max(0, min(trackWidth * fraction - 0.5, trackWidth - 1)), y: 18)
        }
    }

    private func selectedWindowWidth(for trackWidth: CGFloat) -> CGFloat {
        let fraction = max(0.01, min(1, activeDurationSeconds / timelineDurationSeconds))
        return max(24, trackWidth * CGFloat(fraction))
    }

    @ViewBuilder
    private func selectedTimelineThumbnailTrack(trackWidth: CGFloat) -> some View {
        let thumbnails = displayedThumbnails(from: thumbnailStore.baseThumbnails, trackWidth: trackWidth)
        let count = max(1, thumbnails.count)
        let tileWidth = trackWidth / CGFloat(count)

        HStack(spacing: 0) {
            ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumbnail in
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.22)

                    Image(nsImage: thumbnail.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: tileWidth, height: trackHeight)
                        .clipped()

                    if thumbnail.startsLoop {
                        Rectangle()
                            .fill(Color.white.opacity(0.30))
                            .frame(width: 1, height: trackHeight)
                    }
                }
            }
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(Rectangle())
        .saturation(0.86)
        .contrast(1.0)
        .opacity(0.72)
    }

    @ViewBuilder
    private func trailingContextThumbnailTrack(trackWidth: CGFloat) -> some View {
        let thumbnails = displayedSourceThumbnails(from: thumbnailStore.baseThumbnails, trackWidth: trackWidth)
        let count = max(1, thumbnails.count)
        let tileWidth = trackWidth / CGFloat(count)

        HStack(spacing: 0) {
            ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumbnail in
                ZStack {
                    Color.black.opacity(0.22)

                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: tileWidth, height: trackHeight)
                        .clipped()
                }
            }
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(Rectangle())
        .saturation(0.82)
        .contrast(0.94)
        .opacity(0.46)
    }

    @ViewBuilder
    private func sourceThumbnailTrack(trackWidth: CGFloat) -> some View {
        let thumbnails = displayedSourceThumbnails(from: thumbnailStore.baseThumbnails, trackWidth: trackWidth)
        let count = max(1, thumbnails.count)
        let tileWidth = trackWidth / CGFloat(count)

        HStack(spacing: 0) {
            ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumbnail in
                ZStack {
                    Color.black.opacity(0.22)

                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: tileWidth, height: trackHeight)
                        .clipped()
                }
            }
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(Rectangle())
        .saturation(0.86)
        .contrast(1.0)
        .opacity(0.72)
    }

    private func displayedSourceThumbnails(from baseThumbnails: [NSImage], trackWidth: CGFloat) -> [NSImage] {
        guard !baseThumbnails.isEmpty else { return [] }

        let totalDuration = max(0.2, sourceTotalSeconds)
        let durationDrivenCount: Int
        if totalDuration >= 5 * 60 {
            durationDrivenCount = 20
        } else if totalDuration >= 90 {
            durationDrivenCount = 22
        } else if totalDuration >= 30 {
            durationDrivenCount = 24
        } else {
            durationDrivenCount = 28
        }

        let widthDrivenCap = max(10, Int(trackWidth / 56))
        let frameCount = min(baseThumbnails.count, min(durationDrivenCount, widthDrivenCap))
        guard frameCount < baseThumbnails.count else { return baseThumbnails }

        return (0..<frameCount).map { index in
            let fraction = frameCount == 1 ? 0.5 : Double(index) / Double(frameCount - 1)
            let sampledIndex = min(
                baseThumbnails.count - 1,
                max(0, Int(round(fraction * Double(baseThumbnails.count - 1))))
            )
            return baseThumbnails[sampledIndex]
        }
    }

    private func displayedThumbnails(from baseThumbnails: [NSImage], trackWidth: CGFloat) -> [(image: NSImage, startsLoop: Bool)] {
        guard !baseThumbnails.isEmpty else { return [] }

        let totalDuration = max(0.2, timelineDurationSeconds)
        let selectedStart = activeRange.lowerBound
        let selectedDuration = max(0.033, activeRange.upperBound - activeRange.lowerBound)
        let durationDrivenCount = max(18, Int(totalDuration.rounded(.up) * 3.0))
        let widthDrivenCap = max(12, Int(trackWidth / 56))
        let frameCount = min(96, min(durationDrivenCount, widthDrivenCap))
        let frameStep = totalDuration / Double(frameCount)

        return (0..<frameCount).map { index in
            let timelineSeconds = min(totalDuration - 0.033, max(0, (Double(index) + 0.5) * frameStep))
            let loopCycle = Int(floor(timelineSeconds / selectedDuration))
            let loopOffset = timelineSeconds.truncatingRemainder(dividingBy: selectedDuration)
            let sampleSeconds = min(sourceTotalSeconds - 0.033, max(0, selectedStart + loopOffset))
            let normalized = min(0.999, max(0, sampleSeconds / sourceTotalSeconds))
            let baseIndex = min(baseThumbnails.count - 1, max(0, Int(floor(normalized * Double(baseThumbnails.count)))))
            let previousCycle = index == 0 ? loopCycle : Int(floor(max(0, timelineSeconds - frameStep) / selectedDuration))
            return (image: baseThumbnails[baseIndex], startsLoop: index != 0 && loopCycle != previousCycle)
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

            layerToggleButton(
                label: {
                    Image(systemName: context.isVisible ? "eye" : "eye.slash")
                        .font(.caption.weight(.medium))
                },
                isActive: !context.isVisible,
                activeFill: Color.red.opacity(0.88),
                activeForeground: .white,
                inactiveForeground: Color.secondary.opacity(visualOpacity),
                tooltip: context.isVisible ? "Hide Layer" : "Show Layer",
                action: onToggleVisibility
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

}

private struct LayerTrimInteractionOverlay: NSViewRepresentable {
    @Binding var range: ClosedRange<Double>
    let totalDurationSeconds: Double
    let timelineDurationSeconds: Double
    let snapTargetDurationsSeconds: [Double]
    let maxSelectionDurationSeconds: Double
    let minimumDurationSeconds: Double
    let usesSourceSelectionMode: Bool
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
        nsView.timelineDurationSeconds = timelineDurationSeconds
        nsView.snapTargetDurationsSeconds = snapTargetDurationsSeconds
        nsView.maxSelectionDurationSeconds = maxSelectionDurationSeconds
        nsView.minimumDurationSeconds = minimumDurationSeconds
        nsView.usesSourceSelectionMode = usesSourceSelectionMode
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
    var timelineDurationSeconds: Double = 0.1
    var snapTargetDurationsSeconds: [Double] = []
    var maxSelectionDurationSeconds: Double = 0.1
    var minimumDurationSeconds: Double = 0.1
    var usesSourceSelectionMode: Bool = false
    var currentRange: ClosedRange<Double> = 0...0.1
    var onSelect: (() -> Void)?
    var onRangeChanged: ((ClosedRange<Double>) -> Void)?
    var onRangeCommitted: ((ClosedRange<Double>) -> Void)?

    private var dragStartPoint: CGPoint?
    private var dragStartRange: ClosedRange<Double>?
    private var dragMode: DragMode?

    private let handleHitWidth: CGFloat = 36

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        let point = convert(event.locationInWindow, from: nil)
        dragStartPoint = point
        dragStartRange = normalized(currentRange)
        dragMode = dragModeForStartEvent(event, at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPoint, let dragStartRange, let dragMode else { return }

        let point = convert(event.locationInWindow, from: nil)
        let translationX = point.x - dragStartPoint.x
        let resizeDelta = resizeSecondsDelta(forTranslationX: translationX, trackWidth: bounds.width)
        let slipDelta = slipSecondsDelta(forTranslationX: translationX, trackWidth: bounds.width)
        let total = safeTotalSeconds
        let minWindow = safeMinimumDurationSeconds
        let maxWindow = safeMaxSelectionDurationSeconds

        let updatedRange: ClosedRange<Double>
        switch dragMode {
        case .leadingHandle:
            let minLower = dragStartRange.upperBound - maxWindow
            let maxLower = dragStartRange.upperBound - minWindow
            let newLower = max(minLower, min(dragStartRange.lowerBound + resizeDelta, maxLower))
            updatedRange = snappedToRelevantDurationIfNeeded(
                proposed: newLower...dragStartRange.upperBound,
                dragMode: dragMode,
                trackWidth: bounds.width
            )

        case .trailingHandle:
            let minUpper = dragStartRange.lowerBound + minWindow
            let maxUpper = min(total, dragStartRange.lowerBound + maxWindow)
            let newUpper = max(minUpper, min(dragStartRange.upperBound + resizeDelta, maxUpper))
            updatedRange = snappedToRelevantDurationIfNeeded(
                proposed: dragStartRange.lowerBound...newUpper,
                dragMode: dragMode,
                trackWidth: bounds.width
            )

        case .window:
            let windowWidth = dragStartRange.upperBound - dragStartRange.lowerBound
            let proposedLower = dragStartRange.lowerBound + slipDelta
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

    private var safeTimelineDurationSeconds: Double {
        max(0.1, timelineDurationSeconds)
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

    private func snappedToRelevantDurationIfNeeded(
        proposed: ClosedRange<Double>,
        dragMode: DragMode,
        trackWidth: CGFloat
    ) -> ClosedRange<Double> {
        let proposedDuration = proposed.upperBound - proposed.lowerBound
        guard let targetDuration = matchingSnapTargetDuration(for: proposedDuration, trackWidth: trackWidth) else {
            return proposed
        }

        switch dragMode {
        case .leadingHandle:
            let snappedLower = proposed.upperBound - targetDuration
            guard snappedLower >= 0 else { return proposed }
            return snappedLower...proposed.upperBound

        case .trailingHandle:
            let snappedUpper = proposed.lowerBound + targetDuration
            guard snappedUpper <= safeTotalSeconds else { return proposed }
            return proposed.lowerBound...snappedUpper

        case .window:
            return proposed
        }
    }

    private func matchingSnapTargetDuration(for proposedDuration: Double, trackWidth: CGFloat) -> Double? {
        let snapThresholdSeconds = max(0.16, Double(18 / max(trackWidth, 1)) * safeTimelineDurationSeconds)

        return snapTargetDurationsSeconds
            .filter { $0 >= safeMinimumDurationSeconds && $0 <= safeMaxSelectionDurationSeconds }
            .min(by: { abs($0 - proposedDuration) < abs($1 - proposedDuration) })
            .flatMap { candidate in
                abs(candidate - proposedDuration) <= snapThresholdSeconds ? candidate : nil
            }
    }

    private func resizeSecondsDelta(forTranslationX translationX: CGFloat, trackWidth: CGFloat) -> Double {
        guard trackWidth > 0 else { return 0 }
        return Double(translationX / trackWidth) * safeTimelineDurationSeconds
    }

    private func slipSecondsDelta(forTranslationX translationX: CGFloat, trackWidth: CGFloat) -> Double {
        guard trackWidth > 0 else { return 0 }
        let directionAdjustedTranslation = usesSourceSelectionMode ? translationX : -translationX
        return Double(directionAdjustedTranslation / trackWidth) * safeTotalSeconds
    }

    private func dragModeForStartEvent(_ event: NSEvent, at point: CGPoint) -> DragMode {
        if usesSourceSelectionMode {
            let leftEdge = bounds.width * CGFloat(max(0, min(currentRange.lowerBound / safeTotalSeconds, 1)))
            let rightEdge = bounds.width * CGFloat(max(0, min(currentRange.upperBound / safeTotalSeconds, 1)))

            if abs(point.x - leftEdge) <= handleHitWidth {
                return .leadingHandle
            }
            if abs(point.x - rightEdge) <= handleHitWidth {
                return .trailingHandle
            }
            return .window
        }

        let visibleWindowWidth = max(24, bounds.width * CGFloat(max(0.01, min(1, currentWindowSeconds / safeTimelineDurationSeconds))))
        let rightEdge = visibleWindowWidth

        if abs(point.x - rightEdge) <= handleHitWidth {
            return .trailingHandle
        }
        if event.modifierFlags.contains(.command) {
            return .trailingHandle
        }
        return .window
    }

    private var currentWindowSeconds: Double {
        max(0.1, currentRange.upperBound - currentRange.lowerBound)
    }
}

private final class LayerTrimThumbnailStripStore: ObservableObject {
    @Published private(set) var baseThumbnails: [NSImage] = []

    private static var cache: [UUID: [NSImage]] = [:]
    private static var cacheOrder: [UUID] = []
    private static let maxCacheEntries = 36

    private var currentFileID: UUID?
    private var loadTask: Task<Void, Never>?

    func loadIfNeeded(context: LayerTrimContext) {
        if currentFileID == context.fileID, !baseThumbnails.isEmpty {
            return
        }

        if let cached = Self.cache[context.fileID], !cached.isEmpty {
            currentFileID = context.fileID
            baseThumbnails = cached
            return
        }

        currentFileID = context.fileID
        baseThumbnails = []
        loadTask?.cancel()

        let fileID = context.fileID
        let source = context.source
        let mediaKind = context.mediaKind
        let sourceDuration = context.sourceDurationSeconds

        loadTask = Task(priority: ThumbnailWorkPolicy.mediaThumbnailTaskPriority) { [weak self] in
            let generated = await MediaThumbnailGenerator.makeStrip(
                source: source,
                mediaKind: mediaKind,
                sourceDurationSeconds: sourceDuration,
                frameCount: ThumbnailWorkPolicy.layerStripFrameCount(for: sourceDuration),
                maximumSize: ThumbnailWorkPolicy.layerStripThumbnailSize
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                guard self.currentFileID == fileID else { return }
                self.baseThumbnails = generated
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
}
