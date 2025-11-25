import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Unified display view for Dream mode, supporting both montage and sequence styles.
///
/// - **Montage style**: All sources composited together, looping at targetDuration
/// - **Sequence style**: All sources concatenated in timeline, seek to current source
struct DreamView: NSViewRepresentable {
    /// The recipe containing all sources and target duration
    let recipe: HypnogramRecipe
    
    /// Display style: montage (layered) or sequence (timeline)
    let style: DreamStyle
    
    /// Preview render size
    let outputSize: CGSize
    
    /// Current source index (used for seeking in sequence style)
    let currentSourceIndex: Int
    
    /// Binding to track current playback time (montage style only)
    @Binding var currentSourceTime: CMTime?
    
    let playRate: Float = 0.8
    
    class Coordinator {
        var player: AVPlayer?
        var timeObserverToken: Any?
        var endObserverToken: Any?
        var compositionID: String?
        var clipStartTimes: [CMTime] = []
        var lastSeekIndex: Int?
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
        
        guard !recipe.sources.isEmpty else {
            Self.tearDown(coordinator: c, view: nsView)
            currentSourceTime = nil
            return
        }
        
        let newID = compositionIdentity(for: recipe, style: style)
        
        if newID != c.compositionID || c.player == nil {
            guard let build = makePlayerItem(from: recipe, style: style) else {
                Self.tearDown(coordinator: c, view: nsView)
                currentSourceTime = nil
                return
            }
            
            let previousTime = c.player?.currentTime() ?? .zero
            let player: AVPlayer
            if let existing = c.player {
                player = existing
                player.replaceCurrentItem(with: build.item)
            } else {
                player = AVPlayer(playerItem: build.item)
                c.player = player
            }
            
            nsView.player = player
            c.compositionID = newID
            c.clipStartTimes = build.clipStartTimes
            c.lastSeekIndex = nil
            
            // Remove previous observers
            if let token = c.timeObserverToken {
                player.removeTimeObserver(token)
                c.timeObserverToken = nil
            }
            if let token = c.endObserverToken {
                NotificationCenter.default.removeObserver(token)
                c.endObserverToken = nil
            }
            
            // Setup observers based on style
            switch style {
            case .montage:
                setupMontageObservers(player: player, item: build.item, coordinator: c)
            case .sequence:
                setupSequenceObservers(player: player, item: build.item, coordinator: c)
            }
            
            player.seek(to: previousTime)
            player.playImmediately(atRate: playRate)
        } else {
            c.player?.playImmediately(atRate: playRate)
        }
        
