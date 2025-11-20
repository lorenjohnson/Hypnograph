import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Single composited preview using the same AVFoundation + custom
/// Core Image compositor as the final render.
struct MontageView: NSViewRepresentable {
    let layers: [HypnogramLayer]
    @Binding var currentLayerTime: CMTime?
    let outputDuration: CMTime
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
            guard let item = makeDisplay(for: layers, renderSize: outputSize) else {
                Self.tearDown(coordinator: c, view: nsView)
                currentLayerTime = nil
                return
            }

            let previousTime = c.player?.currentTime() ?? .zero
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

            player.seek(to: previousTime)
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
    /// MultiLayerBlendCompositor (Core Image compositor), using the
    /// *same* looping + duration semantics as the final renderer.
    private func makeDisplay(
        for layers: [HypnogramLayer],
        renderSize: CGSize
    ) -> AVPlayerItem? {
        let targetSeconds = outputDuration.seconds
        guard targetSeconds > 0 else {
            print("Preview: non-positive targetDuration; skipping")
            return nil
        }

        let buildResult: MontageCompositionBuilder.Result
        do {
            buildResult = try MontageCompositionBuilder.build(
                layers: layers,
                targetDuration: outputDuration
            )
        } catch {
            print("Preview: composition build failed: \(error)")
            return nil
        }

        let composition   = buildResult.composition
        let videoTrackIDs = buildResult.videoTrackIDs
        let blendModes    = buildResult.blendModes
        let transforms    = buildResult.transforms

        // Same instruction + custom compositor as renderer
        let instruction = MultiLayerBlendInstruction(
            layerTrackIDs: videoTrackIDs,
            blendModes: blendModes,
            transforms: transforms,
            timeRange: CMTimeRange(start: .zero, duration: outputDuration)
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MultiLayerBlendCompositor.self
        videoComposition.renderSize    = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions  = [instruction]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition

        return item
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
