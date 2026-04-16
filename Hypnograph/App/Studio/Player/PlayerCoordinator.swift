import AVFoundation
import CoreMedia
import Foundation
import HypnoCore

@MainActor
final class PlayerCoordinator {
    var contentView: PlayerContentView?
    var stillClipTimer: Timer?
    var compositionID: String?
    var bindingUpdateToken: UInt64 = 0
    var currentTask: Task<Void, Never>?
    var lastPauseState: Bool?
    var lastEffectsCounter: Int?
    var lastSessionRevision: Int?
    var playRate: Float = 0.8
    var lastAppliedPlayRate: Float?
    var transitionDuration: Double = 1.5
    var lastVolume: Float?
    var endBehavior: Studio.PlayerEndBehavior = .advanceAcrossCompositions(loopAtSequenceEnd: false, generateAtSequenceEnd: true)
    var onCompositionEnded: (() -> Bool)?
    var isAllStillImages: Bool = false
    var lastRenderedComposition: Composition?
    /// Whether this is the first composition load (no transition needed)
    var isFirstLoad: Bool = true
    /// Use a sentinel to distinguish "never set" from "set to nil (system default)"
    private static let notSetSentinel = "___NOT_SET___"
    var lastAudioDeviceUID: String? = notSetSentinel
    /// Observers for player item end notifications
    var endObservers: [Any] = []
    /// Observers for per-player time updates (used for pre-end advancing)
    var timeObservers: [Any] = []
    /// Guard so we request auto-advance at most once per active composition.
    /// Reset when compositionID changes (new composition loaded).
    var didRequestPreEndAdvance: Bool = false
    /// Prevent runaway auto-advance while a new composition is being built/transitioned in.
    /// If the current composition ends again before the next composition is ready, we loop the current composition
    /// instead of requesting another advance. Cleared when transition completes.
    var isAutoAdvanceInFlight: Bool = false
    /// True while the user is manually scrubbing the timeline playhead.
    var isTimelineScrubbing: Bool = false
    /// Seek to apply once a rebuilt composition has fully become the active slot.
    var pendingPostLoadSourceTime: CMTime?
    /// Suppress outgoing/current player time reports while a composition handoff is in flight.
    var suppressCurrentTimeReporting: Bool = false

    func audioDeviceChanged(to newUID: String?) -> Bool {
        if lastAudioDeviceUID == Self.notSetSentinel { return true }
        return lastAudioDeviceUID != newUID
    }

    func removeEndObservers() {
        for observer in endObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        endObservers.removeAll()
    }

    func removeTimeObservers() {
        guard let contentView else { return }
        for (idx, observer) in timeObservers.enumerated() {
            if idx < contentView.allPlayers.count {
                contentView.allPlayers[idx].removeTimeObserver(observer)
            } else {
                for player in contentView.allPlayers {
                    player.removeTimeObserver(observer)
                }
            }
        }
        timeObservers.removeAll()
    }

    func beginBindingUpdateCycle() -> UInt64 {
        bindingUpdateToken &+= 1
        return bindingUpdateToken
    }
}
