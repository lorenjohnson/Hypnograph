//
//  HistoryActions.swift
//  Hypnograph
//

import Foundation
import Combine
import AppKit
import HypnoCore
import HypnoUI

@MainActor
extension Studio {
    func setupHistoryPersistence() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveHistory(synchronous: true)
                self?.state.settingsStore.save(synchronous: true)
                self?.state.appSettingsStore.save(synchronous: true)
            }
        }

        player.$hypnogramRevision
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleHistorySave()
                self?.markWorkingHypnogramDirtyIfNeeded()
            }
            .store(in: &historySaveCancellables)

        player.$currentCompositionIndex
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleHistorySave()
                self?.syncCurrentCompositionIndexIntoHypnogram()
            }
            .store(in: &historySaveCancellables)
    }

    private func scheduleHistorySave() {
        historySaveTimer?.invalidate()
        historySaveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveHistory(synchronous: false)
            }
        }
    }

    func saveHistory(synchronous: Bool) {
        guard isUsingDefaultWorkingHypnogram else { return }
        syncCurrentHypnogramDocumentContextFromRuntime()
        var history = player.hypnogram
        history.currentCompositionIndex = clampedCurrentCompositionIndex
        history.snapshot = nil
        historyPersistenceService.save(
            history,
            url: Environment.historyURL,
            historyLimit: state.settings.historyLimit,
            synchronous: synchronous
        )
    }

    func restoreHistory() {
        if let history = historyPersistenceService.load(
            url: Environment.historyURL,
            historyLimit: state.settings.historyLimit
        ),
           !history.hypnogram.compositions.isEmpty {
            let restoredIndex =
                history.hypnogram.currentCompositionIndex
                ?? history.legacySelectedCompositionIndex
                ?? 0
            var restoredHypnogram = history.hypnogram
            restoredHypnogram.currentCompositionIndex = max(0, min(restoredIndex, history.hypnogram.compositions.count - 1))
            activateWorkingHypnogram(restoredHypnogram, sourceURL: nil)
            print("📼 Restored composition history (\(history.hypnogram.compositions.count) compositions)")
            return
        }

        replaceHistoryWithNewComposition()
    }

    var currentCompositionIndicatorText: String {
        let compositions = player.hypnogram.compositions
        guard !compositions.isEmpty else { return "Composition --" }
        let displayIndex = max(0, min(player.currentCompositionIndex, compositions.count - 1)) + 1
        return "Composition \(displayIndex)"
    }

    var currentHistoryPositionText: String {
        let compositions = player.hypnogram.compositions
        guard !compositions.isEmpty else { return "--/--" }
        let displayIndex = max(0, min(player.currentCompositionIndex, compositions.count - 1)) + 1
        return "\(displayIndex)/\(compositions.count)"
    }

    var isViewingHistoryComposition: Bool {
        let count = player.hypnogram.compositions.count
        guard count > 1 else { return false }
        return player.currentCompositionIndex < (count - 1)
    }

    func enforceHistoryLimit() {
        guard isUsingDefaultWorkingHypnogram else { return }
        let limit = max(1, state.settings.historyLimit)
        let overflow = max(0, player.hypnogram.compositions.count - limit)
        guard overflow > 0 else { return }

        player.hypnogram.compositions.removeFirst(overflow)
        player.currentCompositionIndex = max(0, player.currentCompositionIndex - overflow)
        player.notifyHypnogramMutated()
    }

    func applyCompositionSelectionChanged(manual: Bool) {
        let selectedCompositionID = player.currentComposition.id
        compositionSelectionUpdateToken &+= 1
        let token = compositionSelectionUpdateToken
        compositionSelectionWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.compositionSelectionUpdateToken == token else { return }
            guard self.player.currentComposition.id == selectedCompositionID else { return }

            self.player.currentCompositionLoadFailure = nil
            self.player.clampCurrentSourceIndex()
            self.player.currentLayerTimeOffset = nil
            self.player.effectManager.clearFrameBuffer()
            self.player.effectManager.invalidateBlendAnalysis()
            self.player.notifyHypnogramChanged()

            if manual {
                self.flashHistoryIndicator()
            }
        }

        compositionSelectionWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func previousComposition() {
        if isLoopSequenceEnabled {
            guard !player.hypnogram.compositions.isEmpty else { return }
            persistCurrentCompositionPreviewIfNeeded()
            player.hasPendingGeneratedNextComposition = false
            player.currentCompositionLoadFailure = nil
            player.currentCompositionIndex = player.currentCompositionIndex > 0
                ? (player.currentCompositionIndex - 1)
                : (player.hypnogram.compositions.count - 1)
            applyCompositionSelectionChanged(manual: true)
            return
        }

        guard player.currentCompositionIndex > 0 else { return }
        persistCurrentCompositionPreviewIfNeeded()
        player.hasPendingGeneratedNextComposition = false
        player.currentCompositionLoadFailure = nil
        player.currentCompositionIndex -= 1
        applyCompositionSelectionChanged(manual: true)
    }

    func nextComposition() {
        if isLoopSequenceEnabled {
            guard !player.hypnogram.compositions.isEmpty else { return }
            persistCurrentCompositionPreviewIfNeeded()
            player.hasPendingGeneratedNextComposition = false
            player.currentCompositionLoadFailure = nil
            let nextIndex = player.currentCompositionIndex + 1
            player.currentCompositionIndex = nextIndex < player.hypnogram.compositions.count ? nextIndex : 0
            applyCompositionSelectionChanged(manual: true)
            return
        }

        let nextIndex = player.currentCompositionIndex + 1
        if nextIndex < player.hypnogram.compositions.count {
            persistCurrentCompositionPreviewIfNeeded()
            player.hasPendingGeneratedNextComposition = false
            player.currentCompositionLoadFailure = nil
            player.currentCompositionIndex = nextIndex
            applyCompositionSelectionChanged(manual: true)
        } else {
            guard !player.hasPendingGeneratedNextComposition else { return }
            player.hasPendingGeneratedNextComposition = true
            insertNewCompositionAfterCurrentAndSelect(manual: false)
        }
    }

    func jumpToComposition(at index: Int) {
        guard !player.hypnogram.compositions.isEmpty else { return }

        let clampedIndex = max(0, min(index, player.hypnogram.compositions.count - 1))
        guard clampedIndex != player.currentCompositionIndex else { return }

        persistCurrentCompositionPreviewIfNeeded()
        player.hasPendingGeneratedNextComposition = false
        player.currentCompositionLoadFailure = nil
        player.currentCompositionIndex = clampedIndex
        applyCompositionSelectionChanged(manual: true)
    }

    func deleteCurrentComposition() {
        deleteComposition(at: player.currentCompositionIndex)
    }

    func deleteComposition(at index: Int) {
        guard !player.hypnogram.compositions.isEmpty else { return }

        if player.hypnogram.compositions.count == 1 {
            if isUsingDefaultWorkingHypnogram {
                replaceHistoryWithNewComposition()
            } else {
                replaceCurrentCompositionWithNewComposition(manual: true)
            }
            applyCompositionSelectionChanged(manual: true)
            return
        }

        let clampedIndex = max(0, min(index, player.hypnogram.compositions.count - 1))
        player.hypnogram.compositions.remove(at: clampedIndex)

        if clampedIndex < player.currentCompositionIndex {
            player.currentCompositionIndex -= 1
        } else if clampedIndex == player.currentCompositionIndex {
            player.currentCompositionIndex = min(
                clampedIndex,
                max(0, player.hypnogram.compositions.count - 1)
            )
        }

        player.notifyHypnogramMutated()
        applyCompositionSelectionChanged(manual: true)
    }

    func clearHistory() {
        let composition = player.currentComposition
        player.hypnogram = makeHypnogramWithCurrentDocumentContext(
            compositions: [composition],
            currentCompositionIndex: 0
        )
        player.currentCompositionIndex = 0
        player.notifyHypnogramMutated()
        applyCompositionSelectionChanged(manual: true)
    }

    private var clampedCurrentCompositionIndex: Int {
        max(0, min(player.currentCompositionIndex, max(0, player.hypnogram.compositions.count - 1)))
    }

    private func syncCurrentCompositionIndexIntoHypnogram() {
        player.hypnogram.currentCompositionIndex = clampedCurrentCompositionIndex
    }

    func persistCurrentCompositionPreviewIfNeeded() {
        let composition = player.currentComposition
        let compositionIndex = clampedCurrentCompositionIndex
        guard player.currentCompositionPreviewNeedsRefresh else { return }
        guard player.currentRenderedCompositionID == composition.id else { return }
        guard let frameSnapshot = currentFrameSnapshot() else { return }

        let compositionID = composition.id
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self,
                  let previewImages = CompositionPreviewImageCodec.makePreviewImages(from: frameSnapshot) else { return }

            Task { @MainActor in
                guard compositionIndex < self.player.hypnogram.compositions.count else { return }
                guard self.player.hypnogram.compositions[compositionIndex].id == compositionID else { return }

                self.player.hypnogram.compositions[compositionIndex].snapshot = previewImages.snapshotBase64
                self.player.hypnogram.compositions[compositionIndex].thumbnail = previewImages.thumbnailBase64
                self.player.currentCompositionPreviewNeedsRefresh = false
                self.player.suppressNextPreviewInvalidation = true
                self.performWithoutMarkingWorkingHypnogramDirty {
                    self.player.notifyHypnogramMutated()
                }
            }
        }
    }

    private func flashHistoryIndicator() {
        guard !player.hypnogram.compositions.isEmpty else { return }
        historyIndicatorText = currentHistoryPositionText

        historyIndicatorClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.historyIndicatorText = nil
        }
        historyIndicatorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }
}
