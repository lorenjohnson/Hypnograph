//
//  SourcePlaybackService.swift
//  Hypnograph
//

import Foundation
import CoreImage
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import HypnoCore

enum SourcePlaybackLoadError: LocalizedError {
    case randomImageLoadFailed
    case randomVideoLoadFailed
    case photosAccessDenied
    case photosAssetMissing
    case photosImageLoadFailed
    case photosVideoLoadFailed
    case unsupportedPhotosAssetType
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .randomImageLoadFailed:
            return "Failed to load random image source."
        case .randomVideoLoadFailed:
            return "Failed to load random video source."
        case .photosAccessDenied:
            return "Apple Photos access denied. Enable Photos access in System Settings."
        case .photosAssetMissing:
            return "Could not load selected Photos asset."
        case .photosImageLoadFailed:
            return "Failed to load Apple Photos image."
        case .photosVideoLoadFailed:
            return "Failed to load selected Apple Photos video asset."
        case .unsupportedPhotosAssetType:
            return "Unsupported Photos asset type."
        case .unsupportedFileType:
            return "Unsupported file type. Pick an image or video."
        }
    }
}

final class SourcePlaybackService {
    struct LoadedSource {
        enum Kind {
            case still(CIImage)
            case video(AVAsset)
        }

        var kind: Kind
        var label: String
    }

    static let live = SourcePlaybackService()

    private var videoFrameGenerator: AVAssetImageGenerator?
    private var videoFrameGeneratorAssetID: ObjectIdentifier?
    private var lastVideoFrameImage: CIImage?

