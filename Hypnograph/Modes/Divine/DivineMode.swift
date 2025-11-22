import SwiftUI
import AVFoundation
import CoreMedia
import CoreGraphics

// Simple no-op renderer since Divine is view-only.
final class DivineNoopRenderer: HypnogramRenderer {
    func enqueue(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void) {
        completion(.failure(NSError(domain: "DivineMode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Rendering not supported for Divine mode."])))
    }
}

/// Tarot-style stills mode with drag-and-drop cards from a bottom-right deck.
final class DivineMode: ObservableObject, HypnographMode {
    struct Card: Identifiable {
        let id = UUID()
        var clip: VideoClip
        var cgImage: CGImage?
        var isRevealed: Bool
        var isPlaying: Bool
        var isFlipped: Bool
        var rotationQuarterTurns: Int = 0
        var offset: CGSize
        var dragOffset: CGSize
        var lastSnapshotTime: CMTime?
    }

    private let state: HypnogramState
    let renderQueue: RenderQueue

    private var players: [UUID: AVPlayer] = [:]
    private var endObservers: [UUID: Any] = [:]
    private var viewportSize: CGSize = .zero
    private var cardSize: CGSize = .zero

    @Published private(set) var cards: [Card] = []
    @Published private(set) var currentIndex: Int = 0

    init(state: HypnogramState) {
        self.state = state
        self.renderQueue = RenderQueue(renderer: DivineNoopRenderer())
        cards = []
        currentIndex = 0
    }

    // MARK: HypnographMode basics

    var currentSourceIndex: Int { currentIndex }
    var isSoloActive: Bool { false }
    var soloIndicatorText: String? { nil }

    func makeDisplayView(state: HypnogramState, renderQueue: RenderQueue) -> AnyView {
        AnyView(
            DivineView(
                cards: cards,
                onTap: { [weak self] id in self?.handleTap(id: id) },
                onLongPress: { [weak self] id in self?.handleLongPress(id: id) },
                onDragChanged: { [weak self] id, translation in self?.updateDrag(id: id, translation: translation) },
                onDragEnded: { [weak self] id, translation in self?.endDrag(id: id, translation: translation) },
                onLayoutUpdate: { [weak self] viewport, cardSize in
                    self?.viewportSize = viewport
                    self?.cardSize = cardSize
                },
                playerProvider: { [weak self] id in self?.players[id] }
            )
        )
    }

    func hudItems(state: HypnogramState, renderQueue: RenderQueue) -> [HUDItem] {
        [
            .text("Space: Clear table", order: 27),
        ]
    }

    func compositionCommands() -> [ModeCommand] { [] }
    func sourceCommands() -> [ModeCommand] { [] }

    // MARK: Lifecycle

    func new() { 
        clearTable()
        addCardAtRandom()
    }

    func save() { print("DivineMode: save not supported.") }

    // MARK: Source navigation

    func addSource() { addCardAtRandom() }

