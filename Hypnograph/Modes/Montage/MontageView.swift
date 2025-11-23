import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Single composited preview using the same AVFoundation + custom
/// Core Image compositor as the final render.
struct MontageView: NSViewRepresentable {
    let sources: [HypnogramSource]
    let sourceIndices: [Int] // Maps source position → original source index
    @Binding var currentSourceTime: CMTime?
    let outputDuration: CMTime
    let outputSize: CGSize
    let playRate: Float = 0.8

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

        // No sources → clear player and time.
        guard !sources.isEmpty else {
            Self.tearDown(coordinator: c, view: nsView)
            currentSourceTime = nil
            return
        }

        // Build a simple identity string so we only rebuild when sources change.
        let newID = compositionIdentity(for: sources)

        if newID != c.compositionID || c.player == nil {
            // Rebuild composition + player item
            guard let item = makeDisplay(for: sources, renderSize: outputSize) else {
                Self.tearDown(coordinator: c, view: nsView)
                currentSourceTime = nil
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
                currentSourceTime = time
            }

            // Loop when reaching the end
            c.endObserverToken = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                p.seek(to: .zero)
                p.playImmediately(atRate: playRate)
            }

            player.seek(to: previousTime)
            player.playImmediately(atRate: playRate)
        } else {
            // Same composition, just make sure it's playing.
            c.player?.playImmediately(atRate: playRate)
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        tearDown(coordinator: coordinator, view: nsView)
    }

    // MARK: - Helpers

    /// Build an identity string so we know when sources change.
    private func compositionIdentity(for sources: [HypnogramSource]) -> String {
        sources.map { source in
            let url   = source.clip.file.url.path
            let start = source.clip.startTime.seconds
            let dur   = source.clip.duration.seconds
            let mode  = source.blendMode.ciFilterName
            return "\(url)|\(start)|\(dur)|\(mode)"
        }
        .joined(separator: ";;")
    }

    /// Build an AVPlayerItem using AVMutableComposition + our custom
    /// MultiLayerBlendCompositor (Core Image compositor), using the
    /// *same* looping + duration semantics as the final renderer.
    private func makeDisplay(
        for sources: [HypnogramSource],
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
                sources: sources,
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
            sourceIndices: sourceIndices,
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
