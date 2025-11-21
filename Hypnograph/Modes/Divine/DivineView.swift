import SwiftUI
import AVFoundation
import AVKit
import CoreGraphics

// MARK: - Divine View Hierarchy

public struct DivineView: View {
    let cards: [DivineMode.Card]
    let onTap: (UUID) -> Void
    let onDragChanged: (UUID, CGSize) -> Void
    let onDragEnded: (UUID, CGSize) -> Void
    let onAddFromDeck: (CGSize) -> Void
    let playerProvider: (UUID) -> AVPlayer?

    @State private var deckDrag: CGSize?

    public var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 32
            let count = max(cards.count, 1)
            let cardWidth = min(max(geo.size.width / CGFloat(count + 1), 260), 420)
            let cardHeight = min(geo.size.height * 0.75, cardWidth * 1.5)

            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let deckPadding: CGFloat = 48
            let deckSize = CGSize(width: cardWidth * 0.8, height: cardHeight * 0.8)
            let deckOrigin = CGPoint(
                x: geo.size.width - deckPadding - deckSize.width / 2,
                y: geo.size.height - deckPadding - deckSize.height / 2
            )
            let spawnOffset = CGSize(width: deckOrigin.x - center.x, height: deckOrigin.y - center.y)

            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { pair in
                    let idx = pair.offset
                    let card = pair.element
                    ZStack {
                        CardView(
                            card: card,
                            size: CGSize(width: cardWidth, height: cardHeight),
                            player: playerProvider(card.id)
                        )
                    }
                    .frame(width: cardWidth, height: cardHeight, alignment: .center)
                    .contentShape(Rectangle())
                    .offset(card.offset + card.dragOffset)
                    .onTapGesture { onTap(card.id) }
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

                // Deck
                CardBack()
                    .frame(width: deckSize.width, height: deckSize.height)
                    .position(deckOrigin)
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 4)
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            onAddFromDeck(spawnOffset)
                        }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                deckDrag = value.translation
                            }
                            .onEnded { value in
                                let finalOffset = spawnOffset + value.translation
                                onAddFromDeck(finalOffset)
                                deckDrag = nil
                            }
                    )
                    .zIndex(1000)

                // Ghost card while dragging from deck
                if let deckDrag {
                    CardBack()
                        .frame(width: deckSize.width, height: deckSize.height)
                        .position(
                            x: center.x + spawnOffset.width + deckDrag.width,
                            y: center.y + spawnOffset.height + deckDrag.height
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }
}

private struct CardView: View {
    let card: DivineMode.Card
    let size: CGSize
    let player: AVPlayer?

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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 12)
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