    func chooseFileSourceURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .movie]
        panel.title = "Choose Effect Studio Source"
        panel.message = "Select a single image or video as preview source."

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func loadMediaClip(_ clip: MediaClip) async -> Result<LoadedSource, SourcePlaybackLoadError> {
        if clip.file.mediaKind == .image {
            let image = await clip.file.loadImage()
            guard let image else {
                return .failure(.randomImageLoadFailed)
            }
            return .success(
                LoadedSource(kind: .still(image), label: "Random \(clip.file.displayName)")
            )
        }

        let asset = await clip.file.loadAsset()
        guard let asset else {
            return .failure(.randomVideoLoadFailed)
        }
        return .success(
            LoadedSource(kind: .video(asset), label: "Random \(clip.file.displayName)")
        )
    }

    func loadPhotosSource(identifier: String) async -> Result<LoadedSource, SourcePlaybackLoadError> {
        ApplePhotos.shared.refreshStatus()
        guard ApplePhotos.shared.status.canRead else {
            return .failure(.photosAccessDenied)
        }

        guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else {
            return .failure(.photosAssetMissing)
        }

        if asset.mediaType == .image {
            let image = await ApplePhotos.shared.requestCIImage(for: asset)
            guard let image else {
                return .failure(.photosImageLoadFailed)
            }
            return .success(
                LoadedSource(kind: .still(image), label: "Apple Photos Image")
            )
        }

        if asset.mediaType == .video {
            let avAsset = await ApplePhotos.shared.requestAVAsset(for: asset)
            guard let avAsset else {
                return .failure(.photosVideoLoadFailed)
            }
            return .success(
                LoadedSource(kind: .video(avAsset), label: "Apple Photos Video")
            )
        }

        return .failure(.unsupportedPhotosAssetType)
    }

    func loadFileSource(url: URL) -> Result<LoadedSource, SourcePlaybackLoadError> {
        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]
        let videoExts: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]

        if imageExts.contains(ext), let image = CIImage(contentsOf: url) {
            return .success(
                LoadedSource(kind: .still(image), label: "File Image: \(url.lastPathComponent)")
            )
        }

        if videoExts.contains(ext) {
            return .success(
                LoadedSource(kind: .video(AVURLAsset(url: url)), label: "File Video: \(url.lastPathComponent)")
            )
        }

        return .failure(.unsupportedFileType)
    }

    func currentSourceImage(
        time: Double,
        sourceStillImage: CIImage?,
        sourceVideoAsset: AVAsset?,
        previewSize: CGSize
    ) -> CIImage {
        if let image = sourceStillImage {
            return aspectFill(image: image, to: previewSize)
        }

        if let asset = sourceVideoAsset, let frame = videoFrame(from: asset, at: time) {
            return aspectFill(image: frame, to: previewSize)
        }

        return makeGeneratedPreviewImage(size: previewSize, time: Float(time))
    }

    func invalidateVideoFrameCache() {
        videoFrameGenerator = nil
        videoFrameGeneratorAssetID = nil
        lastVideoFrameImage = nil
    }

    private func videoFrame(from asset: AVAsset, at time: Double) -> CIImage? {
        let duration = asset.duration.seconds
        let sampleTimeSeconds: Double

        if duration.isFinite, duration > 0 {
            sampleTimeSeconds = time.truncatingRemainder(dividingBy: duration)
        } else {
            sampleTimeSeconds = 0
        }

        let sampleTime = CMTime(seconds: max(0, sampleTimeSeconds), preferredTimescale: 600)
        let assetID = ObjectIdentifier(asset)

        if videoFrameGenerator == nil || videoFrameGeneratorAssetID != assetID {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0 / 120.0, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0 / 120.0, preferredTimescale: 600)
            videoFrameGenerator = generator
            videoFrameGeneratorAssetID = assetID
            lastVideoFrameImage = nil
        }

        guard let generator = videoFrameGenerator else {
            return lastVideoFrameImage
        }
        guard let cgImage = try? generator.copyCGImage(at: sampleTime, actualTime: nil) else {
            return lastVideoFrameImage
        }

        let image = CIImage(cgImage: cgImage)
        lastVideoFrameImage = image
        return image
    }

    private func aspectFill(image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return makeGeneratedPreviewImage(size: size, time: 0)
        }

        let normalized = image.transformed(by: .init(translationX: -extent.origin.x, y: -extent.origin.y))
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaled = normalized.transformed(by: .init(scaleX: scale, y: scale))
        let x = (size.width - scaled.extent.width) * 0.5
        let y = (size.height - scaled.extent.height) * 0.5

        return scaled
            .transformed(by: .init(translationX: x, y: y))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func makeGeneratedPreviewImage(size: CGSize, time: Float) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        var image = CIImage(color: CIColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1)).cropped(to: rect)

        if let checker = CIFilter(name: "CICheckerboardGenerator") {
            checker.setValue(CIVector(x: size.width * 0.5 + CGFloat(sin(Double(time)) * 120.0), y: size.height * 0.5), forKey: "inputCenter")
            checker.setValue(CIColor(red: 0.12, green: 0.16, blue: 0.26, alpha: 1), forKey: "inputColor0")
            checker.setValue(CIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1), forKey: "inputColor1")
            checker.setValue(34.0, forKey: "inputWidth")
            checker.setValue(0.95, forKey: "inputSharpness")

            if let board = checker.outputImage?.cropped(to: rect),
               let overlay = CIFilter(name: "CISoftLightBlendMode") {
                overlay.setValue(board, forKey: kCIInputImageKey)
                overlay.setValue(image, forKey: kCIInputBackgroundImageKey)
                image = overlay.outputImage?.cropped(to: rect) ?? image
            }
        }

        if let radial = CIFilter(name: "CIRadialGradient") {
            radial.setValue(CIVector(x: size.width * 0.5, y: size.height * 0.5), forKey: "inputCenter")
            radial.setValue(size.height * 0.10, forKey: "inputRadius0")
            radial.setValue(size.height * 0.48, forKey: "inputRadius1")
            radial.setValue(CIColor(red: 1.0, green: 0.35, blue: 0.1, alpha: 0.32), forKey: "inputColor0")
            radial.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")

            if let glow = radial.outputImage?.cropped(to: rect),
               let comp = CIFilter(name: "CISourceOverCompositing") {
                comp.setValue(glow, forKey: kCIInputImageKey)
                comp.setValue(image, forKey: kCIInputBackgroundImageKey)
                image = comp.outputImage?.cropped(to: rect) ?? image
            }
        }

        return image
    }
}
