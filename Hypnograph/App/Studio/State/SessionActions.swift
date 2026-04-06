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
            onLoaded: { [weak self] hypnogram, url in
                self?.appendHypnogramToHistory(hypnogram, sourceURL: url)
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
        applyCompositionSelectionChanged(manual: true)
    }

    func appendHypnogramToHistory(_ hypnogram: Hypnogram, sourceURL: URL? = nil) {
        var mutableHypnogram = hypnogram
        mutableHypnogram.ensureEffectChainNames()

        liveMode = .edit

        let loadedCompositions = mutableHypnogram.compositions
        guard !loadedCompositions.isEmpty else { return }

        EffectChainLibraryActions.importChainsFromSession(mutableHypnogram, into: effectsSession)
        appendLoadedCompositions(loadedCompositions)
        copyDocumentContext(from: mutableHypnogram)
        applyCurrentHypnogramDocumentContextToRuntime()
        assignSaveTargetIfUnambiguous(sourceURL, for: loadedCompositions)
        pruneSaveTargetsToCurrentHistory()
        state.setLoopCurrentCompositionMode(true)
    }
}
