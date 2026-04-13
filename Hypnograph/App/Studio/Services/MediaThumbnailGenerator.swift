//
//  MediaThumbnailGenerator.swift
//  Hypnograph
//

import AppKit
import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import HypnoCore

enum MediaThumbnailGenerator {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func makeImage(
        source: MediaSource,
        mediaKind: MediaKind,
        sourceDurationSeconds: Double,
        time: CMTime,
        maximumSize: CGSize
    ) async -> NSImage? {
        guard let cgImage = await makeCGImage(
            source: source,
            mediaKind: mediaKind,
            sourceDurationSeconds: sourceDurationSeconds,
            time: time,
            maximumSize: maximumSize
        ) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: CGSize(width: cgImage.width, height: cgImage.height)
        )
    }

    static func makeCGImage(
        source: MediaSource,
        mediaKind: MediaKind,
        sourceDurationSeconds: Double,
        time: CMTime,
        maximumSize: CGSize? = nil
    ) async -> CGImage? {
        let file = MediaFile(
            source: source,
            mediaKind: mediaKind,
            duration: CMTime(seconds: max(0.1, sourceDurationSeconds), preferredTimescale: 600)
        )

        switch mediaKind {
        case .image:
            switch source {
            case .url(let url):
                return StillImageCache.cgImage(for: url)
            case .external:
                guard let ciImage = await file.loadImage() else { return nil }
                return ciContext.createCGImage(ciImage, from: ciImage.extent)
            }

        case .video:
            guard let asset = await file.loadAsset() else { return nil }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            if let maximumSize, maximumSize != .zero {
                generator.maximumSize = maximumSize
            }

            let requestedTime = time.isValid && time.seconds.isFinite ? time : .zero
            return try? generator.copyCGImage(at: requestedTime, actualTime: nil)
        }
    }

    static func makeStrip(
        source: MediaSource,
        mediaKind: MediaKind,
        sourceDurationSeconds: Double,
        frameCount: Int,
        maximumSize: CGSize
    ) async -> [NSImage] {
        let cappedFrameCount = max(1, frameCount)

        if mediaKind == .image {
            guard let image = await makeImage(
                source: source,
                mediaKind: mediaKind,
                sourceDurationSeconds: sourceDurationSeconds,
                time: .zero,
                maximumSize: maximumSize
            ) else {
                return []
            }
            return Array(repeating: image, count: cappedFrameCount)
        }

        let file = MediaFile(
            source: source,
            mediaKind: mediaKind,
            duration: CMTime(seconds: max(0.1, sourceDurationSeconds), preferredTimescale: 600)
        )
        guard let asset = await file.loadAsset() else { return [] }

        let totalDuration = max(0.2, sourceDurationSeconds)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.12, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)

        var images: [NSImage] = []
        images.reserveCapacity(cappedFrameCount)

        for index in 0..<cappedFrameCount {
            if Task.isCancelled {
                return []
            }

            let fraction = (Double(index) + 0.5) / Double(cappedFrameCount)
            let sampleSeconds = min(totalDuration - 0.033, max(0, totalDuration * fraction))
            let sampleTime = CMTime(seconds: sampleSeconds, preferredTimescale: 600)

            if let cgImage = try? generator.copyCGImage(at: sampleTime, actualTime: nil) {
                images.append(
                    NSImage(
                        cgImage: cgImage,
                        size: CGSize(width: cgImage.width, height: cgImage.height)
                    )
                )
            }
        }

        if images.isEmpty,
           let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            images.append(
                NSImage(
                    cgImage: cgImage,
                    size: CGSize(width: cgImage.width, height: cgImage.height)
                )
            )
        }

        return images
    }
}
