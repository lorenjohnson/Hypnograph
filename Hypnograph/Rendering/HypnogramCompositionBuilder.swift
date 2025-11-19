//
//  HypnographCompositionBuilder.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//


import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

struct HypnogramCompositionBuilder {

    struct Result {
        let composition: AVMutableComposition
        let videoTrackIDs: [CMPersistentTrackID]
        let blendModes: [String]
        let transforms: [CGAffineTransform]
        let duration: CMTime
    }

    enum BuildError: Error {
        case emptyLayers
        case nonPositiveDuration
        case noValidVideoTracks
    }

    /// Build an AVMutableComposition (video + audio) from hypnogram layers,
    /// looping clips as needed to fill `targetDuration`.
    ///
    /// This is the *single* source of truth used by both preview + export.
    static func build(
        layers: [HypnogramLayer],
        targetDuration: CMTime
    ) throws -> Result {
        guard !layers.isEmpty else {
            throw BuildError.emptyLayers
        }

        let targetSeconds = targetDuration.seconds
        guard targetSeconds > 0 else {
            throw BuildError.nonPositiveDuration
        }

        let composition = AVMutableComposition()
        var videoTrackIDs: [CMPersistentTrackID] = []
        var blendModes: [String] = []
        var transforms: [CGAffineTransform] = []

        // Helper to insert a timeRange based on seconds
        func insertSegment(
            from srcTrack: AVAssetTrack,
            startSeconds: Double,
            durationSeconds: Double,
            into compTrack: AVMutableCompositionTrack,
            at insertTime: inout CMTime
        ) throws {
            guard durationSeconds > 0 else { return }
            let start    = CMTime(seconds: startSeconds,   preferredTimescale: 600)
            let duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
            let range = CMTimeRange(start: start, duration: duration)
            try compTrack.insertTimeRange(range, of: srcTrack, at: insertTime)
            insertTime = insertTime + duration
        }

        // One track per layer, looped to fill `targetDuration`.
        for (index, layer) in layers.enumerated() {
            let clip  = layer.clip
            let asset = AVAsset(url: clip.file.url)

            guard let srcVideoTrack = asset.tracks(withMediaType: .video).first else {
                print("CompositionBuilder: layer \(index) has no video track; skipping")
                continue
            }

            let fileDuration = asset.duration
            let fileSeconds  = fileDuration.seconds
            if fileSeconds <= 0 {
                print("CompositionBuilder: layer \(index) has non-positive duration; skipping")
                continue
            }

            // Composition video track
            let trackID = CMPersistentTrackID(index + 1)
            guard let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: trackID
            ) else {
                print("CompositionBuilder: failed to add video track for layer \(index)")
                continue
            }

            // Preserve original orientation
            compVideoTrack.preferredTransform = srcVideoTrack.preferredTransform

            var insertTime: CMTime = .zero
            var remainingSeconds = targetSeconds

            let initialStartSeconds = min(
                max(clip.startTime.seconds, 0),
                max(fileSeconds - 0.0001, 0)
            )
            let initialAvailable = max(0.0, fileSeconds - initialStartSeconds)
            let firstSegmentSeconds = min(remainingSeconds, initialAvailable)

            do {
                // First tail segment from clip.startTime → end
                if firstSegmentSeconds > 0 {
                    try insertSegment(
                        from: srcVideoTrack,
                        startSeconds: initialStartSeconds,
                        durationSeconds: firstSegmentSeconds,
                        into: compVideoTrack,
                        at: &insertTime
                    )
                    remainingSeconds -= firstSegmentSeconds
                }

                // Then loop from the start as needed
                while remainingSeconds > 0.0001 {
                    let segmentSeconds = min(remainingSeconds, fileSeconds)
                    try insertSegment(
                        from: srcVideoTrack,
                        startSeconds: 0.0,
                        durationSeconds: segmentSeconds,
                        into: compVideoTrack,
                        at: &insertTime
                    )
                    remainingSeconds -= segmentSeconds
                }
            } catch {
                print("CompositionBuilder: failed to insert video segments for layer \(index): \(error)")
                continue
            }

            // Track ID for compositor
            videoTrackIDs.append(compVideoTrack.trackID)

            // Per-layer blend mode: base layer is always source-over, others use CI filter.
            if index == 0 {
                blendModes.append("CISourceOverCompositing")
            } else {
                blendModes.append(layer.blendMode.ciFilterName)
            }

            // Preserve the original track's orientation transform
            transforms.append(srcVideoTrack.preferredTransform)

            // --- Audio mirroring (same looping semantics) ---

            if let srcAudioTrack = asset.tracks(withMediaType: .audio).first {
                if let compAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) {
                    var audioInsertTime: CMTime = .zero
                    var audioRemainingSeconds = targetSeconds

                    do {
                        let audioFirstSegmentSeconds = min(audioRemainingSeconds, initialAvailable)
                        if audioFirstSegmentSeconds > 0 {
                            try insertSegment(
                                from: srcAudioTrack,
                                startSeconds: initialStartSeconds,
                                durationSeconds: audioFirstSegmentSeconds,
                                into: compAudioTrack,
                                at: &audioInsertTime
                            )
                            audioRemainingSeconds -= audioFirstSegmentSeconds
                        }

                        while audioRemainingSeconds > 0.0001 {
                            let seg = min(audioRemainingSeconds, fileSeconds)
                            try insertSegment(
                                from: srcAudioTrack,
                                startSeconds: 0.0,
                                durationSeconds: seg,
                                into: compAudioTrack,
                                at: &audioInsertTime
                            )
                            audioRemainingSeconds -= seg
                        }
                    } catch {
                        print("CompositionBuilder: failed to insert audio segments for layer \(index): \(error)")
                    }
                } else {
                    print("CompositionBuilder: failed to add audio track for layer \(index)")
                }
            } else {
                // fine: no audio on this layer
            }
        }

        guard !videoTrackIDs.isEmpty else {
            throw BuildError.noValidVideoTracks
        }

        return Result(
            composition: composition,
            videoTrackIDs: videoTrackIDs,
            blendModes: blendModes,
            transforms: transforms,
            duration: targetDuration
        )
    }
}
