import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Single composited preview using the same AVFoundation + custom
/// Core Image compositor as the final render.
struct MontageView: NSViewRepresentable {
    /// Unified blueprint for this preview (can be a solo subset recipe).
    let recipe: HypnogramRecipe

    /// Preview render size (currently comes from Settings.outputSize).
    let outputSize: CGSize

    @Binding var currentSourceTime: CMTime?
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
        guard !recipe.sources.isEmpty else {
            Self.tearDown(coordinator: c, view: nsView)
            currentSourceTime = nil
            return
        }

        // Build a simple identity string so we only rebuild when sources,
        // blend modes, or duration change.
        let newID = compositionIdentity(for: recipe)

        if newID != c.compositionID || c.player == nil {
            // Rebuild composition + player item
            guard let item = makeDisplay(from: recipe, renderSize: outputSize) else {
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

    /// Build an identity string so we know when sources, blend modes, or duration change.
    private func compositionIdentity(for recipe: HypnogramRecipe) -> String {
        let blendModes = resolvedBlendModes(from: recipe)

        let pairs: [String] = recipe.sources.enumerated().map { index, source in
            let url   = source.clip.file.url.path
            let start = source.clip.startTime.seconds
            let dur   = source.clip.duration.seconds
            let mode  = index < blendModes.count ? blendModes[index] : kBlendModeDefaultMontage
            return "\(url)|\(start)|\(dur)|\(mode)"
        }

        let durationPart = "dur=\(recipe.targetDuration.seconds)"
        return pairs.joined(separator: ";;") + "||" + durationPart
    }

    /// Resolve per-layer blend modes from the recipe's mode payload.
    ///
    /// - Index 0: always SourceOver.
    /// - Others: use stored value if present; otherwise default Montage blend.
    private func resolvedBlendModes(from recipe: HypnogramRecipe) -> [String] {
        let count = recipe.sources.count
        let modeData = recipe.mode?.sourceData ?? []

        return (0..<count).map { idx in
            if idx == 0 {
                return kBlendModeSourceOver
            }

            let stored = (idx < modeData.count) ? modeData[idx]["blendMode"] : nil
            return stored ?? kBlendModeDefaultMontage
        }
    }

    /// Build an AVPlayerItem using AVMutableComposition + our custom
    /// MultiLayerBlendCompositor (Core Image compositor), using the
    /// *same* looping + duration semantics as the final renderer.
    private func makeDisplay(
        from recipe: HypnogramRecipe,
        renderSize: CGSize
    ) -> AVPlayerItem? {
        let sources = recipe.sources
        let targetDuration = recipe.targetDuration

        let targetSeconds = targetDuration.seconds
        guard targetSeconds > 0 else {
            print("Preview: non-positive targetDuration; skipping")
            return nil
        }

        let buildResult: MontageTimelineBuilder.Result

        do {
            buildResult = try MontageTimelineBuilder.build(
                sources: sources,
                targetDuration: targetDuration
            )
        } catch let error as MontageTimelineBuilder.BuildError {
            switch error {
            case .noValidVideoTracks:
                // All visible sources are likely still images.
                // Build a dummy timebase composition with empty video tracks,
                // one per source, and let the compositor draw the stills.
                buildResult = Self.buildDummyStillComposition(
                    sources: sources,
                    targetDuration: targetDuration
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

        // Per-layer blend-mode list derived from mode payload.
        let resolvedBlendModes = resolvedBlendModes(from: recipe)

        // For preview, keep the mapping simple: one track per displayed source
        // in the same order, so we can safely index into `sources`.
        let localSourceIndices = Array(0..<videoTrackIDs.count)

        let instruction = MultiLayerBlendInstruction.make(
            layerTrackIDs: videoTrackIDs,
            blendModes: resolvedBlendModes,
            transforms: transforms,
            sourceIndices: localSourceIndices,
            timeRange: CMTimeRange(start: .zero, duration: targetDuration),
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
