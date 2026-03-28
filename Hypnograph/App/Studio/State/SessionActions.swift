//
//  SessionActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore
import HypnoUI

@MainActor
extension Studio {
    func openHypnogram() {
        HypnogramFileActions.openHypnogram(
            onLoaded: { [weak self] hypnogram in
                self?.appendHypnogramToHistory(hypnogram)
                AppNotifications.show("Hypnogram loaded", flash: true)
            },
            onFailure: {
                AppNotifications.show("Failed to load hypnogram", flash: true)
            }
        )
    }

    private func appendLoadedCompositions(_ compositions: [Composition]) {
        let oldCount = activePlayer.hypnogram.compositions.count
        activePlayer.hypnogram.compositions.append(contentsOf: compositions)
        activePlayer.currentCompositionIndex = oldCount
        activePlayer.currentLayerIndex = -1
        activePlayer.notifyHypnogramMutated()
        enforceHistoryLimit()
        applyClipSelectionChanged(manual: true)
    }

    func appendHypnogramToHistory(_ hypnogram: Hypnogram) {
        var mutableHypnogram = hypnogram
        mutableHypnogram.ensureEffectChainNames()

        liveMode = .edit

        let loadedCompositions = mutableHypnogram.compositions
        guard !loadedCompositions.isEmpty else { return }

        EffectChainLibraryActions.importChainsFromSession(mutableHypnogram, into: effectsSession)
        appendLoadedCompositions(loadedCompositions)
    }
}