    func modeCommands() -> [ModeCommand] { [] }

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
        addCardAtRandom()
        // I like it better without this so you always have to draw a new card
        // refreshCard(at: currentIndex)
    }
    func acceptCandidate() {
        // irrelevant in this mode I think
        // handleTap(index: currentIndex)
    }

    func deleteCurrentSource() {
        guard !cards.isEmpty, currentIndex < cards.count else { return }
        clearPlayer(for: cards[currentIndex].id)
        cards.remove(at: currentIndex)
        if currentIndex >= cards.count { currentIndex = max(0, cards.count - 1) }
    }

    func excludeCurrentSource() {}

    func redeal() { clearTable() }

    // MARK: Effects / misc

    func cycleEffect() {}
    func toggleHUD() { state.toggleHUD() }
    func toggleSolo() {}

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        clearTable()
    }

    func cycleGlobalEffect() { state.renderHooks.cycleGlobalEffect() }
    func cycleSourceEffect() { state.renderHooks.cycleSourceEffect(for: currentIndex) }
    func clearAllEffects() {
        state.renderHooks.setGlobalEffect(nil)
        state.renderHooks.setSourceEffect(nil, for: currentIndex)
    }

    var globalEffectName: String { state.renderHooks.globalEffectName }
    var sourceEffectName: String { state.renderHooks.sourceEffectName(for: currentIndex) }

    func selectOrToggleSolo(index: Int) { selectSource(index: index) }

    // MARK: Helpers

    private func clearTable() {
        clearPlayers()
        cards = []
        currentIndex = 0
    }

    private func addCardAtRandom() {
        let padding: CGFloat = 20
        let halfW: CGFloat = max((viewportSize.width - cardSize.width) / 2 - padding, 0)
        let halfH: CGFloat = max((viewportSize.height - cardSize.height) / 2 - padding, 0)
        let offset = CGSize(
            width: halfW > 0 ? CGFloat.random(in: (-halfW)...halfW) : 0,
            height: halfH > 0 ? CGFloat.random(in: (-halfH)...halfH) : 0
        )
        addCard(offset: offset)
    }

    private func addCard(offset: CGSize) {
        guard let card = makeCard(offset: offset) else { return }
        cards.append(card)
        currentIndex = cards.count - 1
    }

    private func refreshCard(at index: Int) {
        guard index >= 0 && index < cards.count else { return }
        if let newCard = makeCard(offset: cards[index].offset) {
            clearPlayer(for: cards[index].id)
            cards[index] = newCard
        }
    }

    private func handleTap(index: Int) {
        guard index >= 0 && index < cards.count else { return }
        // If the card is not already on top, just bring it forward; user can tap again to interact.
        if index != cards.count - 1 {
            _ = bringToFront(at: index)
            return
        }

        var card = cards[index]
        let player = player(for: card)

        switch (card.isRevealed, card.isPlaying) {
        case (false, _):
            // Face-down → reveal still using last snapshot if available
            let snapshotTime = card.lastSnapshotTime ?? card.clip.startTime
            if card.cgImage == nil, let image = snapshot(for: card.clip, at: snapshotTime) {
                card.cgImage = image
            }
            card.isRevealed = true
            card.isPlaying = false
            player?.pause()
        case (true, false):
            // Face-up still → flip back down (keep snapshot/time)
            card.isRevealed = false
            card.isPlaying = false
            player?.pause()
        case (true, true):
            // Playing → pause and update snapshot, stay revealed
            player?.pause()
            let snapshotTime = player?.currentTime() ?? card.clip.startTime
            card.lastSnapshotTime = snapshotTime
            if let image = snapshot(for: card.clip, at: snapshotTime) {
                card.cgImage = image
            }
            card.isPlaying = false
            card.isRevealed = true
        }

        cards[index] = card
    }

    private func handleTap(id: UUID) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = bringToFront(at: idx)
        handleTap(index: newIdx)
    }

    private func handleLongPress(id: UUID) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = bringToFront(at: idx)
        var card = cards[newIdx]
        let player = player(for: card)

        card.isRevealed = true
        card.isPlaying = true
        if let p = player {
            seek(p, to: card.clip.startTime)
            p.play()
        }

        cards[newIdx] = card
    }

    private func updateDrag(id: UUID, translation: CGSize) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = bringToFront(at: idx)
        var card = cards[newIdx]
        card.dragOffset = translation
        cards[newIdx] = card
    }

    private func endDrag(id: UUID, translation: CGSize) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        var card = cards[idx]
        card.offset = card.offset + translation
        card.dragOffset = .zero
        cards[idx] = card
    }

    @discardableResult
    private func bringToFront(at index: Int) -> Int {
        guard index >= 0 && index < cards.count else { return index }
        let card = cards.remove(at: index)
        cards.append(card)
        currentIndex = cards.count - 1
        return currentIndex
    }

    private func makeCard(offset: CGSize) -> Card? {
        let clipLength = max(3.0, state.settings.outputDuration.seconds)
        guard let clip = state.library.randomClip(clipLength: clipLength) else { return nil }
        let cgImage = grabStill(from: clip)
        let flipped = Bool.random()

        return Card(
            clip: clip,
            cgImage: cgImage,
            isRevealed: false,
            isPlaying: false,
            isFlipped: flipped,
            rotationQuarterTurns: 0,
            offset: offset,
            dragOffset: .zero,
            lastSnapshotTime: clip.startTime
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

    private func snapshot(for clip: VideoClip, at time: CMTime) -> CGImage? {
        let asset = AVURLAsset(url: clip.file.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        do {
            var actual = CMTime.zero
            let imageRef = try generator.copyCGImage(at: time, actualTime: &actual)
            return imageRef
        } catch {
            print("DivineMode: failed to snapshot: \(error)")
            return nil
        }
    }

    private func player(for card: Card) -> AVPlayer? {
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
                // Use first frame as face after playback completes.
                let startTime = updated.clip.startTime
                if let image = self.snapshot(for: updated.clip, at: startTime) {
                    updated.cgImage = image
                }
                updated.lastSnapshotTime = updated.clip.startTime
                updated.isPlaying = false
                updated.isRevealed = true
                if let p = player {
                    self.seek(p, to: startTime)
                }
                self.cards[idx] = updated
            }
        }
        endObservers[card.id] = token

        return player
    }

    private func seek(_ player: AVPlayer, to time: CMTime) {
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func clearPlayer(for id: UUID) {
        if let token = endObservers[id], let player = players[id] {
            player.removeTimeObserver(token)
        }
        endObservers[id] = nil
        players[id]?.pause()
        players[id] = nil
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

// Shared helper for offset math
extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}
