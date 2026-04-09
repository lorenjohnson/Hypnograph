//
//  SequencePanel.swift
//  Hypnograph
//

import SwiftUI
import UniformTypeIdentifiers
import HypnoCore

struct CompositionEntry: Identifiable {
    let index: Int
    let composition: Composition
    let isCurrent: Bool

    var id: UUID { composition.id }

    var thumbnailImage: NSImage? {
        CompositionPreviewImageCodec.decodeImage(from: composition.thumbnail ?? composition.snapshot)
    }
}

struct SequenceLaneView: View {
    let compositionEntries: [CompositionEntry]
    @Binding var draggedCompositionID: UUID?
    var onJumpToComposition: (Int) -> Void
    var onDeleteCompositionEntry: (Int) -> Void
    var onMoveComposition: (UUID, UUID) -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat?

    private let clipSpacing: CGFloat = 1
    private let edgeOverlayWidth: CGFloat = 34
    private let laneTrackHeight: CGFloat = 74
    private let edgeArrowWidth: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            let laneWidth = viewportWidth(in: geometry.size.width)
            let maxOffset = maximumScrollOffset(laneWidth: laneWidth)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: laneTrackHeight)

                clipsStrip(laneWidth: laneWidth)
                .padding(.vertical, 1)
                .padding(.horizontal, 1)
                .frame(width: totalContentWidth, alignment: .leading)
                .offset(x: -scrollOffset)
                .frame(width: laneWidth, alignment: .leading)
                .clipped()

                HStack(spacing: 0) {
                    edgeScrollButton(
                        systemName: "chevron.left",
                        direction: .left,
                        disabled: scrollOffset <= 0.5
                    ) {
                        scrollBy(-laneWidth * 0.72, laneWidth: laneWidth)
                    }

                    Spacer(minLength: 0)

                    edgeScrollButton(
                        systemName: "chevron.right",
                        direction: .right,
                        disabled: scrollOffset >= maxOffset - 0.5
                    ) {
                        scrollBy(laneWidth * 0.72, laneWidth: laneWidth)
                    }
                }
                .frame(width: laneWidth, height: laneTrackHeight)
                .zIndex(5)
            }
            .onAppear {
                clampScrollOffset(laneWidth: laneWidth)
                ensureCurrentCompositionVisible(laneWidth: laneWidth, animated: false)
            }
            .onChange(of: compositionEntries.map(\.id)) { _, _ in
                clampScrollOffset(laneWidth: laneWidth)
                ensureCurrentCompositionVisible(laneWidth: laneWidth, animated: false)
            }
            .onChange(of: currentCompositionID) { _, currentID in
                guard currentID != nil else { return }
                ensureCurrentCompositionVisible(laneWidth: laneWidth, animated: true)
            }
            .gesture(scrollGesture(laneWidth: laneWidth))
        }
        .frame(height: laneTrackHeight + 2)
    }

    private func baseClipWidth(for entry: CompositionEntry) -> CGFloat {
        let seconds = max(0.1, entry.composition.targetDuration.seconds)
        let scaled = 14 + (seconds * 2.1)
        return CGFloat(min(max(scaled, 28), 76))
    }

    private func clipWidth(for entry: CompositionEntry) -> CGFloat {
        baseClipWidth(for: entry)
    }

    private var currentCompositionID: UUID? {
        compositionEntries.first(where: \.isCurrent)?.id
    }

    private var totalContentWidth: CGFloat {
        let widths = compositionEntries.map(baseClipWidth(for:))
        return widths.reduce(0, +) + (clipSpacing * CGFloat(max(widths.count - 1, 0))) + 2
    }

    private func viewportWidth(in totalWidth: CGFloat) -> CGFloat {
        max(120, totalWidth)
    }

    private func maximumScrollOffset(laneWidth: CGFloat) -> CGFloat {
        max(totalContentWidth - laneWidth, 0)
    }

    private func clampedOffset(_ proposed: CGFloat, laneWidth: CGFloat) -> CGFloat {
        min(max(0, proposed), maximumScrollOffset(laneWidth: laneWidth))
    }

    private func clampScrollOffset(laneWidth: CGFloat) {
        scrollOffset = clampedOffset(scrollOffset, laneWidth: laneWidth)
    }

    private func scrollBy(_ delta: CGFloat, laneWidth: CGFloat) {
        withAnimation(.easeInOut(duration: 0.18)) {
            scrollOffset = clampedOffset(scrollOffset + delta, laneWidth: laneWidth)
        }
    }

    private func ensureCurrentCompositionVisible(laneWidth: CGFloat, animated: Bool) {
        guard let currentCompositionID,
              let index = compositionEntries.firstIndex(where: { $0.id == currentCompositionID }) else {
            return
        }

        let clipStart = xPosition(for: index)
        let clipEnd = clipStart + clipWidth(for: compositionEntries[index])
        let leftVisible = scrollOffset + edgeOverlayWidth
        let rightVisible = scrollOffset + laneWidth - edgeOverlayWidth

        let targetOffset: CGFloat
        if clipStart < leftVisible {
            targetOffset = clipStart - edgeOverlayWidth
        } else if clipEnd > rightVisible {
            targetOffset = clipEnd - laneWidth + edgeOverlayWidth
        } else {
            targetOffset = scrollOffset
        }

        let clamped = clampedOffset(targetOffset, laneWidth: laneWidth)
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollOffset = clamped
            }
        } else {
            scrollOffset = clamped
        }
    }

    private func xPosition(for index: Int) -> CGFloat {
        guard index > 0 else { return 1 }
        let priorWidths = compositionEntries[..<index].map(baseClipWidth(for:)).reduce(0, +)
        let priorSpacing = CGFloat(index) * clipSpacing
        return 1 + priorWidths + priorSpacing
    }

    @ViewBuilder
    private func clipsStrip(laneWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: clipSpacing) {
            ForEach(compositionEntries) { entry in
                clipView(for: entry, laneWidth: laneWidth)
            }
        }
    }

    @ViewBuilder
    private func clipView(for entry: CompositionEntry, laneWidth: CGFloat) -> some View {
        SequenceClipView(
            entry: entry,
            width: clipWidth(for: entry),
            height: laneTrackHeight,
            draggedCompositionID: $draggedCompositionID,
            onJump: {
                onJumpToComposition(entry.index)
            },
            onDelete: {
                onDeleteCompositionEntry(entry.index)
            }
        )
        .onDrop(
            of: [UTType.text],
            delegate: SequenceCompositionReorderDropDelegate(
                targetID: entry.id,
                draggedCompositionID: $draggedCompositionID,
                moveComposition: onMoveComposition
            )
        )
    }

    private enum EdgeDirection {
        case left
        case right
    }

    private func edgeScrollButton(systemName: String, direction: EdgeDirection, disabled: Bool, action: @escaping () -> Void) -> some View {
        let gradient = LinearGradient(
            colors: [
                Color.black.opacity(disabled ? 0.05 : 0.32),
                Color.black.opacity(disabled ? 0.02 : 0.12),
                Color.black.opacity(0.0)
            ],
            startPoint: direction == .left ? .leading : .trailing,
            endPoint: direction == .left ? .trailing : .leading
        )

        return Button(action: action) {
            ZStack(alignment: direction == .left ? .leading : .trailing) {
                gradient

                Image(systemName: systemName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(disabled ? Color.white.opacity(0.16) : Color.white.opacity(0.86))
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                    .frame(width: edgeArrowWidth, height: laneTrackHeight)
                    .offset(x: direction == .left ? -6 : 6)
            }
            .frame(width: edgeOverlayWidth, height: laneTrackHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .disabled(disabled)
    }

    private func scrollGesture(laneWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = scrollOffset
                }
                let base = dragStartOffset ?? scrollOffset
                scrollOffset = clampedOffset(base - value.translation.width, laneWidth: laneWidth)
            }
            .onEnded { value in
                let base = dragStartOffset ?? scrollOffset
                let projectedOffset = clampedOffset(base - value.predictedEndTranslation.width, laneWidth: laneWidth)
                dragStartOffset = nil
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 34)) {
                    scrollOffset = projectedOffset
                }
            }
    }
}

