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
            }
        }

        $hypnogramRevision
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleHistorySave()
                self?.markWorkingHypnogramDirtyIfNeeded()
            }
            .store(in: &historySaveCancellables)

        $currentCompositionIndex
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
        var history = hypnogram
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
        let compositions = hypnogram.compositions
        guard !compositions.isEmpty else { return "Composition --" }
        let displayIndex = max(0, min(currentCompositionIndex, compositions.count - 1)) + 1
        return "Composition \(displayIndex)"
    }

    var currentHistoryPositionText: String {
        let compositions = hypnogram.compositions
        guard !compositions.isEmpty else { return "--/--" }
        let displayIndex = max(0, min(currentCompositionIndex, compositions.count - 1)) + 1
        return "\(displayIndex)/\(compositions.count)"
    }

    var isViewingHistoryComposition: Bool {
        let count = hypnogram.compositions.count
        guard count > 1 else { return false }
        return currentCompositionIndex < (count - 1)
    }

    func enforceHistoryLimit() {
        guard isUsingDefaultWorkingHypnogram else { return }
        let limit = max(1, state.settings.historyLimit)
        let overflow = max(0, hypnogram.compositions.count - limit)
        guard overflow > 0 else { return }

        hypnogram.compositions.removeFirst(overflow)
        currentCompositionIndex = max(0, currentCompositionIndex - overflow)
        notifyHypnogramMutated()
    }

    func applyCompositionSelectionChanged(manual: Bool) {
        let selectedCompositionID = currentComposition.id
        compositionSelectionUpdateToken &+= 1
        let token = compositionSelectionUpdateToken
        compositionSelectionWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.compositionSelectionUpdateToken == token else { return }
            guard self.currentComposition.id == selectedCompositionID else { return }

            self.player.currentCompositionLoadFailure = nil
            self.clampCurrentSourceIndex()
            self.player.currentLayerTimeOffset = nil
            self.player.effectManager.clearFrameBuffer()
            self.player.effectManager.invalidateBlendAnalysis()
            self.notifyHypnogramChanged()

            if manual {
                self.flashHistoryIndicator()
            }
        }

        compositionSelectionWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func previousComposition() {
        if isLoopSequenceEnabled {
            guard !hypnogram.compositions.isEmpty else { return }
            persistCurrentCompositionPreviewIfNeeded()
            player.hasPendingGeneratedNextComposition = false
            player.currentCompositionLoadFailure = nil
            currentCompositionIndex = currentCompositionIndex > 0
                ? (currentCompositionIndex - 1)
                : (hypnogram.compositions.count - 1)
            applyCompositionSelectionChanged(manual: true)
            return
        }

        guard currentCompositionIndex > 0 else { return }
        persistCurrentCompositionPreviewIfNeeded()
        player.hasPendingGeneratedNextComposition = false
        player.currentCompositionLoadFailure = nil
        currentCompositionIndex -= 1
        applyCompositionSelectionChanged(manual: true)
    }

    func nextComposition() {
        if isLoopSequenceEnabled {
            guard !hypnogram.compositions.isEmpty else { return }
            persistCurrentCompositionPreviewIfNeeded()
            player.hasPendingGeneratedNextComposition = false
            player.currentCompositionLoadFailure = nil
            let nextIndex = currentCompositionIndex + 1
            currentCompositionIndex = nextIndex < hypnogram.compositions.count ? nextIndex : 0
            applyCompositionSelectionChanged(manual: true)
            return
        }

        let nextIndex = currentCompositionIndex + 1
        if nextIndex < hypnogram.compositions.count {
            persistCurrentCompositionPreviewIfNeeded()
            player.hasPendingGeneratedNextComposition = false
            player.currentCompositionLoadFailure = nil
            currentCompositionIndex = nextIndex
            applyCompositionSelectionChanged(manual: true)
        } else {
            guard !player.hasPendingGeneratedNextComposition else { return }
            player.hasPendingGeneratedNextComposition = true
            insertNewCompositionAfterCurrentAndSelect(manual: false)
        }
    }

    func jumpToComposition(at index: Int) {
        guard !hypnogram.compositions.isEmpty else { return }

        let clampedIndex = max(0, min(index, hypnogram.compositions.count - 1))
        guard clampedIndex != currentCompositionIndex else { return }

        persistCurrentCompositionPreviewIfNeeded()
        player.hasPendingGeneratedNextComposition = false
        player.currentCompositionLoadFailure = nil
        currentCompositionIndex = clampedIndex
        applyCompositionSelectionChanged(manual: true)
    }

    func deleteCurrentComposition() {
        deleteComposition(at: currentCompositionIndex)
    }

    func deleteComposition(at index: Int) {
        guard !hypnogram.compositions.isEmpty else { return }

        if hypnogram.compositions.count == 1 {
            if isUsingDefaultWorkingHypnogram {
                replaceHistoryWithNewComposition()
            } else {
                replaceCurrentCompositionWithNewComposition(manual: true)
            }
            applyCompositionSelectionChanged(manual: true)
            return
        }

        let clampedIndex = max(0, min(index, hypnogram.compositions.count - 1))
        hypnogram.compositions.remove(at: clampedIndex)

        if clampedIndex < currentCompositionIndex {
            currentCompositionIndex -= 1
        } else if clampedIndex == currentCompositionIndex {
            currentCompositionIndex = min(
                clampedIndex,
                max(0, hypnogram.compositions.count - 1)
            )
        }

        notifyHypnogramMutated()
        applyCompositionSelectionChanged(manual: true)
    }

    func clearHistory() {
        let composition = currentComposition
        hypnogram = makeHypnogramWithCurrentHypnogramContext(
            compositions: [composition],
            currentCompositionIndex: 0
        )
        currentCompositionIndex = 0
        notifyHypnogramMutated()
        applyCompositionSelectionChanged(manual: true)
    }

    private var clampedCurrentCompositionIndex: Int {
        max(0, min(currentCompositionIndex, max(0, hypnogram.compositions.count - 1)))
    }

    private func syncCurrentCompositionIndexIntoHypnogram() {
        hypnogram.currentCompositionIndex = clampedCurrentCompositionIndex
    }

    func persistCurrentCompositionPreviewIfNeeded() {
        let composition = currentComposition
        let compositionIndex = clampedCurrentCompositionIndex
        guard player.currentCompositionPreviewNeedsRefresh else { return }
        guard player.currentRenderedCompositionID == composition.id else { return }
        guard let frameSnapshot = currentFrameSnapshot() else { return }

        let compositionID = composition.id
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self,
                  let previewImages = CompositionPreviewImageCodec.makePreviewImages(from: frameSnapshot) else { return }

            Task { @MainActor in
                guard compositionIndex < self.hypnogram.compositions.count else { return }
                guard self.hypnogram.compositions[compositionIndex].id == compositionID else { return }

                self.hypnogram.compositions[compositionIndex].snapshot = previewImages.snapshotBase64
                self.hypnogram.compositions[compositionIndex].thumbnail = previewImages.thumbnailBase64
                self.player.currentCompositionPreviewNeedsRefresh = false
                self.player.suppressNextPreviewInvalidation = true
                self.performWithoutMarkingWorkingHypnogramDirty {
                    self.notifyHypnogramMutated()
                }
            }
        }
    }

    private func flashHistoryIndicator() {
        guard !hypnogram.compositions.isEmpty else { return }
        historyIndicatorText = currentHistoryPositionText

        historyIndicatorClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.historyIndicatorText = nil
        }
        historyIndicatorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }
}
