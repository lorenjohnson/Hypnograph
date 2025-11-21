import SwiftUI
import AVFoundation
import AVKit
import CoreGraphics

// MARK: - Divine View Hierarchy

public struct DivineView: View {
    let cards: [DivineMode.Card]
    let onTap: (UUID) -> Void
    let onLongPress: (UUID) -> Void
    let onDragChanged: (UUID, CGSize) -> Void
    let onDragEnded: (UUID, CGSize) -> Void
    let onLayoutUpdate: (CGSize, CGSize) -> Void
    let playerProvider: (UUID) -> AVPlayer?

    private let cornerRadius: CGFloat = 12
    private let showBorders: Bool = false
    @State private var baseScale: CGFloat = 1.0
    @State private var sceneScale: CGFloat = 1.0

    public var body: some View {
        GeometryReader { geo in
            let cardSize = layoutSizes(for: geo.size, count: cards.count)

            let content = ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { pair in
                    let idx = pair.offset
                    let card = pair.element

                    CardView(
                        card: card,
                        size: cardSize,
                        player: playerProvider(card.id),
                        showBorder: showBorders,
                        cornerRadius: cornerRadius
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

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { onLayoutUpdate(geo.size, cardSize) }
                .onChange(of: geo.size) { newSize in
                    onLayoutUpdate(newSize, layoutSizes(for: newSize, count: cards.count))
                }
                .scaleEffect(sceneScale)
                .gesture(magnificationGesture())
        }
        .background(Color.black)
    }

    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let adjusted = 1 + (value - 1) * 0.3
                sceneScale = max(0.5, min(baseScale * adjusted, 3.0))
            }
            .onEnded { value in
                let adjusted = 1 + (value - 1) * 0.3
                sceneScale = max(0.5, min(baseScale * adjusted, 3.0))
                baseScale = sceneScale
            }
    }

    private func layoutSizes(for geoSize: CGSize, count: Int) -> CGSize {
        let safeCount = max(count, 1)
        let countCGFloat = CGFloat(safeCount)
        let rawWidth = geoSize.width / (countCGFloat + 1)
        let clampedWidth = min(max(rawWidth, 260), 420)
        let cardHeight = min(geoSize.height * 0.75, clampedWidth * 1.5)
        return CGSize(width: clampedWidth, height: cardHeight)
    }
}

private struct CardView: View {
    let card: DivineMode.Card
    let size: CGSize
    let player: AVPlayer?
    let showBorder: Bool
    let cornerRadius: CGFloat

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
                        .aspectRatio(2/3, contentMode: .fill)
                        .rotationEffect(.degrees(card.isFlipped ? 180 : 0))
                        .clipped()
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
        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 4)
    }
}

private struct CardBack: View {
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
