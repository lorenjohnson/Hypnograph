//  DivinePlayerManager.swift
//  Hypnograph
//
//  Manages AVPlayers + end observers for Divine cards.
//  Used *only* by DivineCardManager.

import Foundation
import AVFoundation
import CoreMedia

final class DivinePlayerManager {
    private var players: [UUID: AVPlayer] = [:]
    private var endObservers: [UUID: Any] = [:]

    /// Get or create a player for the given card.
    ///
    /// - Parameters:
    ///   - card: The card whose clip should be played.
    ///   - onPlaybackEnd: Called when playback naturally reaches the card's end time.
    func player(
        for card: DivineCard,
        onPlaybackEnd: @escaping () -> Void
    ) -> AVPlayer {
        if let existing = players[card.id] {
            return existing
        }

        let asset = card.clip.file.asset
        let item = AVPlayerItem(asset: asset)
        let endTime = CMTimeAdd(card.clip.startTime, card.clip.duration)
        item.forwardPlaybackEndTime = endTime

        let player = AVPlayer(playerItem: item)
        players[card.id] = player

        let token = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: endTime)],
            queue: DispatchQueue.main
        ) { [weak player] in
            // Just pause; card semantics are handled by DivineCardManager.
            player?.pause()
            onPlaybackEnd()
        }

        endObservers[card.id] = token
        return player
    }

    /// Lookup an existing player by card id (for the view).
    func player(forID id: UUID) -> AVPlayer? {
        players[id]
    }

    func clearPlayer(for id: UUID) {
        if let token = endObservers[id], let player = players[id] {
            player.removeTimeObserver(token)
        }
        endObservers[id] = nil
        players[id]?.pause()
        players[id] = nil
    }

    func clearAllPlayers() {
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
