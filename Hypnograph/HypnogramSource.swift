//
//  Models.swift
//  Hypnograph
//
//  Core, mode-agnostic models.
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import CoreMedia
import CoreGraphics

// MARK: - Core Data Models

enum MediaKind: String, Codable {
    case video
    case image
}

/// A single video file on disk that we can select clips from.
struct VideoFile: Identifiable {
    let id: UUID
    let url: URL
    let mediaKind: MediaKind
    let duration: CMTime

    init(
        id: UUID = UUID(),
        url: URL,
        mediaKind: MediaKind = .video,
        duration: CMTime
    ) {
        self.id = id
        self.url = url
        self.mediaKind = mediaKind
        self.duration = duration
    }
}

/// A specific slice (start + length) from a VideoFile.
struct VideoClip {
    let file: VideoFile
    let startTime: CMTime
    let duration: CMTime

    init(file: VideoFile, startTime: CMTime, duration: CMTime) {
        self.file = file
        self.startTime = startTime
        self.duration = duration
    }
}

// MARK: - Hypnogram core models

/// One source of a hypnogram: clip + transform + effects.
///
/// NOTE: any mode-specific per-source data (e.g. blend modes for Montage)
/// lives in `HypnogramMode.sourceData`, *not* here.
struct HypnogramSource {
    var clip: VideoClip
    var transform: CGAffineTransform
    var effects: [RenderHook]

    init(
        clip: VideoClip,
        transform: CGAffineTransform = .identity,
        effects: [RenderHook] = []
    ) {
        self.clip = clip
        self.transform = transform
        self.effects = effects
    }
}
