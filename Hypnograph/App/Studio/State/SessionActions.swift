//
//  SessionActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore
import HypnoUI

@MainActor
extension Studio {
    func openRecipe() {
        SessionFileActions.openSession(
            onLoaded: { [weak self] session in
                self?.appendSessionToHistory(session)
                AppNotifications.show("Recipe loaded", flash: true)
            },
            onFailure: {
                AppNotifications.show("Failed to load recipe", flash: true)
            }
        )
    }

    private func appendLoadedHypnograms(_ hypnograms: [Hypnogram]) {
        let oldCount = activePlayer.session.hypnograms.count
        activePlayer.session.hypnograms.append(contentsOf: hypnograms)
        activePlayer.currentHypnogramIndex = oldCount
        activePlayer.currentSourceIndex = -1
        activePlayer.notifySessionMutated()
        enforceHistoryLimit()
        applyClipSelectionChanged(manual: true)
    }

    func appendSessionToHistory(_ session: HypnographSession) {
        var mutableSession = session
        mutableSession.ensureEffectChainNames()

        liveMode = .edit

        let loadedHypnograms = mutableSession.hypnograms
        guard !loadedHypnograms.isEmpty else { return }

        EffectChainLibraryActions.importChainsFromSession(mutableSession, into: effectsSession)
        appendLoadedHypnograms(loadedHypnograms)
    }
}
