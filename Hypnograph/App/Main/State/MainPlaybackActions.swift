//
//  MainPlaybackActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Main {
    var isLoopCurrentClipEnabled: Bool {
        state.settings.playbackEndBehavior == .loopCurrentClip
    }

    func new() {
        // Clear frame buffer to prevent memory bloat from stored CIImages
        activePlayer.effectManager.clearFrameBuffer()

        // Clear image cache if it's getting large to prevent memory bloat
        let cacheSize = StillImageCache.cacheSize()
        if cacheSize.ciImages > 30 || cacheSize.cgImages > 30 {
            StillImageCache.clear()
        }

        appendNewClipAndSelect(manual: true)
    }

    /// Send current hypnogram to live display
    func sendToLivePlayer() {
        livePlayer.send(
            clip: activePlayer.currentHypnogram.copyForExport(),
            config: activePlayer.config
        )
    }

    func toggleHUD() {
        state.windowState.toggle("hud")
    }

    func togglePause() {
        activePlayer.togglePause()
    }

    func toggleLoopCurrentClipMode() {
        state.toggleLoopCurrentClipMode()
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
