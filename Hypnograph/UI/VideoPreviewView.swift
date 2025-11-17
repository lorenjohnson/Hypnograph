import SwiftUI
import AVKit
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
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
        view.videoGravity = .resizeAspectFill
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

            // --- PREVIEW PLAYBACK RATE (change this constant) ---
            // 1.0 = normal, 0.5 = half speed, 0.25 = quarter speed, 2.0 = double
            // Float.random(in: (0.4...1.0) )
            let previewRate: Float = 0.8

            player.seek(to: start)
            player.playImmediately(atRate: previewRate)

            // Loop on end.
            c.endObserverToken = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                p.seek(to: start)
                p.playImmediately(atRate: previewRate)   // use same rate on loop
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

fileprivate extension View {
    /// Small per-blend-mode exposure/contrast tweaks so
    /// Screen/Overlay/Multiply don't blow out or crush.
    func hypnoBlendPrep(for modeName: String) -> some View {
        switch modeName.lowercased() {
        case "screen":
            // Screen tends to over-brighten → darken a touch, pop contrast
            return AnyView(
                self
                    .brightness(-0.15)
                    .contrast(1.05)
            )

        case "overlay":
            // Overlay can get a bit heavy → lift mids slightly
            return AnyView(
                self
                    .brightness(0.1)
                    .contrast(0.98)
            )

        case "multiply":
            // Multiply often too dark → lift mids more noticeably
            return AnyView(
                self
                    .brightness(0.1)
                    .contrast(1.02)
            )

        case "softlight", "soft_light", "soft-light":
            // Soft light: tiny midtone lift
            return AnyView(
                self
                    .brightness(0.03)
            )

        default:
            // Modes that don't obviously benefit: leave untouched
            return AnyView(self)
        }
    }
}

struct MultiLayerPreviewView: View {
    let layers: [HypnogramLayer]
    let currentLayerIndex: Int
    @Binding var currentLayerTime: CMTime?
    let outputSize: CGSize

    var body: some View {
        let content = ZStack {
            // Solid background so the base of the stack has something to composite against
            Color.black

            let firstEdgeBlendMode: SwiftUI.BlendMode? = {
                // If we have at least 2 layers, the "edge" between 1 and 2
                // is controlled by layer 2's blend mode.
                guard layers.count > 1 else { return nil }
                let modeName = layers[1].blendMode.name
                return swiftUIBlendMode(for: modeName)
            }()

            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                SingleLayerPreviewView(
                    layer: layer,
                    isActive: index == currentLayerIndex,
                    currentTime: $currentLayerTime
                )
                .hypnoBlendPrep(
                    for: layer.blendMode.name
                )
                .blendMode(blendModeForLayer(at: index,
                                             layer: layer,
                                             firstEdgeMode: firstEdgeBlendMode))
            }
        }
        
        return content
            .compositingGroup()
//            .blur(radius: CGFloat(Float.random(in: 0.0...2.0)))
            .overlay(vignetteOverlay)
            .aspectRatio(outputSize.width / outputSize.height, contentMode: .fit)
            .focusable(false)
    }

    /// Decide which SwiftUI blend mode to use for each layer index.
    private func blendModeForLayer(
        at index: Int,
        layer: HypnogramLayer,
        firstEdgeMode: SwiftUI.BlendMode?
    ) -> SwiftUI.BlendMode {
        // 0 layers is impossible here; if there's only 1 layer, no "edge" mode.
        if layers.count == 1 {
            // Just show the single layer normally.
            return .normal
        }

        // We have 2+ layers:

        if index == 0 {
            // Base layer: when there is a second layer, we want layer 2's mode
            // to "apply down" to layer 1 as well, so they feel like one paired blend.
            return firstEdgeMode ?? .normal
        } else if index == 1 {
            // Second layer: same story – its mode is the one defining the
            // interaction between layer 1 and 2.
            return firstEdgeMode ?? swiftUIBlendMode(for: layer.blendMode.name)
        } else {
            // Layers 3+ use their own configured blend mode relative to the
            // already-composited stack beneath.
            return swiftUIBlendMode(for: layer.blendMode.name)
        }
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
            // SwiftUI doesn’t expose `difference`, `exclusion`, etc.,
            // so we fall back to .normal for those.
            return .normal
        }
    }
    
    // Vignette overlay (unchanged from before, or tweak to taste)
    private var vignetteOverlay: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                Color.black.opacity(0.0),
                Color.black.opacity(0.2),
                Color.black.opacity(1.0)
            ]),
            center: .center,
            startRadius: 0,
            endRadius: 1000
        )
        .blendMode(.darken)
        .allowsHitTesting(false)
    }
}
