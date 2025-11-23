//
//  SequenceRenderer.swift
//  Hypnograph
//
//  Created by Loren Johnson on 20.11.25.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

final class SequenceRenderer: HypnogramRenderer {
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
        // In Sequence mode, each source represents a clip to be played sequentially
        DispatchQueue.global(qos: .userInitiated).async {
            self.renderSequence(recipe: recipe, completion: completion)
        }
    }

    private func renderSequence(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void) {

        guard !recipe.sources.isEmpty else {
            let err = NSError(
                domain: "SequenceRenderer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Empty recipe"]
            )
            print("SequenceRenderer: \(err)")
            completion(.failure(err))
            return
        }

        print("SequenceRenderer: rendering sequence with \(recipe.sources.count) clip(s)")

        // Build composition by concatenating clips (each source is one clip in the sequence)
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            let err = NSError(
                domain: "SequenceRenderer",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to add video track to composition"]
            )
            print("SequenceRenderer: \(err)")
            completion(.failure(err))
            return
        }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var currentTime = CMTime.zero
        var instructions: [AVVideoCompositionInstructionProtocol] = []

        for (index, source) in recipe.sources.enumerated() {
            let clip = source.clip
            let asset = AVURLAsset(url: clip.file.url)

            guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
                print("SequenceRenderer: warning - no video track in clip \(index), skipping")
                continue
            }

            let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)
            let insertAt = currentTime

            do {
                try videoTrack.insertTimeRange(
                    timeRange,
                    of: sourceVideoTrack,
                    at: insertAt
                )

                // TODO: Move MultiLayerBlendInstruction to Mode/Renderer or otherwise make a Sequence specific version
                // to eliminate this dependency between modes.
                let instruction = MultiLayerBlendInstruction(
                    layerTrackIDs: [videoTrack.trackID],
                    blendModes: Array(
                        repeating: "CISourceOverCompositing",
                        count: recipe.sources.count
                    ),
                    transforms: [.identity],      // Identity for sequential clips
                    sourceIndices: [index],       // Map to clip index for effects
                    timeRange: CMTimeRange(start: insertAt, duration: clip.duration)
                )
                instructions.append(instruction)

                currentTime = CMTimeAdd(insertAt, clip.duration)
                print("SequenceRenderer: added clip \(index) at \(insertAt.seconds)s, duration \(clip.duration.seconds)s")
            } catch {
                print("SequenceRenderer: failed to insert clip \(index): \(error)")
                completion(.failure(error))
                return
            }

            if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
               let audioTrack {
                do {
                    try audioTrack.insertTimeRange(
                        timeRange,
                        of: sourceAudioTrack,
                        at: insertAt
                    )
                } catch {
                    print("SequenceRenderer: failed to insert audio for clip \(index): \(error)")
                }
            }
        }

        let totalDuration = currentTime
        print("SequenceRenderer: total sequence duration: \(totalDuration.seconds)s")

        guard !instructions.isEmpty else {
            let err = NSError(
                domain: "SequenceRenderer",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "No valid instructions built for sequence render"]
            )
            print("SequenceRenderer: \(err)")
            completion(.failure(err))
            return
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MultiLayerBlendCompositor.self
        videoComposition.renderSize = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        // Output folder
        do {
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("SequenceRenderer: failed to create output folder: \(error)")
            completion(.failure(error))
            return
        }

        let filename = "sequence-\(UUID().uuidString).mp4"
        let outputFileURL = outputURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outputFileURL)

        // Export
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPreset1920x1080
        ) ?? AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            let err = NSError(
                domain: "SequenceRenderer",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAssetExportSession"]
            )
            print("SequenceRenderer: \(err)")
            completion(.failure(err))
            return
        }

        exportSession.outputURL = outputFileURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        print("SequenceRenderer: starting export to \(outputFileURL.path)")

        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                print("SequenceRenderer: export completed → \(outputFileURL.path)")
                completion(.success(outputFileURL))

            case .failed, .cancelled:
                let error = exportSession.error ?? NSError(
                    domain: "SequenceRenderer",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Export failed or cancelled"]
                )
                print("SequenceRenderer: export failed/cancelled: \(error)")
                completion(.failure(error))

            default:
                let error = exportSession.error ?? NSError(
                    domain: "SequenceRenderer",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected export status: \(exportSession.status)"]
                )
                print("SequenceRenderer: unexpected export status: \(exportSession.status)")
                completion(.failure(error))
            }
        }
    }
}
