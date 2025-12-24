//
//  HypnogramSource.swift
//  Hypnograph
//
//  Core, mode-agnostic models for media sources and hypnogram composition.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics
import CoreImage

// MARK: - Core Data Models

enum MediaKind: String, Codable {
    case video
    case image
}

/// A single media file that we can select clips from.
/// Abstracts over local files and Apple Photos sources.
struct MediaFile: Identifiable {

    /// Where the media comes from
    enum Source {
        case url(URL)
        case photos(localIdentifier: String)
    }

    let id: UUID
    let source: Source
    let mediaKind: MediaKind
    let duration: CMTime

    // MARK: - Init

    init(
        id: UUID = UUID(),
        source: Source,
        mediaKind: MediaKind = .video,
        duration: CMTime
    ) {
        self.id = id
        self.source = source
        self.mediaKind = mediaKind
        self.duration = duration
    }

    /// Convenience init for URL-based sources (most common case)
    init(
        id: UUID = UUID(),
        url: URL,
        mediaKind: MediaKind = .video,
        duration: CMTime
    ) {
        self.init(id: id, source: .url(url), mediaKind: mediaKind, duration: duration)
    }

    // MARK: - Accessors

    /// Display name for HUD/UI
    var displayName: String {
        switch source {
        case .url(let url): return url.lastPathComponent
        case .photos(let id): return "Photos:\(id.prefix(8))"
        }
    }

    // MARK: - Asset Loading

    /// Get AVAsset for video sources (async - works for all source types)
    func loadAsset() async -> AVAsset? {
        switch source {
        case .url(let url):
            return AVURLAsset(url: url)
        case .photos(let localIdentifier):
            guard let phAsset = ApplePhotos.shared.fetchAsset(localIdentifier: localIdentifier) else {
                return nil
            }
            return await ApplePhotos.shared.requestAVAsset(for: phAsset)
        }
    }

    /// Load CIImage for still image sources
    func loadImage() async -> CIImage? {
        guard mediaKind == .image else { return nil }
        switch source {
        case .url(let url):
            return StillImageCache.ciImage(for: url)
        case .photos(let localIdentifier):
            guard let phAsset = ApplePhotos.shared.fetchAsset(localIdentifier: localIdentifier) else {
                return nil
            }
            return await ApplePhotos.shared.requestCIImage(for: phAsset)
        }
    }

    /// Load CGImage for still image sources (used by Divine for thumbnails)
    func loadCGImage() async -> CGImage? {
        guard mediaKind == .image else { return nil }
        switch source {
        case .url(let url):
            return StillImageCache.cgImage(for: url)
        case .photos(let localIdentifier):
            guard let phAsset = ApplePhotos.shared.fetchAsset(localIdentifier: localIdentifier) else {
                return nil
            }
            // Get CIImage and convert to CGImage
            guard let ciImage = await ApplePhotos.shared.requestCIImage(for: phAsset) else {
                return nil
            }
            let context = CIContext()
            return context.createCGImage(ciImage, from: ciImage.extent)
        }
    }
}

/// A specific slice (start + length) from a MediaFile.
struct VideoClip {
    let file: MediaFile
    let startTime: CMTime
    let duration: CMTime

    init(file: MediaFile, startTime: CMTime, duration: CMTime) {
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
    var effects: [Effect]
    var blendMode: String?

    /// Editable effect definition - stores parameter values per-source.
    /// This is the source of truth for the effects editor UI.
    /// When modified, `effects` should be re-instantiated from this definition.
    var effectDefinition: EffectDefinition?

    init(
        clip: VideoClip,
        transforms: [CGAffineTransform] = [],
        effects: [Effect] = [],
        blendMode: String? = nil,
        effectDefinition: EffectDefinition? = nil
    ) {
        self.clip = clip
        self.transforms = transforms
        self.effects = effects
        self.blendMode = blendMode
        self.effectDefinition = effectDefinition
    }
}
