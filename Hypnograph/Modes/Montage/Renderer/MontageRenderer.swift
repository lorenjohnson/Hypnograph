//
//  MontageRenderer.swift
//  Hypnograph
//
//  Created by Loren Johnson on 17.11.25.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

final class MontageRenderer: HypnogramRenderer {
    private let outputURL: URL
    private let outputSize: CGSize

    init(
        outputURL: URL,
        outputSize: CGSize
    ) {
        self.outputURL = outputURL
        self.outputSize = outputSize
    }

    func enqueue(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.render(recipe: recipe, completion: completion)
        }
    }

    private func render(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void) {
        // 1. Basic sanity check
        guard !recipe.sources.isEmpty else {
            let err = NSError(
                domain: "MontageRenderer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Empty HypnogramRecipe"]
            )
            print("MontageRenderer: \(err)")
            completion(.failure(err))
            return
        }

        let targetDuration = recipe.targetDuration
        let targetSeconds = targetDuration.seconds
        guard targetSeconds > 0 else {
            let err = NSError(
                domain: "MontageRenderer",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Non-positive targetDuration in recipe"]
            )
            print("MontageRenderer: \(err)")
            completion(.failure(err))
            return
        }

        print("MontageRenderer: rendering recipe with \(recipe.sources.count) source(s), target duration \(targetSeconds)s")

        // 2. Per-layer blend-mode configuration:
        //    Prefer the serialized MontageConfig, otherwise fall back to names
        //    derived from the recipe’s sources.
        let configuredBlendModes: [String]
        if let config: MontageConfig = recipe.modeConfig(MontageConfig.self) {
            configuredBlendModes = config.layerBlendModes
        } else {
            configuredBlendModes = defaultBlendModes(from: recipe.sources)
        }

        // 3. Build composition via shared builder (same as preview)
        let buildResult: MontageCompositionBuilder.Result
        do {
            buildResult = try MontageCompositionBuilder.build(
                sources: recipe.sources,
                targetDuration: targetDuration
            )
        } catch {
            print("MontageRenderer: composition build failed: \(error)")
            completion(.failure(error))
            return
        }

        let composition   = buildResult.composition
        let videoTrackIDs = buildResult.videoTrackIDs
        let transforms    = buildResult.transforms

        guard !videoTrackIDs.isEmpty else {
            let err = NSError(
                domain: "MontageRenderer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No valid video tracks in composition"]
            )
            print("MontageRenderer: \(err)")
            completion(.failure(err))
            return
        }

        print("MontageRenderer: using \(videoTrackIDs.count) video track(s), duration \(targetSeconds)s")

        // Normalize blend-mode list to match the number of video tracks.
        let blendModes = normalizedBlendModes(configuredBlendModes, count: videoTrackIDs.count)

        // 4. Video composition + custom compositor
        // For full render, source indices are sequential (no solo filtering)
        let sourceIndices = Array(0..<videoTrackIDs.count)
        let instruction = MultiLayerBlendInstruction(
            layerTrackIDs: videoTrackIDs,
            blendModes: blendModes,
            transforms: transforms,
            sourceIndices: sourceIndices,
            timeRange: CMTimeRange(start: .zero, duration: targetDuration)
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MultiLayerBlendCompositor.self
        videoComposition.renderSize    = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions  = [instruction]

        // 5. Audio mix
        let audioTracks = composition.tracks(withMediaType: .audio)
        print("MontageRenderer: composition has \(audioTracks.count) audio track(s)")

        var audioMix: AVAudioMix?
        if !audioTracks.isEmpty {
            let mix = AVMutableAudioMix()
            var params: [AVMutableAudioMixInputParameters] = []

            for (i, track) in audioTracks.enumerated() {
                let p = AVMutableAudioMixInputParameters(track: track)
                p.setVolume(1.0, at: .zero)
                params.append(p)
                print("MontageRenderer: audio track \(i) id=\(track.trackID) duration=\(track.timeRange.duration.seconds)s")
            }

            mix.inputParameters = params
            audioMix = mix
        }

        // 6. Output folder
        do {
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("MontageRenderer: failed to create output folder: \(error)")
            completion(.failure(error))
            return
        }

        let filename = "hypnogram-\(UUID().uuidString).mp4"
        let outputURL = outputURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outputURL)

        // 7. Export
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPreset1920x1080
        ) ?? AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            let err = NSError(
                domain: "MontageRenderer",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAssetExportSession"]
            )
            print("MontageRenderer: \(err)")
            completion(.failure(err))
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        if let mix = audioMix {
            exportSession.audioMix = mix
            print("MontageRenderer: attached audio mix with \(mix.inputParameters.count) input(s)")
        } else {
            print("MontageRenderer: no audio mix attached")
        }

        print("MontageRenderer: starting export to \(outputURL.path)")

        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                print("MontageRenderer: export completed → \(outputURL.path)")
                completion(.success(outputURL))

            case .failed, .cancelled:
                let error = exportSession.error ?? NSError(
                    domain: "MontageRenderer",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Export failed or cancelled"]
                )
                print("MontageRenderer: export failed/cancelled: \(error)")
                completion(.failure(error))

            default:
                let error = exportSession.error ?? NSError(
                    domain: "MontageRenderer",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected export status: \(exportSession.status)"]
                )
                print("MontageRenderer: unexpected export status: \(exportSession.status) (error: \(String(describing: exportSession.error)))")
                completion(.failure(error))
            }
        }
    }

    // MARK: - Blend-mode helpers

    /// Default per-layer blend modes derived from the recipe’s sources.
    /// First layer is always source-over.
    private func defaultBlendModes(from sources: [HypnogramSource]) -> [String] {
        sources.enumerated().map { index, source in
            if index == 0 {
                return "CISourceOverCompositing"
            } else {
                return source.blendMode.ciFilterName
            }
        }
    }

    /// Normalize a blend-mode list to match the number of layers/tracks.
    /// If too short, pad with the last value; if empty, default to source-over.
    private func normalizedBlendModes(_ modes: [String], count: Int) -> [String] {
        guard count > 0 else { return [] }

        if modes.isEmpty {
            return Array(repeating: "CISourceOverCompositing", count: count)
        }

        if modes.count >= count {
            return Array(modes.prefix(count))
        } else {
            var result = modes
            let last = modes.last ?? "CISourceOverCompositing"
            while result.count < count {
                result.append(last)
            }
            return result
        }
    }
}
