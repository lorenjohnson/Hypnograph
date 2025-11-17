import Foundation
import AVFoundation
import CoreMedia

/// RenderBackend implementation that uses AVFoundation to render full Hypnographs:
/// - one video track per layer (looped as needed to fill the target duration)
/// - optional audio tracks per layer (also looped)
/// - custom CoreImage compositor applying per-layer blend modes.
final class AVRenderBackend: RenderBackend {
    private let outputFolder: URL
    private let outputWidth: Int
    private let outputHeight: Int

    /// `outputWidth` / `outputHeight`:
    /// - both > 0  → use exactly this size
    /// - only one > 0 (other 0) → derive the other assuming 16:9 (width:height)
    /// - both 0 → default 1920x1080
    init(
        outputFolder: URL,
        outputWidth: Int = 0,
        outputHeight: Int = 0
    ) {
        self.outputFolder = outputFolder
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
    }

    /// Final render size based on settings, with 16:9 default.
    private var targetRenderSize: CGSize {
        let defaultW: CGFloat = 1920
        let defaultH: CGFloat = 1080
        let aspect: CGFloat   = 16.0 / 9.0  // width / height

        let w = CGFloat(outputWidth)
        let h = CGFloat(outputHeight)

        switch (w > 0, h > 0) {
        case (true, true):
            // Both explicitly set
            return CGSize(width: w, height: h)

        case (true, false):
            // Width set → derive height from 16:9
            return CGSize(width: w, height: round(w / aspect))

        case (false, true):
            // Height set → derive width from 16:9
            return CGSize(width: round(h * aspect), height: h)

        default:
            // Neither set → default 1920x1080
            return CGSize(width: defaultW, height: defaultH)
        }
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
                domain: "AVRenderBackend",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Empty HypnogramRecipe"]
            )
            print("AVRenderBackend: \(err)")
            completion(.failure(err))
            return
        }

        let targetDuration = recipe.targetDuration
        let targetSeconds = targetDuration.seconds
        guard targetSeconds > 0 else {
            let err = NSError(
                domain: "AVRenderBackend",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Non-positive targetDuration in recipe"]
            )
            print("AVRenderBackend: \(err)")
            completion(.failure(err))
            return
        }

        print("AVRenderBackend: rendering recipe with \(recipe.layers.count) layer(s), target duration \(targetSeconds)s")

        let composition = AVMutableComposition()

        var videoTrackIDs: [CMPersistentTrackID] = []
        var blendModes: [String] = []

        // Helper to insert a timeRange based on seconds
        func insertSegment(
            from srcTrack: AVAssetTrack,
            startSeconds: Double,
            durationSeconds: Double,
            into compTrack: AVMutableCompositionTrack,
            at insertTime: inout CMTime
        ) throws {
            guard durationSeconds > 0 else { return }
            let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
            let duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
            let range = CMTimeRange(start: start, duration: duration)
            try compTrack.insertTimeRange(range, of: srcTrack, at: insertTime)
            insertTime = insertTime + duration
        }

        // 2. One track per layer, looped to fill `targetDuration`
        for (index, layer) in recipe.layers.enumerated() {
            let clip = layer.clip
            let asset = AVAsset(url: clip.file.url)

            guard let srcVideoTrack = asset.tracks(withMediaType: .video).first else {
                print("AVRenderBackend: layer \(index) has no video track; skipping")
                continue
            }

            let fileDuration = asset.duration
            let fileSeconds = fileDuration.seconds
            if fileSeconds <= 0 {
                print("AVRenderBackend: layer \(index) has non-positive duration; skipping")
                continue
            }

            // Composition video track
            let trackID = CMPersistentTrackID(index + 1)
            guard let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: trackID
            ) else {
                print("AVRenderBackend: failed to add video track for layer \(index)")
                continue
            }

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
                print("AVRenderBackend: failed to insert video segments for layer \(index): \(error)")
                continue
            }

            // Track ID for compositor
            videoTrackIDs.append(compVideoTrack.trackID)

            // Per-layer blend mode: base layer should always be normal/source-over,
            // higher layers use their configured CI filter.
            if index == 0 {
                blendModes.append("CISourceOverCompositing")
            } else {
                blendModes.append(layer.blendMode.ciFilterName)
            }

            // Audio: mirror the same looping if present
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
                        print("AVRenderBackend: failed to insert audio segments for layer \(index): \(error)")
                    }
                } else {
                    print("AVRenderBackend: failed to add audio track for layer \(index)")
                }
            } else {
                print("AVRenderBackend: layer \(index) has no audio track; skipping audio")
            }
        }

        // 3. Validate content
        guard !videoTrackIDs.isEmpty else {
            let err = NSError(
                domain: "AVRenderBackend",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No valid video content to render"]
            )
            print("AVRenderBackend: \(err)")
            completion(.failure(err))
            return
        }

        print("AVRenderBackend: using \(videoTrackIDs.count) video track(s), duration \(targetSeconds)s")

        // 4. Video composition + custom compositor
        let instruction = VideoCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: targetDuration),
            layerTrackIDs: videoTrackIDs,
            blendModes: blendModes
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = HypnogramVideoCompositor.self
        videoComposition.renderSize = targetRenderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        // 5. Audio mix
        let audioTracks = composition.tracks(withMediaType: .audio)
        print("AVRenderBackend: composition has \(audioTracks.count) audio track(s)")

        var audioMix: AVAudioMix?
        if !audioTracks.isEmpty {
            let mix = AVMutableAudioMix()
            var params: [AVMutableAudioMixInputParameters] = []

            for (i, track) in audioTracks.enumerated() {
                let p = AVMutableAudioMixInputParameters(track: track)
                p.setVolume(1.0, at: .zero)
                params.append(p)
                print("AVRenderBackend: audio track \(i) id=\(track.trackID) duration=\(track.timeRange.duration.seconds)s")
            }

            mix.inputParameters = params
            audioMix = mix
        }

        // 6. Output folder
        do {
            try FileManager.default.createDirectory(
                at: outputFolder,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("AVRenderBackend: failed to create output folder: \(error)")
            completion(.failure(error))
            return
        }

        let filename = "hypnogram-\(UUID().uuidString).mp4"
        let outputURL = outputFolder.appendingPathComponent(filename)
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
                domain: "AVRenderBackend",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAssetExportSession"]
            )
            print("AVRenderBackend: \(err)")
            completion(.failure(err))
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        if let mix = audioMix {
            exportSession.audioMix = mix
            print("AVRenderBackend: attached audio mix with \(mix.inputParameters.count) input(s)")
        } else {
            print("AVRenderBackend: no audio mix attached")
        }

        print("AVRenderBackend: starting export to \(outputURL.path)")

        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                print("AVRenderBackend: export completed → \(outputURL.path)")
                completion(.success(outputURL))

            case .failed, .cancelled:
                let error = exportSession.error ?? NSError(
                    domain: "AVRenderBackend",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Export failed or cancelled"]
                )
                print("AVRenderBackend: export failed/cancelled: \(error)")
                completion(.failure(error))

            default:
                let error = exportSession.error ?? NSError(
                    domain: "AVRenderBackend",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected export status: \(exportSession.status)"]
                )
                print("AVRenderBackend: unexpected export status: \(exportSession.status) (error: \(String(describing: exportSession.error)))")
                completion(.failure(error))
            }
        }
    }
}
