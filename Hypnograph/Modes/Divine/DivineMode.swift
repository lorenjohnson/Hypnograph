import SwiftUI
import AVFoundation
import AVKit
import CoreMedia
import CoreGraphics

// Simple no-op renderer since Divine is view-only.
final class DivineNoopRenderer: HypnogramRenderer {
    func enqueue(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void) {
        completion(.failure(NSError(domain: "DivineMode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Rendering not supported for Divine mode."])))
    }
}

/// Tarot-style stills mode with optional playback.
final class DivineMode: ObservableObject, HypnographMode {
    struct DivineCard: Identifiable {
        let id = UUID()
        var clip: VideoClip
        var cgImage: CGImage?
        var isRevealed: Bool
        var offset: CGSize
        var isFlipped: Bool
        var isPlaying: Bool
    }

    private let state: HypnogramState
    let renderQueue: RenderQueue
    private var players: [UUID: AVPlayer] = [:]
    private var endObservers: [UUID: Any] = [:]

    @Published private(set) var cards: [DivineCard] = []
    @Published private(set) var currentIndex: Int = 0

    init(state: HypnogramState) {
        self.state = state
        self.renderQueue = RenderQueue(renderer: DivineNoopRenderer())
        dealCards()
    }

    // MARK: HypnographMode basics

    var currentSourceIndex: Int { currentIndex }
    var isSoloActive: Bool { false }
    var soloIndicatorText: String? { nil }

    func makeDisplayView(state: HypnogramState, renderQueue: RenderQueue) -> AnyView {
        AnyView(
            DivineView(
                cards: cards,
                currentIndex: currentIndex,
                onTap: { [weak self] in self?.handleTap(index: $0) },
                onRedeal: { [weak self] in self?.redeal() },
                playerProvider: { [weak self] id in self?.players[id] }
            )
        )
    }

    func hudItems(state: HypnogramState, renderQueue: RenderQueue) -> [HUDItem] {
        [
            .text("Mode: Divine", order: 25, font: .headline),
            .text("Cards: \(cards.count)", order: 26),
            .text("Current: \(min(currentIndex + 1, cards.count))/\(max(cards.count, 1))", order: 27),
            .text("Space: Re-deal 3 cards", order: 28),
            .text("N: New image for current card", order: 46),
            .text(". : Add new card and select it", order: 47),
            .text("Return: Flip/Play current card", order: 48)
        ]
    }

    func compositionCommands() -> [ModeCommand] {
        return []
    }

    func sourceCommands() -> [ModeCommand] {
        return []
    }    // MARK: Lifecycle

    func new() {
        withAnimation(.easeInOut) {
            dealCards()
        }
    }

    func saveCurrentHypnogram() {
        print("DivineMode: save not supported.")
    }

    // MARK: Source navigation

    func addSource() {
        if let card = makeCard() {
            cards.append(card)
            currentIndex = cards.count - 1
        }
    }

    func nextSource() {
        guard !cards.isEmpty else { return }
        currentIndex = min(cards.count - 1, currentIndex + 1)
    }

    func previousSource() {
        guard !cards.isEmpty else { return }
        currentIndex = max(0, currentIndex - 1)
    }

    func selectSource(index: Int) {
        guard !cards.isEmpty else { return }
        currentIndex = max(0, min(cards.count - 1, index))
    }

    // MARK: Candidate / selection

    func nextCandidate() {
        refreshCard(at: currentIndex)
    }

    func acceptCandidate() {
        handleTap(index: currentIndex)
    }

    func deleteCurrentSource() {
        refreshCard(at: currentIndex, revealed: false)
    }

    func excludeCurrentSource() {}

    func redeal() {
        dealCards()
    }

    // MARK: Effects / misc

