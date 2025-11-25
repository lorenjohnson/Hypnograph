//
//  MontageRenderer.swift
//  Hypnograph
//
//  Final export backend for Montage mode.
//
//  Uses the same MontageTimelineBuilder + MultiLayerBlendCompositor
//  pipeline as the preview, but writes to disk via AVAssetExportSession.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

/// CI filter name for “normal” source-over compositing.
/// Used by compositors (e.g. MultiLayerBlendCompositor) for the *bottom* layer
/// and wherever a simple source-over is needed.
let kBlendModeSourceOver = "CISourceOverCompositing"
/// Default per-layer blend mode for Montage (above layer 0).
let kBlendModeDefaultMontage = "CIScreenBlendMode"

final class MontageRenderer: HypnogramRenderer {

    /// Folder where rendered files are written.
    private let outputFolder: URL

    /// Target render size.
    private let outputSize: CGSize

    init(outputURL: URL, outputSize: CGSize) {
        // Treat `outputURL` from Settings as the *folder* for renders.
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
        guard !recipe.sources.isEmpty else {
            throw MontageRendererError.noSources
        }

        let targetDuration = recipe.targetDuration
        guard targetDuration.seconds > 0 else {
            throw MontageRendererError.invalidTargetDuration
        }

        print("🎬 MontageRenderer: starting render with \(recipe.sources.count) source(s), duration \(targetDuration.seconds)s")

        // For export, keep the compositor completely detached from any
        // preview / SwiftUI-driven hooks or frame buffers.
        let savedHooks = GlobalRenderHooks.manager
        GlobalRenderHooks.manager = nil
        defer { GlobalRenderHooks.manager = savedHooks }

        let buildResult: MontageTimelineBuilder.Result

        do {
            buildResult = try MontageTimelineBuilder.build(
                sources: recipe.sources,
                targetDuration: targetDuration
            )
        } catch let error as MontageTimelineBuilder.BuildError {
            switch error {
            case .noValidVideoTracks:
                // All sources are likely still images.
                // Build a dummy timebase composition with empty video tracks,
                // one per source, and let the compositor draw the stills.
                print("🎬 MontageRenderer: no valid video tracks; using dummy still composition")
                buildResult = Self.buildDummyStillComposition(
                    sources: recipe.sources,
                    targetDuration: targetDuration
                )
            default:
                print("❌ MontageRenderer: composition build failed: \(error)")
                throw MontageRendererError.compositionBuildFailed(error)
            }
        } catch {
            print("❌ MontageRenderer: composition build failed: \(error)")
            throw MontageRendererError.compositionBuildFailed(error)
        }

        let composition   = buildResult.composition
        let videoTrackIDs = buildResult.videoTrackIDs
        let transforms    = buildResult.transforms

        print("🎬 MontageRenderer: composition duration = \(composition.duration.seconds)s, layerTrackIDs = \(videoTrackIDs)")

        // Per-layer blend modes derived from recipe.mode?.sourceData if present.
        let blendModes = resolveBlendModes(
            from: recipe,
            layerCount: videoTrackIDs.count
        )

        // IMPORTANT: For export we mimic preview’s mapping:
        // one track per displayed layer, in the same order.
        let sourceIndices = Array(0..<videoTrackIDs.count)

        let instruction = MultiLayerBlendInstruction.make(
            layerTrackIDs: videoTrackIDs,
            blendModes: blendModes,
            transforms: transforms,
            sourceIndices: sourceIndices,
            timeRange: CMTimeRange(start: .zero, duration: targetDuration),
            sources: recipe.sources
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MultiLayerBlendCompositor.self
        videoComposition.renderSize    = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions  = [instruction]

        let outputURL = try prepareOutputURL()

        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            print("❌ MontageRenderer: failed to create AVAssetExportSession")
            throw MontageRendererError.exportSessionCreationFailed
        }

        export.outputURL = outputURL
        export.outputFileType = .mov
        export.videoComposition = videoComposition

        print("🎬 MontageRenderer: export started → \(outputURL.path)")

        let semaphore = DispatchSemaphore(value: 0)

        export.exportAsynchronously {
            semaphore.signal()
        }

        // Block this background queue until export finishes.
        semaphore.wait()

        // After export finishes, inspect status and error.
        if export.status != .completed {
            let status = export.status
            let err = export.error

            print("❌ MontageRenderer: export finished with status=\(status.rawValue), error=\(String(describing: err))")

            // Best-effort: remove any partial or black file.
            let fm = FileManager.default
            if fm.fileExists(atPath: outputURL.path) {
                try? fm.removeItem(at: outputURL)
            }

            throw MontageRendererError.exportFailedStatus(status, underlying: err)
        }

        print("✅ MontageRenderer: export completed → \(outputURL.lastPathComponent)")
        return outputURL
    }

