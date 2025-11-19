import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Single composited preview using the same AVFoundation + custom
/// Core Image compositor as the final render.
struct MontagePreviewView: NSViewRepresentable {
    let layers: [HypnogramLayer]
    let currentLayerIndex: Int   // kept for future use if you want e.g. HUD
    @Binding var currentLayerTime: CMTime?
    let outputSize: CGSize
    let outputDuration: CMTime

    class Coordinator {
        var player: AVPlayer?
        var timeObserverToken: Any?
        var endObserverToken: Any?
        var compositionID: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.player = AVPlayer()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        let c = context.coordinator

        // No layers → clear player and time.
        guard !layers.isEmpty else {
            Self.tearDown(coordinator: c, view: nsView)
            currentLayerTime = nil
            return
        }

        // Build a simple identity string so we only rebuild when layers change.
        let newID = compositionIdentity(for: layers)

        if newID != c.compositionID || c.player == nil {
            // Rebuild composition + player item
            guard let (item, _) = makePreviewItem(for: layers, renderSize: outputSize) else {
                Self.tearDown(coordinator: c, view: nsView)
                currentLayerTime = nil
                return
            }

            let player: AVPlayer
            if let existing = c.player {
                player = existing
                player.replaceCurrentItem(with: item)
            } else {
                player = AVPlayer(playerItem: item)
                c.player = player
            }

            nsView.player = player
            c.compositionID = newID

            // Remove any previous observers
            if let token = c.timeObserverToken {
                player.removeTimeObserver(token)
                c.timeObserverToken = nil
            }
            if let token = c.endObserverToken {
                NotificationCenter.default.removeObserver(token)
                c.endObserverToken = nil
            }

            // Track preview time (composition-relative)
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            c.timeObserverToken = player.addPeriodicTimeObserver(
                forInterval: interval,
                queue: .main
            ) { time in
                currentLayerTime = time
            }

            // Loop when reaching the end
            c.endObserverToken = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                p.seek(to: .zero)
                p.playImmediately(atRate: 0.8)
            }

            // Start playback at preview rate (slightly slower than real time).
            player.seek(to: .zero)
            player.playImmediately(atRate: 0.8)
        } else {
            // Same composition, just make sure it's playing.
            c.player?.playImmediately(atRate: 0.8)
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        tearDown(coordinator: coordinator, view: nsView)
    }

    // MARK: - Helpers

    /// Build an identity string so we know when layers change.
    private func compositionIdentity(for layers: [HypnogramLayer]) -> String {
        layers.map { layer in
            let url   = layer.clip.file.url.path
            let start = layer.clip.startTime.seconds
            let dur   = layer.clip.duration.seconds
            let mode  = layer.blendMode.key
            return "\(url)|\(start)|\(dur)|\(mode)"
        }
        .joined(separator: ";;")
    }

    /// Build an AVPlayerItem using AVMutableComposition + our custom
    /// LayeredVideoComposition (Core Image compositor), using the
    /// *same* looping + duration semantics as the final renderer.
    private func makePreviewItem(
        for layers: [HypnogramLayer],
        renderSize: CGSize
    ) -> (AVPlayerItem, Double)? {
        let composition = AVMutableComposition()

        var videoTrackIDs: [CMPersistentTrackID] = []
        var blendModes: [String] = []
        var transforms: [CGAffineTransform] = []

        let targetSeconds = outputDuration.seconds
        guard targetSeconds > 0 else {
            print("Preview: non-positive targetDuration; skipping")
            return nil
        }

        // Helper to insert a time range based on seconds
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

        // One track per layer, looped to fill `targetDuration`.
        for (index, layer) in layers.enumerated() {
            let clip  = layer.clip
            let asset = AVAsset(url: clip.file.url)

            guard let srcVideoTrack = asset.tracks(withMediaType: .video).first else {
                print("Preview: layer \(index) has no video track; skipping")
                continue
            }

            let fileDuration = asset.duration
            let fileSeconds = fileDuration.seconds
            if fileSeconds <= 0 {
                print("Preview: layer \(index) has non-positive duration; skipping")
                continue
            }

            // Composition video track
            let trackID = CMPersistentTrackID(index + 1)
            guard let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: trackID
            ) else {
                print("Preview: failed to add video track for layer \(index)")
                continue
            }

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
                print("Preview: failed to insert video segments for layer \(index): \(error)")
                continue
            }

            videoTrackIDs.append(compVideoTrack.trackID)

            // Blend modes match renderer semantics: base layer is normal, others use CI filter.
            if index == 0 {
                blendModes.append("CISourceOverCompositing")
            } else {
                blendModes.append(layer.blendMode.ciFilterName)
            }

            // Preserve original orientation transform.
            transforms.append(srcVideoTrack.preferredTransform)

            // --- Audio mirroring (same looping as renderer) ---

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
                        print("Preview: failed to insert audio segments for layer \(index): \(error)")
                    }
                } else {
                    print("Preview: failed to add audio track for layer \(index)")
                }
            } else {
                // fine: this layer just has no audio
            }
        }

        guard !videoTrackIDs.isEmpty else {
            print("Preview: no valid video tracks")
            return nil
        }

        // Same instruction + custom compositor as renderer
        let instruction = LayeredVideoCompositionInstruction(
            layerTrackIDs: videoTrackIDs,
            blendModes: blendModes,
            transforms: transforms,
            timeRange: CMTimeRange(start: .zero, duration: outputDuration)
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = LayeredVideoComposition.self
        videoComposition.renderSize    = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions  = [instruction]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition

        // We’re using duration from settings, not minDurationSeconds anymore.
        return (item, targetSeconds)
    }

    private static func tearDown(coordinator c: Coordinator, view: AVPlayerView) {
        if let token = c.timeObserverToken, let player = c.player {
            player.removeTimeObserver(token)
        }
        c.timeObserverToken = nil

        if let token = c.endObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        c.endObserverToken = nil

        c.player?.pause()
        c.player = nil
        c.compositionID = nil
        view.player = nil
    }
}
