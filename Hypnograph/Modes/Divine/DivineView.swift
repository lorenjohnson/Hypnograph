import SwiftUI
import AVFoundation
import AVKit
import CoreGraphics

// MARK: - Divine View Hierarchy

public struct DivineView: View {
    let cards: [DivineCard]
    let selectedIndex: Int?
    let onTap: (UUID) -> Void
    let onLongPress: (UUID) -> Void
    let onDragChanged: (UUID, CGSize) -> Void
    let onDragEnded: (UUID, CGSize) -> Void
    let onLayoutUpdate: (CGSize, CGSize) -> Void
    let playerProvider: (UUID) -> AVPlayer?

    @Binding var sceneScale: CGFloat
    @Binding var panOffset: CGSize

    private let cornerRadius: CGFloat = 12
    private let showBorders: Bool = false

    // Gesture-local state
    @State private var baseScale: CGFloat = 1.0
    @State private var pinchAnchor: UnitPoint = .center
    @State private var isZooming: Bool = false
    @State private var pinchLocation: CGPoint = .zero

    // Canvas pan drag delta (transient; panOffset is the persisted value)
    @State private var panDrag: CGSize = .zero

    public var body: some View {
        GeometryReader { geo in
            let cardSize = layoutSizes(for: geo.size, count: cards.count)

            ZStack {
                // Background pan surface — only hit when *not* over a card.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Only treat as pan when we're not actively pinch-zooming
                                guard !isZooming else { return }
                                panDrag = value.translation
                            }
                            .onEnded { value in
                                guard !isZooming else { return }
                                panOffset = panOffset + value.translation
                                panDrag = .zero
                            }
                    )

                // Inner content that actually scales and pans.
                ZStack {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { pair in
                        let idx = pair.offset
                        let card = pair.element
                        let isSelected = (selectedIndex == idx)

                        CardView(
                            card: card,
                            size: cardSize,
                            player: playerProvider(card.id),
                            showBorder: showBorders,
                            cornerRadius: cornerRadius,
                            isSelected: isSelected
                        )
                        .frame(width: cardSize.width, height: cardSize.height, alignment: .center)
                        .contentShape(Rectangle())
                        .offset(card.offset + card.dragOffset)
                        .onTapGesture { onTap(card.id) }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                                onLongPress(card.id)
                            }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    onDragChanged(card.id, value.translation)
                                }
                                .onEnded { value in
                                    onDragEnded(card.id, value.translation)
                                }
                        )
                        .zIndex(Double(idx))
                    }
                }
                .offset(panOffset + panDrag)                  // pan the whole canvas
                .scaleEffect(sceneScale, anchor: pinchAnchor) // zoom the whole canvas
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black)
            .contentShape(Rectangle()) // full rect hittable for pinch
            .onAppear {
                onLayoutUpdate(geo.size, cardSize)
            }
            .onChange(of: geo.size) { newSize in
                let newCardSize = layoutSizes(for: newSize, count: cards.count)
                onLayoutUpdate(newSize, newCardSize)
            }
            .gesture(magnificationGesture(viewSize: geo.size)) // pinch attached to unscaled container
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        pinchLocation = value.location
                        guard isZooming else { return }
                        pinchAnchor = anchorPoint(for: value.location, in: geo.size)
                    }
            )
        }
    }

    private func magnificationGesture(viewSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !isZooming {
                    isZooming = true
                    // Start gesture from current external scale
                    baseScale = sceneScale
                }
                pinchAnchor = anchorPoint(for: pinchLocation, in: viewSize)
                let adjusted = 1 + (value - 1) * 0.3

                // Match DivineMode's min/max zoom for consistency
                let minZoom: CGFloat = 0.5
                let maxZoom: CGFloat = 3.0

                sceneScale = max(minZoom, min(baseScale * adjusted, maxZoom))
            }
            .onEnded { value in
                let adjusted = 1 + (value - 1) * 0.3

                let minZoom: CGFloat = 0.5
                let maxZoom: CGFloat = 3.0

                sceneScale = max(minZoom, min(baseScale * adjusted, maxZoom))
                isZooming = false
            }
    }

    private func layoutSizes(for geoSize: CGSize, count: Int) -> CGSize {
        // Ignore `count` so card size is stable as you add/remove cards.
        let baseWidth = geoSize.width * 0.3   // 30% of width, tweak to taste
        let clampedWidth = min(max(baseWidth, 260), 420)
        let cardHeight = min(geoSize.height * 0.75, clampedWidth * 1.5)
        return CGSize(width: clampedWidth, height: cardHeight)
    }

    private func anchorPoint(for location: CGPoint, in size: CGSize) -> UnitPoint {
        let x = max(0, min(1, location.x / size.width))
        let y = max(0, min(1, location.y / size.height))
        return UnitPoint(x: x, y: y)
    }
}

private struct CardView: View {
    let card: DivineCard
    let size: CGSize
    let player: AVPlayer?
    let showBorder: Bool
    let cornerRadius: CGFloat
    let isSelected: Bool

    var body: some View {
        ZStack {
            if card.isRevealed {
                if let player {
                    CardPlayerView(player: player)
                        .clipped()
                        .allowsHitTesting(false)
                        .rotationEffect(.degrees(card.isFlipped ? 180 : 0))
                } else if let cg = card.cgImage {
                    Image(decorative: cg, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .rotationEffect(.degrees(card.isFlipped ? 180 : 0))
                } else {
                    Color.black
                        .overlay(
                            Text("Loading...")
                                .foregroundColor(.white.opacity(0.7))
                        )
                        .rotationEffect(.degrees(card.isFlipped ? 180 : 0))
                }
            } else {
                CardBack()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            Group {
                if showBorder {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white, lineWidth: 12)
                }
            }
        )
        .overlay(alignment: .bottomTrailing) {
            if isSelected {
                BlinkingDot()
                    .padding(8)
            }
        }
        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 4)
    }
}

private struct CardBack: View {
    var body: some View {
        Image("CardBack")        // name of the image set in Assets.xcassets
            .resizable()
            .scaledToFill()
    }
}

// No longer used
private struct OriginalCardBack: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.0, green: 0.6, blue: 0.65),
                            Color(red: 0.0, green: 0.45, blue: 0.5)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    StripedPattern()
                        .opacity(0.15)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                )
        }
    }
}

private struct StripedPattern: View {
    var body: some View {
        GeometryReader { geo in
            let stripeWidth: CGFloat = 12
            let count = Int(geo.size.width / stripeWidth * 2)
            ZStack(alignment: .topLeading) {
                ForEach(0..<count, id: \.self) { i in
                    Color.white
                        .opacity(0.3)
                        .frame(width: stripeWidth, height: geo.size.height)
                        .rotationEffect(.degrees(45))
                        .offset(x: CGFloat(i) * stripeWidth - geo.size.height)
                }
            }
        }
    }
}

private struct CardPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = HitTransparentPlayerView()
        view.controlsStyle = .none
        view.player = player
        view.videoGravity = .resizeAspectFill
        view.isHidden = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }

    /// AVPlayerView that forwards mouse events so SwiftUI tap/drag gestures still work.
    private final class HitTransparentPlayerView: AVPlayerView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct BlinkingDot: View {
    @State private var isVisible = true

    var body: some View {
        Circle()
            .fill(Color(red: 0.6, green: 0.0, blue: 0.0))
            .frame(width: 10, height: 10)
            .opacity(isVisible ? 1.0 : 0.15)
            .onAppear {
                withAnimation(
                    Animation
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                ) {
                    isVisible.toggle()
                }
            }
    }
}
