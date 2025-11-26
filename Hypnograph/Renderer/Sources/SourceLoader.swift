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
import ImageIO
import UniformTypeIdentifiers
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
        let url = source.clip.file.url
        
        print("📦 SourceLoader: Loading \(url.lastPathComponent)...")
        
        // Determine if this is an image or video
        let isImage = isImageFile(url)
        
        if isImage {
            return await loadImageSource(source: source)
        } else {
            return await loadVideoSource(source: source)
        }
    }
    
    // MARK: - Video Loading
    
    private func loadVideoSource(source: HypnogramSource) async -> Result<LoadedSource, RenderError> {
        let url = source.clip.file.url
        let asset = AVURLAsset(url: url)

        do {
            // Load video tracks asynchronously
            let videoTracks = try await asset.loadTracks(withMediaType: .video)

            guard let videoTrack = videoTracks.first else {
                return .failure(.noVideoTrack(url: url))
            }

            // Load video track properties
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let timeRange = try await videoTrack.load(.timeRange)

            // Load audio track if available
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let audioTrack = audioTracks.first  // nil if no audio

            let loaded = LoadedSource(
                asset: asset,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                duration: timeRange.duration,
                naturalSize: naturalSize,
                transform: preferredTransform,
                isStillImage: false,
                ciImage: nil
            )

            let audioStatus = audioTrack != nil ? "with audio" : "no audio"
            print("✅ SourceLoader: Loaded video \(url.lastPathComponent) - \(naturalSize) @ \(timeRange.duration.seconds)s (\(audioStatus))")
            return .success(loaded)

        } catch {
            return .failure(.sourceLoadFailed(index: -1, url: url, underlying: error))
        }
    }
    
    // MARK: - Image Loading

    private func loadImageSource(source: HypnogramSource) async -> Result<LoadedSource, RenderError> {
        let url = source.clip.file.url

        // Load the image using StillImageCache
        guard let ciImage = StillImageCache.ciImage(for: url) else {
            return .failure(.imageLoadFailed(
                url: url,
                underlying: NSError(domain: "SourceLoader", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode image"])
            ))
        }

        // Get image dimensions
        let extent = ciImage.extent
        let naturalSize = CGSize(width: extent.width, height: extent.height)

        // Use the clip's duration (from VideoFile)
        let duration = source.clip.duration

        // Create a dummy asset (not used, but required for LoadedSource)
        let asset = AVURLAsset(url: url)

        // Get orientation from EXIF if available
        let transform = getImageTransform(ciImage: ciImage)

        let loaded = LoadedSource(
            asset: asset,
            videoTrack: nil,  // No video track for still images
            audioTrack: nil,  // No audio for still images
            duration: duration,
            naturalSize: naturalSize,
            transform: transform,
            isStillImage: true,
            ciImage: ciImage
        )

        print("✅ SourceLoader: Loaded image \(url.lastPathComponent) - \(naturalSize) @ \(duration.seconds)s")
        return .success(loaded)
    }

    // MARK: - Image Transform

    private func getImageTransform(ciImage: CIImage) -> CGAffineTransform {
        // CIImage with applyOrientationProperty already has orientation applied
        // So we return identity transform
        return .identity
    }
    
    // MARK: - Helpers
    
    private func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }
}

