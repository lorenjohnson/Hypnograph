import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Single composited preview using the same AVFoundation + custom
/// Core Image compositor as the final render.
struct MontageView: NSViewRepresentable {
    let sources: [HypnogramSource]
    let sourceIndices: [Int] // Maps source position → original source index (for now only used by mode/state)
    let blendModes: [String] // One per displayed source (bottom → top)

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

        // Build a simple identity string so we only rebuild when sources *or blend modes* change.
        let newID = compositionIdentity(for: sources, blendModes: blendModes)

        if newID != c.compositionID || c.player == nil {
            // Rebuild composition + player item
            guard let item = makeDisplay(for: sources, blendModes: blendModes, renderSize: outputSize) else {
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
                // Bounce onto the next runloop tick so we don't mutate
                // @Published / bindings *inside* a view update pass.
                DispatchQueue.main.async {
                    currentSourceTime = time
                }
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

    /// Build an identity string so we know when sources or blend modes change.
    private func compositionIdentity(
        for sources: [HypnogramSource],
        blendModes: [String]
    ) -> String {
        let pairs: [String] = sources.enumerated().map { index, source in
            let url   = source.clip.file.url.path
            let start = source.clip.startTime.seconds
            let dur   = source.clip.duration.seconds
            let mode  = index < blendModes.count ? blendModes[index] : kBlendModeDefaultMontage
            return "\(url)|\(start)|\(dur)|\(mode)"
        }

        return pairs.joined(separator: ";;")
    }

    /// Build an AVPlayerItem using AVMutableComposition + our custom
    /// MultiLayerBlendCompositor (Core Image compositor), using the
    /// *same* looping + duration semantics as the final renderer.
    private func makeDisplay(
        for sources: [HypnogramSource],
        blendModes: [String],
        renderSize: CGSize
    ) -> AVPlayerItem? {
        let targetSeconds = outputDuration.seconds
        guard targetSeconds > 0 else {
            print("Preview: non-positive targetDuration; skipping")
            return nil
        }

        let buildResult: MontageTimelineBuilder.Result

        do {
            buildResult = try MontageTimelineBuilder.build(
                sources: sources,
                targetDuration: outputDuration
            )
        } catch let error as MontageTimelineBuilder.BuildError {
            switch error {
            case .noValidVideoTracks:
                // All visible sources are likely still images.
                // Build a dummy timebase composition with empty video tracks,
                // one per source, and let the compositor draw the stills.
                buildResult = Self.buildDummyStillComposition(
                    sources: sources,
                    targetDuration: outputDuration
                )
            default:
                print("Preview: composition build failed: \(error)")
                return nil
            }
        } catch {
            print("Preview: composition build failed: \(error)")
            return nil
        }

        let composition   = buildResult.composition
        let videoTrackIDs = buildResult.videoTrackIDs
        let transforms    = buildResult.transforms

        // Per-layer blend-mode list derived from mode-managed blendModes.
        // First layer is always source-over.
        let resolvedBlendModes: [String] = blendModes.enumerated().map { index, name in
            index == 0 ? kBlendModeSourceOver : name
        }

        // For preview, keep the mapping simple: one track per displayed source
        // in the same order, so we can safely index into `sources`.
        let localSourceIndices = Array(0..<videoTrackIDs.count)

        let instruction = MultiLayerBlendInstruction.make(
            layerTrackIDs: videoTrackIDs,
            blendModes: resolvedBlendModes,
            transforms: transforms,
            sourceIndices: localSourceIndices,
            timeRange: CMTimeRange(start: .zero, duration: outputDuration),
            sources: sources
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

    /// Build a dummy AVMutableComposition for the case where there are no
    /// video-backed sources (all still images).
    ///
    /// We:
    /// - create a composition with an empty time range of `targetDuration`
    /// - add one empty video track per source
    /// - use the source transforms directly (no preferredTransform)
    ///
    /// The compositor then uses `MultiLayerBlendInstruction.make(...)` to
    /// attach CIImages for image-backed sources and ignores the empty tracks.
    private static func buildDummyStillComposition(
        sources: [HypnogramSource],
        targetDuration: CMTime
    ) -> MontageTimelineBuilder.Result {
        let composition = AVMutableComposition()

        // Ensure the composition has non-zero duration so AVPlayer drives time.
        composition.insertEmptyTimeRange(
            CMTimeRange(start: .zero, duration: targetDuration)
        )

        var videoTrackIDs: [CMPersistentTrackID] = []
        var transforms: [CGAffineTransform] = []

        for (index, source) in sources.enumerated() {
            let trackID = CMPersistentTrackID(index + 1)
            if let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: trackID
            ) {
                compVideoTrack.preferredTransform = .identity
                videoTrackIDs.append(compVideoTrack.trackID)
                transforms.append(source.transform)
            }
        }

        return MontageTimelineBuilder.Result(
            composition: composition,
            videoTrackIDs: videoTrackIDs,
            transforms: transforms,
            duration: targetDuration
        )
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
