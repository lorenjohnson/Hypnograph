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

struct SequencePanel: View {
    let compositionEntries: [CompositionEntry]
    var onJumpToComposition: (Int) -> Void
    var onDeleteCompositionEntry: (Int) -> Void
    var onMoveComposition: (UUID, UUID) -> Void

    @State private var draggedCompositionID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if compositionEntries.isEmpty {
                        Text("No compositions yet")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(.body, design: .monospaced))
                        .padding(.vertical, 40)
                } else {
                    ForEach(compositionEntries) { entry in
                        CompositionRowView(
                            entry:  entry,
                            onJump: {
                                onJumpToComposition(entry.index)
                            },
                            onDelete: {
                                onDeleteCompositionEntry(entry.index)
                            }
                        )
                        .contentShape(Rectangle())
                        .onDrag {
                            draggedCompositionID = entry.id
                            return NSItemProvider(object: entry.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: SequenceCompositionReorderDropDelegate(
                                targetID: entry.id,
                                draggedCompositionID: $draggedCompositionID,
                                moveComposition: onMoveComposition
                            )
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
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

struct CompositionRowView: View {
    let entry: CompositionEntry
    let onJump: () -> Void
    let onDelete: () -> Void

    private var layerCountText: String {
        let count = entry.composition.layers.count
        return "\(count) layer\(count == 1 ? "" : "s")"
    }

    private var durationText: String {
        let seconds = max(0.1, entry.composition.targetDuration.seconds)
        let rounded = (seconds * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "\(Int(rounded.rounded()))s"
        }
        return String(format: "%.1fs", rounded)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ThumbnailView(image: entry.thumbnailImage)
                .frame(width: 60, height: 60)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text("Composition \(entry.index + 1)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)

                Text("\(layerCountText) • \(durationText)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))

                Text(entry.composition.createdAt, style: .date)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(entry.isCurrent ? Color.blue.opacity(0.16) : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            onJump()
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Composition", systemImage: "trash")
            }
        }
    }
}
