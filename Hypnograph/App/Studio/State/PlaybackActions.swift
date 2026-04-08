//
//  PlaybackActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore
import HypnoUI

@MainActor
extension Studio {
    var playbackLoopMode: PlaybackLoopMode {
        state.settings.playbackLoopMode
    }

    var isLoopCompositionEnabled: Bool {
        playbackLoopMode == .composition
    }

    var isLoopSequenceEnabled: Bool {
        playbackLoopMode == .sequence
    }

    var isGenerateAtEndEnabled: Bool {
        state.settings.generateAtEnd
    }

    private func prepareForManualGenerationAction() {
        // Clear frame buffer to prevent memory bloat from stored CIImages
        activePlayer.effectManager.clearFrameBuffer()

        // Clear image cache if it's getting large to prevent memory bloat
        let cacheSize = StillImageCache.cacheSize()
        if cacheSize.ciImages > 30 || cacheSize.cgImages > 30 {
            StillImageCache.clear()
        }
    }

    func new() {
        guard confirmReplacingWorkingHypnogramIfNeeded(
            actionDescription: "creating a new sequence"
        ) else { return }
        prepareForManualGenerationAction()
        replaceHistoryWithNewComposition()
    }

    func newComposition() {
        prepareForManualGenerationAction()
        insertNewCompositionAfterCurrentAndSelect(manual: true)
    }

    /// Send current hypnogram to live display
    func sendToLivePlayer() {
        livePlayer.send(
            composition: currentComposition.copyForExport(),
            aspectRatio: currentHypnogramAspectRatio,
            outputResolution: currentHypnogramOutputResolution,
            sourceFraming: currentHypnogramSourceFraming,
            transitionStyle: currentHypnogramTransitionStyle,
            transitionDuration: currentHypnogramTransitionDuration
        )
    }

    func toggleHUD() {
        _ = panels.togglePanel("hudPanel")
    }

    func togglePause() {
        activePlayer.togglePause()
    }

    func setPlaybackLoopMode(_ mode: PlaybackLoopMode) {
        state.setPlaybackLoopMode(mode)
        let message: String
        switch mode {
        case .off:
            message = "Loop Off"
        case .composition:
            message = "Loop Composition"
        case .sequence:
            message = "Loop Sequence"
        }
        AppNotifications.show(message, flash: true, duration: 1.25)
    }

    func cyclePlaybackLoopMode() {
        let nextMode: PlaybackLoopMode
        switch playbackLoopMode {
        case .off:
            nextMode = .composition
        case .composition:
            nextMode = .sequence
        case .sequence:
            nextMode = .off
        }
        setPlaybackLoopMode(nextMode)
    }

    func toggleLoopCompositionMode() {
        switch playbackLoopMode {
        case .off:
            setPlaybackLoopMode(.composition)
        case .composition, .sequence:
            setPlaybackLoopMode(.off)
        }
    }

    func toggleLoopSequenceMode() {
        setPlaybackLoopMode(isLoopSequenceEnabled ? .off : .sequence)
    }

    func toggleGenerateAtEnd() {
        let newValue = !isGenerateAtEndEnabled
        state.setGenerateAtEnd(newValue)
        AppNotifications.show(newValue ? "Generate at End" : "Stop at End", flash: true, duration: 1.25)
    }
}
