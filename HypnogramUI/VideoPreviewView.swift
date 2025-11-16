import SwiftUI
import AVKit
import CoreMedia

/// One layer of the live preview: AVPlayerView with no chrome.
/// If `isActive`, it reports its playhead time via `currentTime`.
struct SingleLayerPreviewView: NSViewRepresentable {
    let layer: HypnogramLayer
    let isActive: Bool
    @Binding var currentTime: CMTime?

    class Coordinator {
        var player: AVPlayer?
        var timeObserverToken: Any?
        var endObserverToken: Any?
        var clipID: String?
        var isActive: Bool = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none          // no play bar / buttons
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        let c = context.coordinator
        let clip = layer.clip

        // Identity for this clip instance (file + timing)
        let newID = "\(clip.file.url.path)|\(clip.startTime.seconds)|\(clip.duration.seconds)"

        // If the clip changed, rebuild the player. Otherwise, just update active/inactive.
        if c.clipID != newID || c.player == nil {
            Self.tearDown(coordinator: c)

            let item = AVPlayerItem(url: clip.file.url)

            // Limit playback to [start, start + duration]
            let start = clip.startTime
            let end = CMTimeAdd(clip.startTime, clip.duration)
            item.forwardPlaybackEndTime = end

            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .none
            c.player = player
            c.clipID = newID
            c.isActive = isActive
            nsView.player = player

            player.seek(to: start)
            player.play()

            // Loop on end.
            c.endObserverToken = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                p.seek(to: start)
                p.play()
            }

            // If this layer is active, add a time observer.
            if isActive {
                addTimeObserver(for: player, coordinator: c)
            }
        } else {
            // Same clip, just update active/inactive status.
            if c.isActive != isActive {
                c.isActive = isActive
                if isActive, let player = c.player {
                    addTimeObserver(for: player, coordinator: c)
                } else if let token = c.timeObserverToken, let player = c.player {
                    player.removeTimeObserver(token)
                    c.timeObserverToken = nil
                    // We intentionally do NOT pause here; the layer keeps looping visually.
                }
            }
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        Self.tearDown(coordinator: coordinator)
        nsView.player = nil
    }

    private static func tearDown(coordinator c: Coordinator) {
        if let token = c.timeObserverToken, let p = c.player {
            p.removeTimeObserver(token)
        }
        c.timeObserverToken = nil

        if let token = c.endObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        c.endObserverToken = nil

        c.player?.pause()
        c.player = nil
        c.clipID = nil
        c.isActive = false
    }

    private func addTimeObserver(for player: AVPlayer, coordinator c: Coordinator) {
        // Clear any previous observer first.
        if let token = c.timeObserverToken {
            player.removeTimeObserver(token)
            c.timeObserverToken = nil
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        c.timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            currentTime = time
        }
    }
}

/// Multi-layer preview that stacks each layer and applies blend modes.
struct MultiLayerPreviewView: View {
    let layers: [HypnogramLayer]
    let currentLayerIndex: Int
    @Binding var currentLayerTime: CMTime?

    var body: some View {
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                SingleLayerPreviewView(
                    layer: layer,
                    isActive: index == currentLayerIndex,
                    currentTime: $currentLayerTime
                )
                .blendMode(swiftUIBlendMode(for: layer.blendMode.name))
            }
        }
        .focusable(false)  // 👈 keep keyboard focus off the video stack
    }

    private func swiftUIBlendMode(for name: String) -> SwiftUI.BlendMode {
        switch name.lowercased() {
        case "multiply":
            return .multiply
        case "overlay":
            return .overlay
        case "screen":
            return .screen
        case "softlight", "soft_light", "soft-light":
            return .softLight
        case "darken":
            return .darken
        case "lighten":
            return .lighten
        default:
            return .normal
        }
    }
}
