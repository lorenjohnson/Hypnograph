//
//  MontageTimelineBuilder.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics

/// Shared builder that turns a list of Hypnogram sources into an AVMutableComposition.
/// This is deliberately *blend-mode agnostic*; it just builds tracks + transforms.
/// Blend modes are decided by Montage mode and passed separately into the compositor.
struct MontageTimelineBuilder {

    struct Result {
        let composition: AVMutableComposition
        let videoTrackIDs: [CMPersistentTrackID]
        let transforms: [CGAffineTransform]
        let duration: CMTime
    }

    enum BuildError: Error {
        case emptyLayers
        case nonPositiveDuration
        case noValidVideoTracks
    }

    /// Build an AVMutableComposition (video + audio) from hypnogram sources,
    /// looping clips as needed to fill `targetDuration`.
    ///
    /// This is the *single* source of truth used by both preview + export.
    static func build(
        sources: [HypnogramSource],
        targetDuration: CMTime
    ) throws -> Result {
        guard !sources.isEmpty else {
            throw BuildError.emptyLayers
        }

        let targetSeconds = targetDuration.seconds
        guard targetSeconds > 0 else {
            throw BuildError.nonPositiveDuration
        }

        let composition = AVMutableComposition()
        var videoTrackIDs: [CMPersistentTrackID] = []
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

        // One track per source.
        //  - video: real media segments, looped to fill `targetDuration`
        //  - image: dummy track used only as a timebase / layer handle
        for (index, source) in sources.enumerated() {
            let clip = source.clip
            let file = clip.file

            // ---------------------------------------------------------
            // IMAGE SOURCES: create a dummy video track as a timebase.
            // ---------------------------------------------------------
            if file.mediaKind == .image {
                let trackID = CMPersistentTrackID(index + 1)
                guard let compVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: trackID
                ) else {
                    print("MontageTimelineBuilder: failed to add dummy video track for image source \(index)")
                    continue
                }

                // Keep composition tracks untransformed; apply user transform downstream.
                compVideoTrack.preferredTransform = .identity

                // Insert an empty range covering the entire target duration so
                // the track has a defined timebase.
                let fullRange = CMTimeRange(start: .zero, duration: targetDuration)
                compVideoTrack.insertEmptyTimeRange(fullRange)

                videoTrackIDs.append(compVideoTrack.trackID)
                // Only user transform; no preferredTransform for images
                transforms.append(source.transform)

                // No audio for images; continue to next source.
                continue
            }

            // ---------------------------------------------------------
            // VIDEO SOURCES: existing behavior.
            // ---------------------------------------------------------
            let asset = AVAsset(url: file.url)

            guard let srcVideoTrack = asset.tracks(withMediaType: .video).first else {
                print("MontageTimelineBuilder: source \(index) has no video track; skipping")
                continue
            }

            let fileDuration = asset.duration
            let fileSeconds  = fileDuration.seconds
            if fileSeconds <= 0 {
                print("MontageTimelineBuilder: source \(index) has non-positive duration; skipping")
                continue
            }

            // Composition video track
            let trackID = CMPersistentTrackID(index + 1)
            guard let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: trackID
            ) else {
                print("MontageTimelineBuilder: failed to add video track for source \(index)")
                continue
            }

            // Keep composition tracks untransformed; apply orientation + user transform downstream.
            let baseTransform = srcVideoTrack.preferredTransform
            compVideoTrack.preferredTransform = .identity

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
                print("MontageTimelineBuilder: failed to insert video segments for source \(index): \(error)")
                continue
            }

            // Track ID for compositor
            videoTrackIDs.append(compVideoTrack.trackID)

            // Orientation (base) + user transform combined; applied in compositor
            let finalTransform = baseTransform.concatenating(source.transform)
            transforms.append(finalTransform)

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
                        print("MontageTimelineBuilder: failed to insert audio segments for source \(index): \(error)")
                    }
                } else {
                    print("MontageTimelineBuilder: failed to add audio track for source \(index)")
                }
            } else {
                // fine: no audio on this source
            }
        }

        // If we ended up with no video tracks at all, fail explicitly.
        guard !videoTrackIDs.isEmpty else {
            throw BuildError.noValidVideoTracks
        }

        // 🔴 CRITICAL FIX:
        // For image-only timelines (and any other edge case where no real media
        // extended the composition), AVMutableComposition.duration can remain 0.
        // That breaks AVAssetExportSession with "Operation Stopped".
        //
        // If that happens, explicitly insert an empty range on the *composition*
        // itself so the timeline has a non-zero duration.
        if composition.duration.seconds <= 0 {
            print("⚠️ MontageTimelineBuilder: composition duration was 0s; inserting empty time range for \(targetSeconds)s")
            let fullRange = CMTimeRange(start: .zero, duration: targetDuration)
            composition.insertEmptyTimeRange(fullRange)
        }

        // Debug log
        print("🟫 layerTrackIDs:", videoTrackIDs)

        return Result(
            composition: composition,
            videoTrackIDs: videoTrackIDs,
            transforms: transforms,
            duration: targetDuration
        )
    }
}
