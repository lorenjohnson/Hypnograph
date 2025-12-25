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

// MARK: - Codable Helpers for Core Types

/// Codable wrapper for CMTime (stores as seconds)
struct CodableCMTime: Codable {
    let seconds: Double

    init(_ time: CMTime) {
        self.seconds = time.seconds.isFinite ? time.seconds : 0
    }

    var cmTime: CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}

/// Codable wrapper for CGAffineTransform
struct CodableCGAffineTransform: Codable {
    let a, b, c, d, tx, ty: CGFloat

    init(_ transform: CGAffineTransform) {
        self.a = transform.a
        self.b = transform.b
        self.c = transform.c
        self.d = transform.d
        self.tx = transform.tx
        self.ty = transform.ty
    }

    var transform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
}

/// A single media file that we can select clips from.
/// Abstracts over local files and Apple Photos sources.
struct MediaFile: Identifiable, Codable {

    /// Where the media comes from
    enum Source: Codable {
        case url(URL)
        case photos(localIdentifier: String)

        private enum CodingKeys: String, CodingKey {
            case type, path, localIdentifier
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "url":
                let path = try container.decode(String.self, forKey: .path)
                self = .url(URL(fileURLWithPath: path))
            case "photos":
                let id = try container.decode(String.self, forKey: .localIdentifier)
                self = .photos(localIdentifier: id)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown source type: \(type)")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .url(let url):
                try container.encode("url", forKey: .type)
                try container.encode(url.path, forKey: .path)
            case .photos(let id):
                try container.encode("photos", forKey: .type)
                try container.encode(id, forKey: .localIdentifier)
            }
        }
    }

    let id: UUID
    let source: Source
    let mediaKind: MediaKind
    let duration: CMTime

    private enum CodingKeys: String, CodingKey {
        case id, source, mediaKind, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        source = try container.decode(Source.self, forKey: .source)
        mediaKind = try container.decode(MediaKind.self, forKey: .mediaKind)
        let codableDuration = try container.decode(CodableCMTime.self, forKey: .duration)
        duration = codableDuration.cmTime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(mediaKind, forKey: .mediaKind)
        try container.encode(CodableCMTime(duration), forKey: .duration)
    }

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
struct VideoClip: Codable {
    let file: MediaFile
    let startTime: CMTime
    let duration: CMTime

    private enum CodingKeys: String, CodingKey {
        case file, startTime, duration
    }

    init(file: MediaFile, startTime: CMTime, duration: CMTime) {
        self.file = file
        self.startTime = startTime
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decode(MediaFile.self, forKey: .file)
        startTime = try container.decode(CodableCMTime.self, forKey: .startTime).cmTime
        duration = try container.decode(CodableCMTime.self, forKey: .duration).cmTime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(file, forKey: .file)
        try container.encode(CodableCMTime(startTime), forKey: .startTime)
        try container.encode(CodableCMTime(duration), forKey: .duration)
    }
}

// MARK: - Hypnogram core models

/// One source of a hypnogram: clip + transforms + effects + blend mode.
/// Transforms are user-applied (rotation, scale, etc.) - metadata transforms are computed at runtime.
struct HypnogramSource: Codable {
    var clip: VideoClip
    /// User-applied transforms (rotation, scale, translation). Applied after metadata orientation correction.
    var transforms: [CGAffineTransform]
    var blendMode: String?

    /// The effect chain for this source - contains definitions and handles instantiation/application.
    /// Use effectChain.apply() to apply effects. Always non-nil (can be empty chain).
    var effectChain: EffectChain

    private enum CodingKeys: String, CodingKey {
        case clip, transforms, blendMode, effectChain
    }

    init(
        clip: VideoClip,
        transforms: [CGAffineTransform] = [],
        blendMode: String? = nil,
        effectChain: EffectChain? = nil
    ) {
        self.clip = clip
        self.transforms = transforms
        self.blendMode = blendMode
        self.effectChain = effectChain ?? EffectChain()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clip = try container.decode(VideoClip.self, forKey: .clip)
        let codableTransforms = try container.decodeIfPresent([CodableCGAffineTransform].self, forKey: .transforms) ?? []
        transforms = codableTransforms.map { $0.transform }
        blendMode = try container.decodeIfPresent(String.self, forKey: .blendMode)
        effectChain = try container.decodeIfPresent(EffectChain.self, forKey: .effectChain) ?? EffectChain()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clip, forKey: .clip)
        try container.encode(transforms.map { CodableCGAffineTransform($0) }, forKey: .transforms)
        try container.encodeIfPresent(blendMode, forKey: .blendMode)
        try container.encode(effectChain, forKey: .effectChain)
    }
}