    func cycleEffect() {}
    func toggleHUD() { state.toggleHUD() }
    func toggleSolo() {}
    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        dealCards()
    }

    func cycleGlobalEffect() { state.renderHooks.cycleGlobalEffect() }
    func cycleSourceEffect() { state.renderHooks.cycleSourceEffect(for: currentIndex) }
    func clearAllEffects() {
        state.renderHooks.setGlobalEffect(nil)
        state.renderHooks.setSourceEffect(nil, for: currentIndex)
    }

    var globalEffectName: String { state.renderHooks.globalEffectName }
    var sourceEffectName: String { state.renderHooks.sourceEffectName(for: currentIndex) }

    func selectOrToggleSolo(index: Int) {
        selectSource(index: index)
    }

    // MARK: Helpers

    private func dealCards() {
        clearPlayers()
        cards = (0..<3).compactMap { _ in makeCard() }
        currentIndex = 0
    }

    private func refreshCard(at index: Int, revealed: Bool = false) {
        guard index >= 0 && index < cards.count else { return }
        if let newCard = makeCard(revealed: revealed) {
            cards[index] = newCard
        }
    }

    private func handleTap(index: Int) {
        guard index >= 0 && index < cards.count else { return }
        selectSource(index: index)

        var card = cards[index]
        let player = player(for: card)

        if !card.isRevealed {
            // Flip face-up, paused at start
            card.isRevealed = true
            card.isPlaying = false
            player?.pause()
            if let p = player { seek(p, to: card.clip.startTime) }
        } else if card.isPlaying {
            // Stop and flip back down
            player?.pause()
            if let p = player { seek(p, to: card.clip.startTime) }
            card.isPlaying = false
            card.isRevealed = false
        } else {
            // Face-up paused → start playing
            card.isPlaying = true
            card.isRevealed = true
            if let p = player {
                seek(p, to: card.clip.startTime)
                p.play()
            }
        }

        withAnimation(.easeInOut) {
            cards[index] = card
        }
    }

    private func makeCard(revealed: Bool = false) -> DivineCard? {
        let clipLength = max(3.0, state.settings.outputDuration.seconds)
        guard let clip = state.library.randomClip(clipLength: clipLength) else { return nil }
        let cgImage = grabStill(from: clip)
        let offset = CGSize(
            width: Double.random(in: -18...18),
            height: Double.random(in: -12...12)
        )
        let flipped = Bool.random()

        return DivineCard(
            clip: clip,
            cgImage: cgImage,
            isRevealed: revealed,
            offset: offset,
            isFlipped: flipped,
            isPlaying: false
        )
    }

    private func grabStill(from clip: VideoClip) -> CGImage? {
        let asset = AVURLAsset(url: clip.file.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = clip.startTime
        do {
            var actual = CMTime.zero
            let imageRef = try generator.copyCGImage(at: time, actualTime: &actual)
            return imageRef
        } catch {
            print("DivineMode: failed to grab still: \(error)")
            return nil
        }
    }

    private func player(for card: DivineCard) -> AVPlayer? {
        if let existing = players[card.id] {
            return existing
        }

        let asset = AVURLAsset(url: card.clip.file.url)
        let item = AVPlayerItem(asset: asset)
        let endTime = CMTimeAdd(card.clip.startTime, card.clip.duration)
        item.forwardPlaybackEndTime = endTime

        let player = AVPlayer(playerItem: item)
        seek(player, to: card.clip.startTime)
        players[card.id] = player

        let token = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) { [weak self, weak player] in
            guard let self else { return }
            player?.pause()
            if let idx = self.cards.firstIndex(where: { $0.id == card.id }) {
                var updated = self.cards[idx]
                updated.isPlaying = false
                self.cards[idx] = updated
            }
        }
        endObservers[card.id] = token

        return player
    }

    private func seek(_ player: AVPlayer, to time: CMTime) {
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func clearPlayers() {
        for (id, player) in players {
            if let token = endObservers[id] {
                player.removeTimeObserver(token)
            }
            player.pause()
        }
        players.removeAll()
        endObservers.removeAll()
    }
}

struct DivineView: View {
    let cards: [DivineMode.DivineCard]
    let currentIndex: Int
    let onTap: (Int) -> Void
    let onRedeal: () -> Void
    let playerProvider: (UUID) -> AVPlayer?

    var body: some View {
        GeometryReader { geo in
            let count = max(cards.count, 1)
            let spacing: CGFloat = 32
            let horizontalInset: CGFloat = 48

            let cardHeight = geo.size.height * 0.7
            let usableWidth = geo.size.width - (horizontalInset * 2) - spacing * CGFloat(max(count - 1, 0))
            let targetWidth = usableWidth / CGFloat(count)
            let cardWidth = min(max(targetWidth, 260), 420)
            let cardsWidth = CGFloat(count) * cardWidth + CGFloat(max(count - 1, 0)) * spacing
            let dynamicInset = max((geo.size.width - cardsWidth) / 2, horizontalInset)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                        CardView(
                            card: card,
                            isSelected: idx == currentIndex,
                            size: CGSize(width: cardWidth, height: cardHeight),
                            player: playerProvider(card.id)
                        )
                        .offset(card.offset)
                        // TODO:  A hack because I can't seem  to figure out
                        // how to just have this be an open frame
                        .frame(width: cardWidth, height: cardHeight + 100)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTap(idx)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, dynamicInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(Color.black)
    }

    private struct CardView: View {
        let card: DivineMode.DivineCard
        let isSelected: Bool
        let size: CGSize
        let player: AVPlayer?

        var body: some View {
            ZStack {
                if card.isRevealed, let cg = card.cgImage {
                    if let player {
                        CardPlayerView(player: player)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .rotationEffect(.degrees(card.isFlipped ? 180 : 0))
                    } else {
                        Image(decorative: cg, scale: 1.0, orientation: .up)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .rotationEffect(.degrees(card.isFlipped ? 180 : 0))
                            .clipped()
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    }
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color(red: 0.0, green: 0.6, blue: 0.65), Color(red: 0.0, green: 0.45, blue: 0.5)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            StripedPattern()
                                .opacity(0.15)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        )
                        .frame(width: size.width, height: size.height)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white, lineWidth: 12)
            )
            .rotation3DEffect(.degrees(card.isRevealed ? 0 : 180), axis: (x: 0, y: 1, z: 0))
            .animation(.easeInOut, value: card.isRevealed)
            .shadow(color: Color.black.opacity(0.5), radius: 6, x: 0, y: 4)
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

    /// AVPlayerView that forwards mouse events so SwiftUI tap gestures still work.
    private final class HitTransparentPlayerView: AVPlayerView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
