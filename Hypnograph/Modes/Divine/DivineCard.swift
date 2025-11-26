//  DivineCard.swift
//  Hypnograph
//
//  Model for a single Divine-mode "card" (tarot-style still / clip).

import Foundation
import CoreGraphics
import CoreMedia

struct DivineCard: Identifiable {
    let id: UUID
    var clip: VideoClip
    var cgImage: CGImage?
    var isRevealed: Bool
    var isPlaying: Bool
    var isFlipped: Bool
    var offset: CGSize
    var dragOffset: CGSize
    var lastSnapshotTime: CMTime?

    init(
        id: UUID = UUID(),
        clip: VideoClip,
        cgImage: CGImage? = nil,
        isRevealed: Bool = false,
        isPlaying: Bool = false,
        isFlipped: Bool = false,
        offset: CGSize = .zero,
        dragOffset: CGSize = .zero,
        lastSnapshotTime: CMTime? = nil
    ) {
        self.id = id
        self.clip = clip
        self.cgImage = cgImage
        self.isRevealed = isRevealed
        self.isPlaying = isPlaying
        self.isFlipped = isFlipped
        self.offset = offset
        self.dragOffset = dragOffset
        self.lastSnapshotTime = lastSnapshotTime
    }
}

// Shared helper for offset math used by Divine mode views / logic.
extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}
