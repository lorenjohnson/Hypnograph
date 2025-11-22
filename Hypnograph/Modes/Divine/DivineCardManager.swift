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

    private let state: HypnogramState
    private let playerManager = DivinePlayerManager()

    // Layout context for initial card placement
    private var viewportSize: CGSize = .zero
    private var cardSize: CGSize = .zero

    init(state: HypnogramState) {
        self.state = state
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

    func addCardAtRandom() {
        let padding: CGFloat = 20
        let halfW: CGFloat = max((viewportSize.width - cardSize.width) / 2 - padding, 0)
        let halfH: CGFloat = max((viewportSize.height - cardSize.height) / 2 - padding, 0)
        let offset = CGSize(
            width: halfW > 0 ? CGFloat.random(in: (-halfW)...halfW) : 0,
            height: halfH > 0 ? CGFloat.random(in: (-halfH)...halfH) : 0
        )
        addCard(offset: offset)
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

    // MARK: - Interaction

    func handleTap(id: UUID) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = bringToFront(at: idx)
        handleTapAtIndex(newIdx)
    }

    func handleLongPress(id: UUID) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = bringToFront(at: idx)
        var card = cards[newIdx]

        // Ensure we have a player and wire playback-end semantics.
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
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        var card = cards[idx]
        card.offset = card.offset + translation
        card.dragOffset = .zero
        cards[idx] = card
    }

    // MARK: - Playback access for the view

    /// Used by the SwiftUI view to embed players.
    /// We only return existing players here; creation happens in interactions.
    func player(forID id: UUID) -> AVPlayer? {
        playerManager.player(forID: id)
    }

    // MARK: - Internals

    private func addCard(offset: CGSize) {
        guard let card = makeCard(offset: offset) else { return }
        cards.append(card)
        currentIndex = cards.count - 1
    }

    private func handleTapAtIndex(_ index: Int) {
        guard index >= 0 && index < cards.count else { return }

        var card = cards[index]
        // Only use an existing player if there is one.
        let player = playerManager.player(forID: card.id)

        switch (card.isRevealed, card.isPlaying) {
        case (false, _):
            // Face-down → reveal still using last snapshot if available
            let snapshotTime = card.lastSnapshotTime ?? card.clip.startTime
            if card.cgImage == nil,
               let image = grabStill(from: card.clip, at: snapshotTime) {
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
            if let image = grabStill(from: card.clip, at: snapshotTime) {
                card.cgImage = image
            }
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
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }

        var card = cards[idx]
        let startTime = card.clip.startTime

        if let image = grabStill(from: card.clip, at: startTime) {
            card.cgImage = image
        }
        card.lastSnapshotTime = startTime
        card.isPlaying = false
        card.isRevealed = true

        cards[idx] = card
    }

    private func makeCard(offset: CGSize) -> DivineCard? {
        let clipLength = max(3.0, state.settings.outputDuration.seconds)
        guard let clip = state.library.randomClip(clipLength: clipLength) else { return nil }
        let cgImage = grabStill(from: clip)
        let flipped = Bool.random()

        return DivineCard(
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

    // MARK: - Still grabbing

    private func grabStill(from clip: VideoClip, at time: CMTime? = nil) -> CGImage? {
        let asset = AVURLAsset(url: clip.file.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = time ?? clip.startTime

        do {
            var actual = CMTime.zero
            let imageRef = try generator.copyCGImage(at: time, actualTime: &actual)
            return imageRef
        } catch {
            print("DivineMode: failed to grab still: \(error)")
            return nil
        }
    }
}
