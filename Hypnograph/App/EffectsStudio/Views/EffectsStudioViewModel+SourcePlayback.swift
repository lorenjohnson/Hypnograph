//
//  EffectsStudioViewModel+SourcePlayback.swift
//  Hypnograph
//

import Foundation
import CoreImage
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import HypnoCore

extension EffectsStudioViewModel {
    var runtimeEffectsDirectoryURL: URL {
        HypnoCoreConfig.shared.runtimeEffectsDirectory
    }

    func chooseFileSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .movie]
        panel.title = "Choose Effect Studio Source"
        panel.message = "Select a single image or video as preview source."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFileSource(url: url, persist: true)
    }

    func useGeneratedSample() {
        sourceStillImage = nil
        sourceVideoAsset = nil
        invalidateVideoFrameCache()
        resetPreviewHistory()
        inputSourceLabel = "Generated Sample"
        persistLastSourceSample()
        updateTimelineDurationFromCurrentSource()
        renderPreview()
    }

    func loadRandomSource(from library: MediaLibrary, preferredLength: Double = 8.0) {
        guard let clip = library.randomClip(clipLength: preferredLength) else {
            compileLog = "No source available in active libraries for random pick. Using generated sample."
            useGeneratedSample()
            return
        }
        loadMediaClip(clip)
    }

    func restoreInitialSource(from library: MediaLibrary, preferredLength: Double = 8.0) {
        let persisted = settingsStore.value
        guard let kind = persisted.lastSourceKind else {
            loadRandomSource(from: library, preferredLength: preferredLength)
            return
        }

        switch kind {
        case .file:
            guard let path = persisted.lastSourceValue, !path.isEmpty else {
                loadRandomSource(from: library, preferredLength: preferredLength)
                return
            }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                loadRandomSource(from: library, preferredLength: preferredLength)
                return
            }
            loadFileSource(url: url, persist: false)

        case .photos:
            guard let identifier = persisted.lastSourceValue, !identifier.isEmpty else {
                loadRandomSource(from: library, preferredLength: preferredLength)
                return
            }
            loadPhotosSource(identifier: identifier)

        case .sample:
            useGeneratedSample()
        }
    }

    func loadMediaClip(_ clip: MediaClip) {
        Task {
            if clip.file.mediaKind == .image {
                let image = await clip.file.loadImage()
                await MainActor.run {
                    sourceStillImage = image
                    sourceVideoAsset = nil
                    self.invalidateVideoFrameCache()
                    self.resetPreviewHistory()
                    inputSourceLabel = "Random \(clip.file.displayName)"
                    compileLog = image == nil ? "Failed to load random image source." : compileLog
                    if image != nil {
                        persistSource(file: clip.file)
                    }
                    isPlaying = false
                    updateTimelineDurationFromCurrentSource()
                    renderPreview()
                }
                return
            }

            let asset = await clip.file.loadAsset()
            await MainActor.run {
                sourceStillImage = nil
                sourceVideoAsset = asset
                self.invalidateVideoFrameCache()
                self.resetPreviewHistory()
                inputSourceLabel = "Random \(clip.file.displayName)"
                compileLog = asset == nil ? "Failed to load random video source." : compileLog
                if asset != nil {
                    persistSource(file: clip.file)
                }
                isPlaying = asset != nil
                updateTimelineDurationFromCurrentSource()
                renderPreview()
            }
        }
    }

    func loadPhotosSource(identifier: String) {
        Task {
            let auth: ApplePhotos.AuthorizationStatus
            if ApplePhotos.shared.status.canRead {
                auth = ApplePhotos.shared.status
            } else {
                auth = await ApplePhotos.shared.requestAuthorization()
            }

            guard auth.canRead else {
                await MainActor.run {
                    compileLog = "Apple Photos access denied. Enable Photos access in System Settings."
                }
                return
            }

            guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else {
                await MainActor.run {
                    compileLog = "Could not load selected Photos asset."
                }
                return
            }

            if asset.mediaType == .image {
                let image = await ApplePhotos.shared.requestCIImage(for: asset)
                await MainActor.run {
                    sourceStillImage = image
                    sourceVideoAsset = nil
                    self.invalidateVideoFrameCache()
                    self.resetPreviewHistory()
                    inputSourceLabel = "Apple Photos Image"
                    compileLog = image == nil ? "Failed to load Apple Photos image." : compileLog
                    if image != nil {
                        persistLastPhotosSource(identifier: identifier)
                    }
                    isPlaying = false
                    updateTimelineDurationFromCurrentSource()
                    renderPreview()
                }
                return
            }

            if asset.mediaType == .video {
                let avAsset = await ApplePhotos.shared.requestAVAsset(for: asset)
                await MainActor.run {
                    sourceStillImage = nil
                    if let avAsset {
                        sourceVideoAsset = avAsset
                        self.invalidateVideoFrameCache()
                        self.resetPreviewHistory()
                        inputSourceLabel = "Apple Photos Video"
                        persistLastPhotosSource(identifier: identifier)
                        isPlaying = true
                        updateTimelineDurationFromCurrentSource()
                        renderPreview()
                    } else {
                        sourceVideoAsset = nil
                        isPlaying = false
                        compileLog = "Failed to load selected Apple Photos video asset."
                    }
                }
                return
            }

            await MainActor.run {
                compileLog = "Unsupported Photos asset type."
            }
        }
    }

    func loadFileSource(url: URL, persist: Bool) {
        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]
        let videoExts: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]

        if imageExts.contains(ext), let image = CIImage(contentsOf: url) {
            sourceStillImage = image
            sourceVideoAsset = nil
            invalidateVideoFrameCache()
            resetPreviewHistory()
            inputSourceLabel = "File Image: \(url.lastPathComponent)"
            if persist {
                persistLastFileSource(url: url)
            }
            isPlaying = false
            updateTimelineDurationFromCurrentSource()
            renderPreview()
            return
        }

        if videoExts.contains(ext) {
            sourceStillImage = nil
            sourceVideoAsset = AVURLAsset(url: url)
            invalidateVideoFrameCache()
            resetPreviewHistory()
            inputSourceLabel = "File Video: \(url.lastPathComponent)"
            if persist {
                persistLastFileSource(url: url)
            }
            updateTimelineDurationFromCurrentSource()
            isPlaying = true
            renderPreview()
            return
        }

        compileLog = "Unsupported file type. Pick an image or video."
    }

    func persistSource(file: MediaFile) {
        switch file.source {
        case .url(let url):
            persistLastFileSource(url: url)
        case .external(let identifier):
            persistLastPhotosSource(identifier: identifier)
        }
    }

    func persistLastFileSource(url: URL) {
        settingsStore.update { value in
            value.lastSourceKind = .file
            value.lastSourceValue = url.path
        }
    }

    func persistLastPhotosSource(identifier: String) {
        settingsStore.update { value in
            value.lastSourceKind = .photos
            value.lastSourceValue = identifier
        }
    }

    func persistLastSourceSample() {
        settingsStore.update { value in
            value.lastSourceKind = .sample
            value.lastSourceValue = nil
        }
    }

    func currentSourceImage(time: Double) -> CIImage {
        if let image = sourceStillImage {
            return aspectFill(image: image, to: previewSize)
        }

        if let asset = sourceVideoAsset, let frame = videoFrame(from: asset, at: time) {
            return aspectFill(image: frame, to: previewSize)
        }

        return makeGeneratedPreviewImage(size: previewSize, time: Float(time))
    }

    func videoFrame(from asset: AVAsset, at time: Double) -> CIImage? {
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

    func invalidateVideoFrameCache() {
        videoFrameGenerator = nil
        videoFrameGeneratorAssetID = nil
        lastVideoFrameImage = nil
    }

    func aspectFill(image: CIImage, to size: CGSize) -> CIImage {
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

    func makeGeneratedPreviewImage(size: CGSize, time: Float) -> CIImage {
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

    func updatePlaybackLoop() {
        if !isPlaying {
            playbackTask?.cancel()
            playbackTask = nil
            lastPlaybackTickUptimeNs = nil
            return
        }

        if playbackTask != nil {
            return
        }

        lastPlaybackTickUptimeNs = DispatchTime.now().uptimeNanoseconds
        playbackTask = Task { [weak self] in
            let tickDurationNs: UInt64 = 16_666_667
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickDurationNs)
                await MainActor.run {
                    guard let self else { return }
                    guard self.isPlaying else { return }

                    let now = DispatchTime.now().uptimeNanoseconds
                    let last = self.lastPlaybackTickUptimeNs ?? now
                    self.lastPlaybackTickUptimeNs = now

                    let elapsed = Double(now &- last) / 1_000_000_000.0
                    guard elapsed.isFinite, elapsed > 0 else { return }

                    let duration = max(self.timelineDuration, 0.001)
                    var nextTime = self.time + elapsed
                    if nextTime >= duration {
                        nextTime = nextTime.truncatingRemainder(dividingBy: duration)
                    }
                    if !nextTime.isFinite || nextTime < 0 {
                        nextTime = 0
                    }
                    self.time = nextTime
                }
            }
        }
    }

    func updateTimelineDurationFromCurrentSource() {
        if let asset = sourceVideoAsset {
            let duration = asset.duration.seconds
            if duration.isFinite, duration > 0 {
                timelineDuration = duration
            } else {
                timelineDuration = 12
            }
        } else {
            timelineDuration = 12
        }

        let maxTime = max(timelineDuration, 0.001)
        if time >= maxTime {
            time = time.truncatingRemainder(dividingBy: maxTime)
        }
        if !time.isFinite || time < 0 {
            time = 0
        }
    }
}
