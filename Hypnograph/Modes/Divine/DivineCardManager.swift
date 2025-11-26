//
//  DivineCardManager.swift
//  Hypnograph
//
//  Handles Divine card stack, gestures, and clip -> still conversion.
//  Owns DivinePlayerManager internally and exposes card-centric APIs.
//

import Foundation
import Combine
import CoreGraphics
import CoreMedia
import AVFoundation

final class DivineCardManager: ObservableObject {

    // Public-facing state
    @Published private(set) var cards: [DivineCard] = []
    @Published private(set) var currentIndex: Int = 0

    private let state: HypnographState
    private let playerManager = DivinePlayerManager()

    // TODO: Move into settings, e.g.: "modes:" [ { "Divine": { "allowReversed": true } } ]
    private var allowReversed: Bool = false

    // Layout context for initial card placement
    private var viewportSize: CGSize = .zero
    private var cardSize: CGSize = .zero

    init(state: HypnographState) {
        self.state = state
        // Don't add initial card here - it will use wrong library before per-mode settings load
        // Initial card is added when mode is first displayed (see DivineMode.makeDisplayView)
    }

    // MARK: - Layout

    func updateLayout(viewport: CGSize, cardSize: CGSize) {
        self.viewportSize = viewport
        self.cardSize = cardSize
    }

    // MARK: - Lifecycle helpers

    func reset() {
        playerManager.clearAllPlayers()
        cards.removeAll()
        currentIndex = 0
    }

    func addCardAtOffset(offset: CGSize) {
        guard let card = makeCard(offset: offset) else { return }
        cards.append(card)
        currentIndex = cards.count - 1
    }

    func addCardAtOffsetAtCenter() {
        // Jitter radius around center (0–50px)
        let jitter: CGFloat = 50
        let dx = CGFloat.random(in: -jitter...jitter)
        let dy = CGFloat.random(in: -jitter...jitter)
        let offset = CGSize(width: dx, height: dy)
        addCardAtOffset(offset: offset)
    }

    func deleteCurrent() {
        guard !cards.isEmpty, currentIndex < cards.count else { return }
        let id = cards[currentIndex].id
        playerManager.clearPlayer(for: id)
        cards.remove(at: currentIndex)
        if currentIndex >= cards.count {
            currentIndex = max(0, cards.count - 1)
        }
    }

    // MARK: - Source navigation

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

    // MARK: - Internals

    private func cardRect(for card: DivineCard) -> CGRect {
        // Assume cards are centered in the viewport plus offset/dragOffset
        let center = CGPoint(
            x: viewportSize.width / 2 + card.offset.width + card.dragOffset.width,
            y: viewportSize.height / 2 + card.offset.height + card.dragOffset.height
        )

        let origin = CGPoint(
            x: center.x - cardSize.width / 2,
            y: center.y - cardSize.height / 2
        )

        return CGRect(origin: origin, size: cardSize)
    }

    private func isCardOverlapped(at index: Int) -> Bool {
        guard index >= 0 && index < cards.count else { return false }

        let targetRect = cardRect(for: cards[index])

        // Any later (higher z-order) card overlapping this one = overlapped.
        for i in (index + 1)..<cards.count {
            let otherRect = cardRect(for: cards[i])
            if targetRect.intersects(otherRect) {
                return true
            }
        }

        return false
    }

