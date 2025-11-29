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

/// One source of a hypnogram: clip + transforms + effects + blend mode.
/// Transforms are user-applied (rotation, scale, etc.) - metadata transforms are computed at runtime.
struct HypnogramSource {
    var clip: VideoClip
    /// User-applied transforms (rotation, scale, translation). Applied after metadata orientation correction.
    var transforms: [CGAffineTransform]
    var effects: [RenderHook]
    var blendMode: String?

    init(
        clip: VideoClip,
        transforms: [CGAffineTransform] = [],
        effects: [RenderHook] = [],
        blendMode: String? = nil
    ) {
        self.clip = clip
        self.transforms = transforms
        self.effects = effects
        self.blendMode = blendMode
    }
}