private struct SequenceCompositionReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedCompositionID: UUID?
    let moveComposition: (UUID, UUID) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggedCompositionID else { return }
        guard sourceID != targetID else { return }
        moveComposition(sourceID, targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedCompositionID = nil
        return true
    }

    func dropExited(info: DropInfo) {
    }
}

struct SequenceClipView: View {
    let entry: CompositionEntry
    let width: CGFloat
    let height: CGFloat
    @Binding var draggedCompositionID: UUID?
    let onJump: () -> Void
    let onDelete: () -> Void

    @State private var isHoveringReorderHandle = false
    @State private var isHoveringClip = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ThumbnailView(image: entry.thumbnailImage)
                .frame(width: width, height: max(1, height))
                .clipped()

            if entry.isCurrent {
                Rectangle()
                    .fill(Color.blue.opacity(0.95))
                    .frame(height: 2.5)
            }

            reorderHandle
                .padding(.horizontal, 1)
                .padding(.bottom, 1)
        }
        .opacity(clipOpacity)
        .frame(width: width, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.35)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHoveringClip = hovering
                isHoveringReorderHandle = hovering
            }
        }
        .onTapGesture {
            onJump()
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Composition", systemImage: "trash")
            }
        }
    }

    private var clipOpacity: Double {
        if entry.isCurrent { return 1.0 }
        if isHoveringClip { return 0.76 }
        return 0.56
    }

    private var reorderHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: width - 2, height: 11)
            .overlay(alignment: .center) {
                if isHoveringReorderHandle {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.34))
                        .frame(width: min(34, max(14, width - 10)), height: 2)
                        .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                }
            }
            .contentShape(Rectangle())
            .onDrag(
                {
                    draggedCompositionID = entry.id
                    return NSItemProvider(object: entry.id.uuidString as NSString)
                },
                preview: {
                    dragPreview
                }
            )
    }

    private var dragPreview: some View {
        ThumbnailView(image: entry.thumbnailImage)
            .frame(width: width, height: max(28, height - 6))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
