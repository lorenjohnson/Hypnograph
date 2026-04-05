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

    func new() {
        // Clear frame buffer to prevent memory bloat from stored CIImages
        activePlayer.effectManager.clearFrameBuffer()

        // Clear image cache if it's getting large to prevent memory bloat
        let cacheSize = StillImageCache.cacheSize()
        if cacheSize.ciImages > 30 || cacheSize.cgImages > 30 {
            StillImageCache.clear()
        }

        appendNewCompositionAndSelect(manual: true)
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
