//
//  PlayerActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Studio {
    var loopMode: PlayerLoopMode {
        state.settings.loopMode
    }

    var isLoopCompositionEnabled: Bool {
        loopMode == .composition
    }

    var isLoopSequenceEnabled: Bool {
        loopMode == .sequence
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
        replaceDefaultHypnogramWithNewComposition()
    }

    func newComposition() {
        prepareForManualGenerationAction()
        insertNewCompositionAfterCurrentAndSelect(manual: true)
    }

    /// Send current hypnogram to live display
    func sendToLivePlayer() {
        livePlayer.send(
            composition: currentComposition.copyForExport(),
            hypnogramEffectChain: currentHypnogramEffectChain.clone(),
            aspectRatio: currentHypnogramAspectRatio,
            outputResolution: currentHypnogramOutputResolution,
            sourceFraming: currentHypnogramSourceFraming,
            transitionStyle: currentCompositionTransitionStyle,
            transitionDuration: currentCompositionTransitionDuration
        )
    }

    func toggleHUD() {
        _ = panels.togglePanel("hudPanel")
    }

    func togglePause() {
        activePlayer.togglePause()
    }

    func setLoopMode(_ mode: PlayerLoopMode) {
        state.setLoopMode(mode)
    }

    func cycleLoopMode() {
        let nextMode: PlayerLoopMode
        switch loopMode {
        case .off:
            nextMode = .composition
        case .composition:
            nextMode = .sequence
        case .sequence:
            nextMode = .off
        }
        setLoopMode(nextMode)
    }

    func toggleCompositionLoopMode() {
        switch loopMode {
        case .off:
            setLoopMode(.composition)
        case .composition, .sequence:
            setLoopMode(.off)
        }
    }

    func toggleSequenceLoopMode() {
        setLoopMode(isLoopSequenceEnabled ? .off : .sequence)
    }

    func toggleGenerateAtEnd() {
        let newValue = !isGenerateAtEndEnabled
        state.setGenerateAtEnd(newValue)
    }
}
