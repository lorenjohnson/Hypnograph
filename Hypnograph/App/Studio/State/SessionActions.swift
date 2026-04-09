//
//  SessionActions.swift
//  Hypnograph
//

import Foundation
import AppKit
import HypnoCore
import HypnoUI

@MainActor
extension Studio {
    func openHypnogram() {
        HypnogramFileActions.openHypnogram(
            onLoaded: { [weak self] hypnogram, url in
                _ = self?.openHypnogramAsWorkingDocument(hypnogram, sourceURL: url)
            },
            onFailure: {
                AppNotifications.show("Failed to load hypnogram", flash: true)
            }
        )
    }

    @discardableResult
    func openHypnogramAsWorkingDocument(_ hypnogram: Hypnogram, sourceURL: URL) -> Bool {
        guard confirmReplacingWorkingHypnogramIfNeeded(
            actionDescription: "opening another hypnogram"
        ) else { return false }
        activateWorkingHypnogram(hypnogram, sourceURL: sourceURL)
        AppNotifications.show("Loaded \(sourceURL.lastPathComponent)", flash: true)
        return true
    }

    func activateWorkingHypnogram(_ hypnogram: Hypnogram, sourceURL: URL?) {
        var mutableHypnogram = hypnogram
        mutableHypnogram.ensureEffectChainNames()

        liveMode = .edit

        guard !mutableHypnogram.compositions.isEmpty else { return }

        EffectChainLibraryActions.importChainsFromSession(mutableHypnogram, into: effectsSession)
        performWithoutMarkingWorkingHypnogramDirty {
            setHypnogram(mutableHypnogram)
            setActiveWorkingHypnogramURL(sourceURL)
            clearUnsavedWorkingHypnogramChanges()
            clearAllSaveTargets()
            applyCurrentHypnogramDocumentContextToRuntime()
            player.currentLayerIndex = 0
            player.currentCompositionLoadFailure = nil
            player.hasPendingGeneratedNextComposition = false
        }
        player.effectManager.clearFrameBuffer()
        notifyHypnogramChanged()
    }

    func confirmReplacingWorkingHypnogramIfNeeded(actionDescription: String) -> Bool {
        guard !isUsingDefaultHypnogram else {
            saveDefaultHypnogram(synchronous: true)
            return true
        }
        guard hasUnsavedWorkingHypnogramChanges else { return true }
        guard let currentURL = activeWorkingHypnogramURL else { return true }

        let alert = NSAlert()
        alert.messageText = "Save Sequence Changes?"
        alert.informativeText = "The current sequence has unsaved changes. Save them before \(actionDescription)?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveWorkingHypnogram(to: currentURL, showSuccessNotification: false)
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}
