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

        // Get AVAsset - either from URL or Photos
        let asset: AVAsset
        switch file.source {
        case .url(let url):
            asset = AVURLAsset(url: url)
        case .photos(let localIdentifier):
            guard let phAsset = ApplePhotos.shared.fetchAsset(localIdentifier: localIdentifier),
                  let avAsset = await ApplePhotos.shared.requestAVAsset(for: phAsset) else {
                return .failure(.sourceLoadFailed(
                    index: -1,
                    name: file.displayName,
                    underlying: NSError(domain: "SourceLoader", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load video from Photos"])
                ))
            }
            asset = avAsset
        }

        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)

            guard let videoTrack = videoTracks.first else {
                return .failure(.noVideoTrack(name: file.displayName))
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let timeRange = try await videoTrack.load(.timeRange)

            // Convert AVFoundation transform to CIImage coordinate system
            let ciTransform = ImageUtils.convertTransformForCIImage(preferredTransform, naturalSize: naturalSize)

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let audioTrack = audioTracks.first

            return .success(LoadedSource(
                asset: asset,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                duration: timeRange.duration,
                naturalSize: naturalSize,
                transform: ciTransform,
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

        // Get CIImage - either from URL or Photos
        let ciImage: CIImage?
        switch file.source {
        case .url(let url):
            ciImage = StillImageCache.ciImage(for: url)
        case .photos(let localIdentifier):
            guard let phAsset = ApplePhotos.shared.fetchAsset(localIdentifier: localIdentifier) else {
                return .failure(.imageLoadFailed(
                    name: file.displayName,
                    underlying: NSError(domain: "SourceLoader", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Photos asset not found"])
                ))
            }
            ciImage = await ApplePhotos.shared.requestCIImage(for: phAsset)
        }

        guard let ciImage = ciImage else {
            return .failure(.imageLoadFailed(
                name: file.displayName,
                underlying: NSError(domain: "SourceLoader", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode image"])
            ))
        }

        let extent = ciImage.extent

        // For Photos images, we need a dummy asset - use an empty composition
        let dummyAsset: AVAsset
        switch file.source {
        case .url(let url):
            dummyAsset = AVURLAsset(url: url)
        case .photos:
            dummyAsset = AVMutableComposition()
        }

        return .success(LoadedSource(
            asset: dummyAsset,
            videoTrack: nil,
            audioTrack: nil,
            duration: source.clip.duration,
            naturalSize: CGSize(width: extent.width, height: extent.height),
            transform: .identity,  // CIImage orientation already applied
            isStillImage: true,
            ciImage: ciImage
        ))
    }
}

