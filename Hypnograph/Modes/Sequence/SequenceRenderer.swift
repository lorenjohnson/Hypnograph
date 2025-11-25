//
//  SequenceRenderer.swift
//  Hypnograph
//
//  Final export backend for Sequence mode.
//
//  Concatenates clips one after another to match the recipe's targetDuration.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

final class SequenceRenderer: HypnogramRenderer {

    /// Folder where rendered files are written.
    private let outputFolder: URL

    /// Target render size (not strictly needed here, but kept for symmetry).
    private let outputSize: CGSize

    init(outputURL: URL, outputSize: CGSize) {
        self.outputFolder = outputURL
        self.outputSize = outputSize
    }

    // MARK: - HypnogramRenderer

    func enqueue(
        recipe: HypnogramRecipe,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try self.render(recipe: recipe)
                DispatchQueue.main.async {
                    completion(.success(url))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Core render

    private func render(recipe: HypnogramRecipe) throws -> URL {
        let sources = recipe.sources
        guard !sources.isEmpty else {
            throw SequenceRendererError.noSources
        }

        let targetDuration = recipe.targetDuration
        guard targetDuration.seconds > 0 else {
            throw SequenceRendererError.invalidTargetDuration
        }

        // Build a simple linear AVMutableComposition where each source
        // is laid out back-to-back on a single video track.
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SequenceRendererError.cannotCreateTrack
        }

        var cursor = CMTime.zero
        for source in sources {
            let clip = source.clip
            let asset = AVURLAsset(url: clip.file.url)

            guard let track = asset.tracks(withMediaType: .video).first else {
                continue
            }

            // Time range inside the source file.
            let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)

            // Don’t exceed targetDuration overall.
            if cursor >= targetDuration {
                break
            }

            let remaining = targetDuration - cursor
            let actualDuration = min(timeRange.duration, remaining)
            let trimmedRange = CMTimeRange(start: timeRange.start, duration: actualDuration)

            do {
                try videoTrack.insertTimeRange(
                    trimmedRange,
                    of: track,
                    at: cursor
                )
            } catch {
                throw SequenceRendererError.trackInsertFailed(error)
            }

            cursor = cursor + actualDuration
        }

        // If nothing ended up inserted, bail.
        if cursor == .zero {
            throw SequenceRendererError.noUsableClips
        }

        // Optional: basic videoComposition to enforce target size.
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        // Fit into renderSize (simple aspect fit)
        let naturalSize = videoTrack.naturalSize
        let transform = aspectFitTransform(
            from: naturalSize,
            to: outputSize
        )
        layerInstruction.setTransform(transform, at: .zero)

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let outputURL = try prepareOutputURL()

        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw SequenceRendererError.exportSessionCreationFailed
        }

        export.outputURL = outputURL
        export.outputFileType = .mov
        export.videoComposition = videoComposition

        let semaphore = DispatchSemaphore(value: 1)
        semaphore.wait()
        export.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        if let error = export.error {
            throw SequenceRendererError.exportFailed(error)
        }

        return outputURL
    }

    // MARK: - Helpers

    private func aspectFitTransform(from sourceSize: CGSize, to destSize: CGSize) -> CGAffineTransform {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return .identity
        }

        let scale = min(destSize.width / sourceSize.width,
                        destSize.height / sourceSize.height)

        let scaledWidth  = sourceSize.width * scale
        let scaledHeight = sourceSize.height * scale

        let tx = (destSize.width  - scaledWidth)  / 2.0
        let ty = (destSize.height - scaledHeight) / 2.0

        var transform = CGAffineTransform.identity
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: tx / scale, y: ty / scale)

        return transform
    }

    /// Ensure output folder exists and generate a unique filename.
    private func prepareOutputURL() throws -> URL {
        let fm = FileManager.default

        if !fm.fileExists(atPath: outputFolder.path) {
            try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        }

        let timestamp = Self.timestampString()
        let filename = "Sequence-\(timestamp).mov"
        let url = outputFolder.appendingPathComponent(filename)

        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }

        return url
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - Errors

enum SequenceRendererError: Error {
    case noSources
    case invalidTargetDuration
    case cannotCreateTrack
    case trackInsertFailed(Error)
    case noUsableClips
    case exportSessionCreationFailed
    case exportFailed(Error)
}
