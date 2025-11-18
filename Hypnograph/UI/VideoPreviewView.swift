import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Single composited preview using the same AVFoundation + custom
/// Core Image compositor as the final render.
struct MultiLayerPreviewView: NSViewRepresentable {
    let layers: [HypnogramLayer]
    let currentLayerIndex: Int   // kept for future use if you want e.g. HUD
    @Binding var currentLayerTime: CMTime?
    let outputSize: CGSize

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
    /// LayeredVideoComposition (Core Image compositor).
    private func makePreviewItem(
        for layers: [HypnogramLayer],
        renderSize: CGSize
    ) -> (AVPlayerItem, Double)? {
        let composition = AVMutableComposition()

        var videoTrackIDs: [CMPersistentTrackID] = []
        var blendModes: [String] = []
        var transforms: [CGAffineTransform] = []

        // Use the shortest clip duration as preview duration so we don't run
        // past the end of any track.
        let minDurationSeconds = layers
            .map { $0.clip.duration.seconds }
            .filter { $0 > 0 }
            .min() ?? 1.0

        let targetDuration = CMTime(seconds: minDurationSeconds, preferredTimescale: 600)

        func insertSegment(
            from srcTrack: AVAssetTrack,
            clip: VideoClip,
            into compTrack: AVMutableCompositionTrack
        ) throws {
            let fileDuration = srcTrack.asset?.duration ?? .zero
            let fileSeconds  = fileDuration.seconds

            let requestedStart = clip.startTime.seconds
            let startSeconds   = min(max(requestedStart, 0), max(fileSeconds - 0.0001, 0))
            let maxAvailable   = max(0.0, fileSeconds - startSeconds)
            let segSeconds     = min(clip.duration.seconds, maxAvailable, minDurationSeconds)

            guard segSeconds > 0 else { return }

            let start    = CMTime(seconds: startSeconds, preferredTimescale: 600)
            let duration = CMTime(seconds: segSeconds,    preferredTimescale: 600)
            let range    = CMTimeRange(start: start, duration: duration)

            try compTrack.insertTimeRange(range, of: srcTrack, at: .zero)
        }

        for (index, layer) in layers.enumerated() {
            let clip  = layer.clip
            let asset = AVAsset(url: clip.file.url)

            guard let srcVideoTrack = asset.tracks(withMediaType: .video).first else {
                print("Preview: layer \(index) has no video track; skipping")
                continue
            }

            let trackID = CMPersistentTrackID(index + 1)
            guard let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: trackID
            ) else {
                print("Preview: failed to add video track for layer \(index)")
                continue
            }

            do {
                try insertSegment(from: srcVideoTrack, clip: clip, into: compVideoTrack)
            } catch {
                print("Preview: failed to insert segment for layer \(index): \(error)")
                continue
            }

            videoTrackIDs.append(compVideoTrack.trackID)

            if index == 0 {
                blendModes.append("CISourceOverCompositing")
            } else {
                blendModes.append(layer.blendMode.ciFilterName)
            }

            // Capture the original track's orientation transform.
            transforms.append(srcVideoTrack.preferredTransform)
        }

        guard !videoTrackIDs.isEmpty else {
            print("Preview: no valid video tracks")
            return nil
        }

        let instruction = LayeredVideoCompositionInstruction(
            layerTrackIDs: videoTrackIDs,
            blendModes: blendModes,
            transforms: transforms,
            timeRange: CMTimeRange(start: .zero, duration: targetDuration)
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = LayeredVideoComposition.self
        videoComposition.renderSize    = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions  = [instruction]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition

        return (item, minDurationSeconds)
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