        // In sequence style, seek to current source when selection changes
        if style == .sequence,
           currentSourceIndex != c.lastSeekIndex,
           currentSourceIndex < c.clipStartTimes.count {
            let seekTime = c.clipStartTimes[currentSourceIndex]
            c.player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
            c.lastSeekIndex = currentSourceIndex
        }
    }
    
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        tearDown(coordinator: coordinator, view: nsView)
    }
    
    // MARK: - Helpers
    
    private func compositionIdentity(for recipe: HypnogramRecipe, style: DreamStyle) -> String {
        let blendModes = resolvedBlendModes(from: recipe)
        let pairs: [String] = recipe.sources.enumerated().map { index, source in
            let url = source.clip.file.url.path
            let start = source.clip.startTime.seconds
            let dur = source.clip.duration.seconds
            let mode = index < blendModes.count ? blendModes[index] : kBlendModeDefaultMontage
            return "\(url)|\(start)|\(dur)|\(mode)"
        }
        let durationPart = "dur=\(recipe.targetDuration.seconds)"
        let stylePart = "style=\(style.rawValue)"
        return pairs.joined(separator: ";;") + "||" + durationPart + "||" + stylePart
    }
    
    private func resolvedBlendModes(from recipe: HypnogramRecipe) -> [String] {
        let count = recipe.sources.count
        let modeData = recipe.mode?.sourceData ?? []

        return (0..<count).map { idx in
            if idx == 0 { return kBlendModeSourceOver }
            let stored = (idx < modeData.count) ? modeData[idx]["blendMode"] : nil
            return stored ?? kBlendModeDefaultMontage
        }
    }

    private func makePlayerItem(
        from recipe: HypnogramRecipe,
        style: DreamStyle
    ) -> (item: AVPlayerItem, clipStartTimes: [CMTime])? {
        switch style {
        case .montage:
            return makeMontageItem(from: recipe)
        case .sequence:
            return makeSequenceItem(from: recipe)
        }
    }

    // MARK: - Montage composition

    private func makeMontageItem(
        from recipe: HypnogramRecipe
    ) -> (item: AVPlayerItem, clipStartTimes: [CMTime])? {
        let sources = recipe.sources
        let targetDuration = recipe.targetDuration

        guard targetDuration.seconds > 0 else {
            print("DreamView[montage]: non-positive targetDuration")
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
                buildResult = Self.buildDummyStillComposition(
                    sources: sources,
                    targetDuration: targetDuration
                )
            default:
                print("DreamView[montage]: composition build failed: \(error)")
                return nil
            }
        } catch {
            print("DreamView[montage]: composition build failed: \(error)")
            return nil
        }

        let composition = buildResult.composition
        let videoTrackIDs = buildResult.videoTrackIDs
        let transforms = buildResult.transforms
        let resolvedBlendModes = resolvedBlendModes(from: recipe)
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
        videoComposition.renderSize = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition

        // Montage doesn't need clip start times
        return (item, [])
    }

    // MARK: - Sequence composition

    private func makeSequenceItem(
        from recipe: HypnogramRecipe
    ) -> (item: AVPlayerItem, clipStartTimes: [CMTime])? {
        let sources = recipe.sources
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            print("DreamView[sequence]: failed to add video track")
            return nil
        }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var instructions: [AVVideoCompositionInstructionProtocol] = []
        var startTimes: [CMTime] = []
        var currentTime = CMTime.zero

        for (index, source) in sources.enumerated() {
            let clip = source.clip
            let asset = AVURLAsset(url: clip.file.url)

            guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
                print("DreamView[sequence]: no video track in source \(index)")
                continue
            }

            let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)
            do {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: currentTime)
            } catch {
                print("DreamView[sequence]: failed to insert video for source \(index): \(error)")
                continue
            }

            if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first, let audioTrack {
                do {
                    try audioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: currentTime)
                } catch {
                    print("DreamView[sequence]: failed to insert audio for source \(index): \(error)")
                }
            }

            startTimes.append(currentTime)

            let instruction = MultiLayerBlendInstruction(
                layerTrackIDs: [videoTrack.trackID],
                blendModes: [kBlendModeSourceOver],
                transforms: [.identity],
                sourceIndices: [index],
                timeRange: CMTimeRange(start: currentTime, duration: clip.duration)
            )
            instructions.append(instruction)

            currentTime = CMTimeAdd(currentTime, clip.duration)
        }

        guard !instructions.isEmpty else {
            print("DreamView[sequence]: no valid instructions built")
            return nil
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MultiLayerBlendCompositor.self
        videoComposition.renderSize = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition

        return (item, startTimes)
    }

    // MARK: - Dummy still composition

    private static func buildDummyStillComposition(
        sources: [HypnogramSource],
        targetDuration: CMTime
    ) -> MontageTimelineBuilder.Result {
        let composition = AVMutableComposition()
        composition.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: targetDuration))

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

    // MARK: - Observer setup

    private func setupMontageObservers(
        player: AVPlayer,
        item: AVPlayerItem,
        coordinator c: Coordinator
    ) {
        // Track playback time for montage
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        c.timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            // Update binding on next runloop to avoid mutating during view update
            DispatchQueue.main.async {
                self.currentSourceTime = time
            }
        }

        // Loop at end
        c.endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            guard let p = player else { return }
            p.seek(to: .zero)
            p.playImmediately(atRate: 0.8)
        }
    }

    private func setupSequenceObservers(
        player: AVPlayer,
        item: AVPlayerItem,
        coordinator c: Coordinator
    ) {
        // Sequence doesn't loop by default - just plays through
        // Could add looping here if desired
    }

    // MARK: - Teardown

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
        c.clipStartTimes = []
        c.lastSeekIndex = nil
        view.player = nil
    }
}

