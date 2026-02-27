import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import AppKit
import HypnoCore

enum RecordingRenderPipeline {
    enum PipelineError: LocalizedError {
        case emptySelection
        case segmentRenderFailed(index: Int, reason: String)
        case imageDecodeFailed(URL)
        case pixelBufferPoolUnavailable
        case pixelBufferCreateFailed
        case writerStartFailed
        case writerFailed(String)
        case segmentMissingVideoTrack(URL)
        case concatExportSessionUnavailable
        case concatFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptySelection:
                return "Recording range is empty."
            case .segmentRenderFailed(let index, let reason):
                return "Failed to render segment \(index + 1): \(reason)"
            case .imageDecodeFailed(let url):
                return "Failed to decode image segment at \(url.lastPathComponent)"
            case .pixelBufferPoolUnavailable:
                return "Video segment writer couldn't create a pixel buffer pool."
            case .pixelBufferCreateFailed:
                return "Failed to allocate pixel buffer for still-image segment."
            case .writerStartFailed:
                return "Failed to start video writer."
            case .writerFailed(let message):
                return "Failed writing video segment: \(message)"
            case .segmentMissingVideoTrack(let url):
                return "Rendered segment is missing a video track: \(url.lastPathComponent)"
            case .concatExportSessionUnavailable:
                return "Couldn't create export session for concatenation."
            case .concatFailed(let message):
                return "Failed to concatenate recording: \(message)"
            }
        }
    }

    static func render(
        clips: [Hypnogram],
        outputFolder: URL,
        outputSize: CGSize,
        frameRate: Int = 30,
        sourceFraming: SourceFraming
    ) async -> Result<URL, Error> {
        guard !clips.isEmpty else { return .failure(PipelineError.emptySelection) }

        let fileManager = FileManager.default
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hypnograph-recording-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDirectory) }

            try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)

            var segmentURLs: [URL] = []
            segmentURLs.reserveCapacity(clips.count)

            for (index, clip) in clips.enumerated() {
                let segmentBaseURL = tempDirectory.appendingPathComponent(
                    String(format: "segment-%03d.mov", index),
                    isDirectory: false
                )

                let engine = RenderEngine()
                let config = RenderEngine.Config(
                    outputSize: outputSize,
                    frameRate: frameRate,
                    enableEffects: true,
                    sourceFraming: sourceFraming
                )

                let renderedSegmentURL: URL
                switch await engine.export(clip: clip, outputURL: segmentBaseURL, config: config) {
                case .success(let url):
                    renderedSegmentURL = url
                case .failure(let error):
                    return .failure(PipelineError.segmentRenderFailed(index: index, reason: error.localizedDescription))
                }

                let ensuredVideoURL = try await ensureVideoSegment(
                    renderedURL: renderedSegmentURL,
                    clip: clip,
                    outputSize: outputSize,
                    frameRate: frameRate,
                    tempDirectory: tempDirectory,
                    index: index
                )
                segmentURLs.append(ensuredVideoURL)
            }

            let outputURL = recordingOutputURL(in: outputFolder)
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }

            try await concatenate(segmentURLs: segmentURLs, outputURL: outputURL)
            return .success(outputURL)
        } catch {
            return .failure(error)
        }
    }

    private static func recordingOutputURL(in folder: URL) -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return folder.appendingPathComponent("hypnograph-recording-\(timestamp).mov")
    }

    private static func ensureVideoSegment(
        renderedURL: URL,
        clip: Hypnogram,
        outputSize: CGSize,
        frameRate: Int,
        tempDirectory: URL,
        index: Int
    ) async throws -> URL {
        let ext = renderedURL.pathExtension.lowercased()
        if ext == "mov" || ext == "mp4" || ext == "m4v" {
            return renderedURL
        }

        let convertedURL = tempDirectory.appendingPathComponent(
            String(format: "segment-%03d-converted.mov", index),
            isDirectory: false
        )
        return try await convertStillImageSegmentToVideo(
            imageURL: renderedURL,
            duration: clip.targetDuration,
            outputSize: outputSize,
            frameRate: frameRate,
            outputURL: convertedURL
        )
    }

    private static func convertStillImageSegmentToVideo(
        imageURL: URL,
        duration: CMTime,
        outputSize: CGSize,
        frameRate: Int,
        outputURL: URL
    ) async throws -> URL {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw PipelineError.imageDecodeFailed(imageURL)
        }

        let width = max(2, Int(outputSize.width.rounded()))
        let height = max(2, Int(outputSize.height.rounded()))

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(input) else { throw PipelineError.writerStartFailed }
        writer.add(input)

        guard writer.startWriting() else { throw PipelineError.writerStartFailed }
        writer.startSession(atSourceTime: .zero)

        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw PipelineError.pixelBufferPoolUnavailable
        }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        let totalFrames = max(1, Int((max(duration.seconds, 0.1) * Double(max(1, frameRate))).rounded()))
        let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let fittedImage = fittedCIImage(CIImage(cgImage: cgImage), outputSize: CGSize(width: width, height: height))

        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            var pixelBufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBufferOut)
            guard let pixelBuffer = pixelBufferOut else { throw PipelineError.pixelBufferCreateFailed }

            ciContext.render(
                fittedImage,
                to: pixelBuffer,
                bounds: CGRect(origin: .zero, size: CGSize(width: width, height: height)),
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frame))
            if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                throw PipelineError.writerFailed(writer.error?.localizedDescription ?? "append failed")
            }
        }

        input.markAsFinished()
        try await finishWriting(writer)
        return outputURL
    }

    private static func fittedCIImage(_ image: CIImage, outputSize: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return image.cropped(to: CGRect(origin: .zero, size: outputSize))
        }

        let scaleX = outputSize.width / extent.width
        let scaleY = outputSize.height / extent.height
        let scale = max(scaleX, scaleY)

        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (outputSize.width - scaled.extent.width) * 0.5 - scaled.extent.minX
        let dy = (outputSize.height - scaled.extent.height) * 0.5 - scaled.extent.minY

        return scaled
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    private static func concatenate(segmentURLs: [URL], outputURL: URL) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw PipelineError.concatFailed("Missing composition video track")
        }
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor: CMTime = .zero

        for url in segmentURLs {
            let asset = AVURLAsset(url: url)
            guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
                throw PipelineError.segmentMissingVideoTrack(url)
            }

            let segmentDuration = asset.duration
            let segmentRange = CMTimeRange(start: .zero, duration: segmentDuration)
            try videoTrack.insertTimeRange(segmentRange, of: sourceVideoTrack, at: cursor)

            if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
               let audioTrack {
                try audioTrack.insertTimeRange(segmentRange, of: sourceAudioTrack, at: cursor)
            }

            cursor = CMTimeAdd(cursor, segmentDuration)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw PipelineError.concatExportSessionUnavailable
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return
        case .failed:
            throw PipelineError.concatFailed(exportSession.error?.localizedDescription ?? "unknown export error")
        case .cancelled:
            throw PipelineError.concatFailed("export was cancelled")
        default:
            throw PipelineError.concatFailed("export ended with status \(exportSession.status.rawValue)")
        }
    }

    private static func finishWriting(_ writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if let error = writer.error {
                    continuation.resume(throwing: PipelineError.writerFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
