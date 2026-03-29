import SwiftUI
import AVFoundation
import AppKit
import HypnoCore

struct ClipTrimContext: Equatable {
    let layerIndex: Int
    let fileID: UUID
    let source: MediaSource
    let clipLabel: String
    let totalDurationSeconds: Double
    let maxSelectionDurationSeconds: Double
    let selectedRangeSeconds: ClosedRange<Double>

    var stableID: String {
        "\(layerIndex)-\(fileID.uuidString)"
    }
}

struct ClipTrimPanelView: View {
    let contexts: [ClipTrimContext]
    let onCommit: (Int, ClosedRange<Double>) -> Void

    var body: some View {
        if !contexts.isEmpty {
            VStack(spacing: 6) {
                ForEach(contexts, id: \.stableID) { context in
                    ClipTrimRangeStrip(
                        context: context,
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

private struct ClipTrimRangeStrip: View {
    let context: ClipTrimContext
    let onCommit: (ClosedRange<Double>) -> Void

    @StateObject private var thumbnailStore = ClipTrimThumbnailStripStore()
    @State private var draftRange: ClosedRange<Double>

    private let trackHeight: CGFloat = 38
    private let handleWidth: CGFloat = 10
    private let minimumDurationSeconds: Double = 0.1

    init(
        context: ClipTrimContext,
        onCommit: @escaping (ClosedRange<Double>) -> Void
    ) {
        self.context = context
        self.onCommit = onCommit
        _draftRange = State(initialValue: context.selectedRangeSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(context.clipLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 10)

                Text(formatTime(activeRange.upperBound - activeRange.lowerBound))
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

                    ClipTrimInteractionOverlay(
                        range: $draftRange,
                        totalDurationSeconds: safeTotalSeconds,
                        maxSelectionDurationSeconds: maxWindowSeconds,
                        minimumDurationSeconds: minimumWindowSeconds,
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

            HStack {
                Text("0s")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Text(formatTime(safeTotalSeconds))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
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
        .saturation(0.9)
        .contrast(1.02)
        .opacity(0.76)
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

private struct ClipTrimInteractionOverlay: NSViewRepresentable {
    @Binding var range: ClosedRange<Double>
    let totalDurationSeconds: Double
    let maxSelectionDurationSeconds: Double
    let minimumDurationSeconds: Double
    let onCommit: (ClosedRange<Double>) -> Void

    func makeNSView(context: Context) -> ClipTrimInteractionView {
        let view = ClipTrimInteractionView()
        view.onRangeChanged = { newRange in
            range = newRange
        }
        view.onRangeCommitted = { committedRange in
            onCommit(committedRange)
        }
        return view
    }

    func updateNSView(_ nsView: ClipTrimInteractionView, context: Context) {
        nsView.totalDurationSeconds = totalDurationSeconds
        nsView.maxSelectionDurationSeconds = maxSelectionDurationSeconds
        nsView.minimumDurationSeconds = minimumDurationSeconds
        nsView.currentRange = range
        nsView.onRangeChanged = { newRange in
            range = newRange
        }
        nsView.onRangeCommitted = { committedRange in
            onCommit(committedRange)
        }
    }
}

private final class ClipTrimInteractionView: NSView {
    private enum DragMode {
        case leadingHandle
        case trailingHandle
        case window
    }

    var totalDurationSeconds: Double = 0.1
    var maxSelectionDurationSeconds: Double = 0.1
    var minimumDurationSeconds: Double = 0.1
    var currentRange: ClosedRange<Double> = 0...0.1
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

private final class ClipTrimThumbnailStripStore: ObservableObject {
    @Published private(set) var thumbnails: [NSImage] = []

    private static var cache: [UUID: [NSImage]] = [:]
    private static var cacheOrder: [UUID] = []
    private static let maxCacheEntries = 36

    private var currentFileID: UUID?
    private var loadTask: Task<Void, Never>?

    func loadIfNeeded(context: ClipTrimContext) {
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
        let duration = context.totalDurationSeconds

        loadTask = Task(priority: .utility) { [weak self] in
            let generated = await Self.generateThumbnails(source: source, durationSeconds: duration)
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
        durationSeconds: Double
    ) async -> [NSImage] {
        guard let asset = await resolveAsset(for: source) else { return [] }

        let totalDuration = max(0.2, durationSeconds)
        let frameCount = min(10, max(5, Int((totalDuration / 2.0).rounded(.up))))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 140, height: 84)
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
}