    // MARK: - Helpers

    /// Resolve blend modes for all layers:
    /// - If recipe has mode `.montage` and per-source `"blendMode"` entries, use them.
    /// - Otherwise, fall back to SourceOver for layer 0 and CIScreenBlendMode above.
    private func resolveBlendModes(
        from recipe: HypnogramRecipe,
        layerCount: Int
    ) -> [String] {
        var result: [String] = []

        for idx in 0..<layerCount {
            let fallback = (idx == 0) ? kBlendModeSourceOver : kBlendModeDefaultMontage

            guard
                let mode = recipe.mode,
                mode.name == .montage,
                idx < mode.sourceData.count
            else {
                result.append(fallback)
                continue
            }

            let data = mode.sourceData[idx]
            let stored = data["blendMode"]

            if let stored, !stored.isEmpty {
                result.append(stored)
            } else {
                result.append(fallback)
            }
        }

        return result
    }

    /// Ensure output folder exists and generate a unique filename.
    private func prepareOutputURL() throws -> URL {
        let fm = FileManager.default

        // Create folder if needed
        if !fm.fileExists(atPath: outputFolder.path) {
            try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        }

        let timestamp = Self.timestampString()
        let filename = "Hypnogram-\(timestamp).mov"
        let url = outputFolder.appendingPathComponent(filename)

        // If something is already there with that name, remove it before exporting.
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

    /// Build a dummy AVMutableComposition for the case where there are no
    /// video-backed sources (all still images).
    ///
    /// We:
    /// - create a composition with an empty time range of `targetDuration`
    /// - add one empty video track per source
    /// - use the source transforms directly (no preferredTransform)
    ///
    /// The compositor then uses `MultiLayerBlendInstruction.make(...)` to
    /// attach CIImages for image-backed sources and ignores the empty tracks.
    private static func buildDummyStillComposition(
        sources: [HypnogramSource],
        targetDuration: CMTime
    ) -> MontageTimelineBuilder.Result {
        let composition = AVMutableComposition()

        // Ensure the composition has non-zero duration.
        composition.insertEmptyTimeRange(
            CMTimeRange(start: .zero, duration: targetDuration)
        )

        var videoTrackIDs: [CMPersistentTrackID] = []
        var transforms: [CGAffineTransform] = []

        for (index, source) in sources.enumerated() {
            let trackID = CMPersistentTrackID(index + 1)
            if let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: trackID
            ) {
                compVideoTrack.preferredTransform = .identity
                videoTrackIDs.append(compVideoTrack.trackID)
                transforms.append(source.transform)
            }
        }

        return MontageTimelineBuilder.Result(
            composition: composition,
            videoTrackIDs: videoTrackIDs,
            transforms: transforms,
            duration: targetDuration
        )
    }
}

// MARK: - Errors

enum MontageRendererError: Error {
    case noSources
    case invalidTargetDuration
    case compositionBuildFailed(Error)
    case exportSessionCreationFailed
    case exportFailedStatus(AVAssetExportSession.Status, underlying: Error?)
}
