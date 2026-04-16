//
//  ThumbnailWorkPolicy.swift
//  Hypnograph
//

import Foundation
import CoreGraphics

enum ThumbnailWorkPolicy {
    static let compositionPreviewTaskPriority: TaskPriority = .utility
    static let mediaThumbnailTaskPriority: TaskPriority = .utility

    static let compositionPreviewDelayWhilePaused: TimeInterval = 0.2
    static let compositionPreviewDelayWhilePlaying: TimeInterval = 0.75

    static let layerStripThumbnailSize = CGSize(width: 192, height: 108)

    static func compositionPreviewPersistenceDelay(isPlayerActive: Bool) -> TimeInterval {
        isPlayerActive ? compositionPreviewDelayWhilePlaying : compositionPreviewDelayWhilePaused
    }

    static func layerStripFrameCount(for sourceDurationSeconds: Double) -> Int {
        let totalDuration = max(0.2, sourceDurationSeconds)
        return min(96, max(24, Int(totalDuration.rounded(.up) * 2)))
    }
}
