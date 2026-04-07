//
//  PlaybackActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Studio {
    var isLoopCurrentCompositionEnabled: Bool {
        state.settings.playbackEndBehavior == .loopCurrentComposition
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
            composition: activePlayer.currentComposition.copyForExport(),
            config: activePlayer.config
        )
    }

    func toggleHUD() {
        _ = panels.togglePanel("hudPanel")
    }

    func togglePause() {
        activePlayer.togglePause()
    }

    func toggleLoopCurrentCompositionMode() {
        state.toggleLoopCurrentCompositionMode()
    }

    func nextSource() {
        activePlayer.nextSource()
    }

    func previousSource() {
        activePlayer.previousSource()
    }

    func selectSource(index: Int) {
        activePlayer.selectSource(index)
    }
}
