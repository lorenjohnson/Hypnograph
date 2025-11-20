//
//  SequenceView.swift
//  Hypnograph
//
//  Created by Loren Johnson on 20.11.25.
//

import SwiftUI
import AVKit
import AVFoundation
import CoreMedia

/// Preview view for sequence mode - displays the current clip in the sequence
struct SequenceView: NSViewRepresentable {
    @ObservedObject var mode: SequenceMode
    let outputSize: CGSize
    
    class Coordinator {
        var player: AVPlayer?
        var endObserverToken: Any?
        var clipIDs: [String] = []
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
        
        let clips = mode.sequenceClips
        let isSolo = mode.isSoloActive
        let currentIndex = mode.currentClipIndex
        let displayClips: [(VideoClip, Int)]
        let targetIndex: Int

        if isSolo, let solo = mode.soloClipIndex, solo < clips.count {
            displayClips = [(clips[solo], solo)] // solo uses original index
            targetIndex = 0
        } else {
            displayClips = Array(clips.enumerated()).map { ($0.element, $0.offset) }
            targetIndex = currentIndex
        }

        let shouldLoop = isSolo
        
        // No clips → clear player
        guard !displayClips.isEmpty else {
            Self.tearDown(coordinator: c, view: nsView)
            return
        }
        
        let clipIDs = displayClips.enumerated().map { clipIdentity(for: $0.element.0, index: $0.offset) }
        
        // Only rebuild if the clip changed
        if clipIDs != c.clipIDs || c.player == nil {
            guard let build = buildSequenceItem(for: displayClips) else {
                Self.tearDown(coordinator: c, view: nsView)
                return
            }

            let item = build.item
            c.clipStartTimes = build.startTimes
            
            let player: AVPlayer
            if let existing = c.player {
                player = existing
                player.replaceCurrentItem(with: item)
            } else {
                player = AVPlayer(playerItem: item)
                c.player = player
            }
            
            nsView.player = player
            c.clipIDs = clipIDs
            c.lastSeekIndex = nil
            
            configureLooping(shouldLoop: shouldLoop, coordinator: c, item: item)
            player.seek(to: .zero)
            player.playImmediately(atRate: 1.0)
        } else {
            // Same sequence, just make sure it's playing
            c.player?.playImmediately(atRate: 1.0)
            if let item = c.player?.currentItem {
                configureLooping(shouldLoop: shouldLoop, coordinator: c, item: item)
            }
        }

        // Seek to the start of the requested clip when the selection changes
        if targetIndex != c.lastSeekIndex,
           targetIndex < c.clipStartTimes.count {
            let seekTime = c.clipStartTimes[targetIndex]
            c.player?.seek(
                to: seekTime,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            c.lastSeekIndex = targetIndex
        }
    }
    
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        tearDown(coordinator: coordinator, view: nsView)
    }
    
    // MARK: - Helpers
    
    private func clipIdentity(for clip: VideoClip, index: Int) -> String {
        let url = clip.file.url.path
        let start = clip.startTime.seconds
        let dur = clip.duration.seconds
        return "\(index)|\(url)|\(start)|\(dur)"
    }
    
    private func buildSequenceItem(for clips: [(VideoClip, Int)]) -> (item: AVPlayerItem, startTimes: [CMTime])? {
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            print("SequenceView: failed to add video track")
            return nil
        }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var instructions: [AVVideoCompositionInstructionProtocol] = []
        var startTimes: [CMTime] = []
        var currentTime = CMTime.zero

        for (index, pair) in clips.enumerated() {
            let clip = pair.0
            let originalIndex = pair.1
            let asset = AVURLAsset(url: clip.file.url)

            guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
                print("SequenceView: no video track in source for clip \(index)")
                continue
            }

            let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)
            do {
                try videoTrack.insertTimeRange(
                    timeRange,
                    of: sourceVideoTrack,
                    at: currentTime
                )
            } catch {
                print("SequenceView: failed to insert time range for clip \(index): \(error)")
                continue
            }

            if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
               let audioTrack {
                do {
                    try audioTrack.insertTimeRange(
                        timeRange,
                        of: sourceAudioTrack,
                        at: currentTime
                    )
                } catch {
                    print("SequenceView: failed to insert audio for clip \(index): \(error)")
                }
            }

            startTimes.append(currentTime)

            // Apply effects via custom compositor
            let instruction = MultiLayerBlendInstruction(
                layerTrackIDs: [videoTrack.trackID],
                blendModes: [],               // No blending for sequential clips
                transforms: [.identity],      // Keep original orientation
                sourceIndices: [originalIndex],       // Map to original clip index for effects
                timeRange: CMTimeRange(start: currentTime, duration: clip.duration)
            )
            instructions.append(instruction)

            currentTime = CMTimeAdd(currentTime, clip.duration)
        }

        guard !instructions.isEmpty else {
            print("SequenceView: no valid instructions built")
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

    private func configureLooping(shouldLoop: Bool, coordinator c: Coordinator, item: AVPlayerItem) {
        // Clear previous observer if no longer looping
        if !shouldLoop, let token = c.endObserverToken {
            NotificationCenter.default.removeObserver(token)
            c.endObserverToken = nil
        }

        guard shouldLoop, c.endObserverToken == nil else { return }

        c.endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player = c.player] _ in
            guard let p = player else { return }
            p.seek(to: .zero)
            p.playImmediately(atRate: 1.0)
        }
    }
    
    private static func tearDown(coordinator c: Coordinator, view: AVPlayerView) {
        if let token = c.endObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        c.endObserverToken = nil
        c.clipStartTimes = []
        c.player?.pause()
        c.player = nil
        c.clipIDs = []
        c.lastSeekIndex = nil
        view.player = nil
    }
}
