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
        guard !recipe.layers.isEmpty else {
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

        print("MontageRenderer: rendering recipe with \(recipe.layers.count) layer(s), target duration \(targetSeconds)s")

        // 2. Build composition via shared builder (same as preview)
        let buildResult: MontageCompositionBuilder.Result
        do {
            buildResult = try MontageCompositionBuilder.build(
                layers: recipe.layers,
                targetDuration: targetDuration
            )
        } catch {
            print("MontageRenderer: composition build failed: \(error)")
            completion(.failure(error))
            return
        }

        let composition  = buildResult.composition
        let videoTrackIDs = buildResult.videoTrackIDs
        let blendModes    = buildResult.blendModes
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

        // 3. Video composition + custom compositor
        let instruction = MultiLayerBlendInstruction(
            layerTrackIDs: videoTrackIDs,
            blendModes: blendModes,
            transforms: transforms,
            timeRange: CMTimeRange(start: .zero, duration: targetDuration)
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MultiLayerBlendCompositor.self
        videoComposition.renderSize    = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions  = [instruction]

        // 4. Audio mix
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

        // 5. Output folder
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

        // 6. Export
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
}