    // Small helper to avoid index/assign boilerplate
    private func updateCard(id: UUID, _ mutate: (inout DivineCard, Int) -> Void) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        var card = cards[idx]
        mutate(&card, idx)
        cards[idx] = card
    }

    // MARK: - Interaction

    func handleTap(id: UUID) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }

        let isOverlapped = isCardOverlapped(at: idx)

        if isOverlapped {
            // Something is on top of this card → first bring to front, do not flip.
            _ = bringToFront(at: idx)
            return
        }

        // Not overlapped — safe to flip.
        let effectiveIndex: Int
        if idx == cards.count - 1 {
            effectiveIndex = idx
        } else {
            effectiveIndex = bringToFront(at: idx)
        }

        currentIndex = effectiveIndex
        handleTapAtIndex(effectiveIndex)
    }

    func handleLongPress(id: UUID) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = bringToFront(at: idx)
        var card = cards[newIdx]

        // --- Image-only clips: just reveal the still, no AVPlayer / spinner ---
        if card.clip.file.mediaKind == .image {
            if card.cgImage == nil {
                card.cgImage = grabStill(from: card.clip)
            }
            card.isRevealed = true
            card.isPlaying = false
            cards[newIdx] = card
            return
        }

        // --- Video clips: existing "press to play" semantics ---
        let player = playerManager.player(for: card) { [weak self] in
            self?.handlePlaybackEnded(for: card.id)
        }

        card.isRevealed = true
        card.isPlaying = true

        player.seek(to: card.clip.startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()

        cards[newIdx] = card
    }

    func updateDrag(id: UUID, translation: CGSize) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = bringToFront(at: idx)
        var card = cards[newIdx]
        card.dragOffset = translation
        cards[newIdx] = card
    }

    func endDrag(id: UUID, translation: CGSize) {
        updateCard(id: id) { card, _ in
            card.offset = card.offset + translation
            card.dragOffset = .zero
        }
    }

    // MARK: - Playback access for the view

    /// Used by the SwiftUI view to embed players.
    /// We only return existing players here; creation happens in interactions.
    func player(forID id: UUID) -> AVPlayer? {
        playerManager.player(forID: id)
    }

    // MARK: - Internals

    private func handleTapAtIndex(_ index: Int) {
        guard index >= 0 && index < cards.count else { return }

        var card = cards[index]
        let file = card.clip.file
        let player = playerManager.player(forID: card.id)

        switch (card.isRevealed, card.isPlaying) {
        case (false, _):
            // Face-down → reveal still using last snapshot if available
            let snapshotTime = card.lastSnapshotTime ?? card.clip.startTime
            if card.cgImage == nil {
                card.cgImage = grabStill(from: card.clip, at: snapshotTime)
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
            // For images, snapshot is just the source image; grabStill handles both.
            card.cgImage = grabStill(from: card.clip, at: snapshotTime)
            card.isPlaying = false
            card.isRevealed = true
        }

        cards[index] = card
    }

    private func bringToFront(at index: Int) -> Int {
        guard index >= 0 && index < cards.count else { return index }
        let card = cards.remove(at: index)
        cards.append(card)
        currentIndex = cards.count - 1
        return currentIndex
    }

    private func handlePlaybackEnded(for id: UUID) {
        updateCard(id: id) { card, _ in
            let startTime = card.clip.startTime
            // Works for both video + image sources.
            card.cgImage = grabStill(from: card.clip, at: startTime)
            card.lastSnapshotTime = startTime
            card.isPlaying = false
            card.isRevealed = true
        }
    }

    private func makeCard(offset: CGSize) -> DivineCard? {
        let clipLength = max(3.0, state.settings.outputDuration.seconds)

        // Get all source files currently on the table
        let usedFiles = Set(cards.map { $0.clip.file.url })

        // Try to get a unique clip (not already on the table)
        var clip: VideoClip?
        let maxAttempts = 100 // Prevent infinite loop if library is small

        for _ in 0..<maxAttempts {
            if let candidate = state.library.randomClip(clipLength: clipLength) {
                if !usedFiles.contains(candidate.file.url) {
                    clip = candidate
                    break
                }
            }
        }

        // If we couldn't find a unique clip after maxAttempts, return nil
        guard let clip = clip else {
            print("⚠️ DivineMode: Could not find a unique card (all sources may be in use)")
            return nil
        }

        let cgImage = grabStill(from: clip)
        let flipped = allowReversed ? Bool.random() : false

        return DivineCard(
            clip: clip,
            cgImage: cgImage,
            isRevealed: false,
            isPlaying: false,
            isFlipped: flipped,
            offset: offset,
            dragOffset: .zero,
            lastSnapshotTime: clip.startTime
        )
    }

    // MARK: - Still grabbing

    /// Unified still-grab for Divine:
    /// - video clips: AVAssetImageGenerator at `time`
    /// - image clips: CGImage loaded once from disk (cached)
    private func grabStill(from clip: VideoClip, at time: CMTime? = nil) -> CGImage? {
        let file = clip.file

        // Image-backed sources: load CGImage once and cache it.
        if file.mediaKind == .image {
            return StillImageCache.cgImage(for: file.url)
        }

        // Video-backed sources: use AVAssetImageGenerator.
        let asset = AVURLAsset(url: file.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let t = time ?? clip.startTime

        do {
            var actual = CMTime.zero
            let imageRef = try generator.copyCGImage(at: t, actualTime: &actual)
            return imageRef
        } catch {
            print("DivineMode: failed to grab still from video: \(error)")
            return nil
        }
    }
}
