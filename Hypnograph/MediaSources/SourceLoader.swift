//
//  SourceLoader.swift
//  Hypnograph
//
//  Loads and validates video/image sources with graceful error handling
//

import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import AppKit

/// Represents a successfully loaded source ready for composition
struct LoadedSource {
    let asset: AVAsset
    let videoTrack: AVAssetTrack?  // nil for still images (they use ciImage instead)
    let audioTrack: AVAssetTrack?  // nil if no audio
    let duration: CMTime
    let naturalSize: CGSize
    let transform: CGAffineTransform  // embedded orientation from EXIF/metadata
    let isStillImage: Bool
    let ciImage: CIImage?  // For still images - the actual image data
}

/// Loads sources with fault tolerance
final class SourceLoader {

    // MARK: - Loading

    /// Load a source, return error if it fails (never crashes)
    func load(source: HypnogramSource) async -> Result<LoadedSource, RenderError> {
        let file = source.clip.file

        switch file.mediaKind {
        case .image:
            return await loadImageSource(source: source)
        case .video:
            return await loadVideoSource(source: source)
        }
    }
    
    // MARK: - Video Loading

    private func loadVideoSource(source: HypnogramSource) async -> Result<LoadedSource, RenderError> {
        let file = source.clip.file
        let asset = file.asset

        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)

            guard let videoTrack = videoTracks.first else {
                return .failure(.noVideoTrack(name: file.displayName))
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let timeRange = try await videoTrack.load(.timeRange)

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let audioTrack = audioTracks.first

            return .success(LoadedSource(
                asset: asset,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                duration: timeRange.duration,
                naturalSize: naturalSize,
                transform: preferredTransform,
                isStillImage: false,
                ciImage: nil
            ))
        } catch {
            return .failure(.sourceLoadFailed(index: -1, name: file.displayName, underlying: error))
        }
    }

    // MARK: - Image Loading

    private func loadImageSource(source: HypnogramSource) async -> Result<LoadedSource, RenderError> {
        let file = source.clip.file

        guard let ciImage = file.loadImage() else {
            return .failure(.imageLoadFailed(
                name: file.displayName,
                underlying: NSError(domain: "SourceLoader", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode image"])
            ))
        }

        let extent = ciImage.extent

        return .success(LoadedSource(
            asset: file.asset,  // dummy asset for images
            videoTrack: nil,
            audioTrack: nil,
            duration: source.clip.duration,
            naturalSize: CGSize(width: extent.width, height: extent.height),
            transform: .identity,  // CIImage orientation already applied by StillImageCache
            isStillImage: true,
            ciImage: ciImage
        ))
    }
}

