//
//  SequenceNavigationActions.swift
//  Hypnograph
//

import Foundation
import AppKit
import HypnoCore
import HypnoUI

@MainActor
extension Studio {
    var currentCompositionIndicatorText: String {
        let compositions = hypnogram.compositions
        guard !compositions.isEmpty else { return "Composition --" }
        let displayIndex = max(0, min(currentCompositionIndex, compositions.count - 1)) + 1
        return "Composition \(displayIndex)"
    }

    var currentCompositionPositionText: String {
        let compositions = hypnogram.compositions
        guard !compositions.isEmpty else { return "--/--" }
        let displayIndex = max(0, min(currentCompositionIndex, compositions.count - 1)) + 1
        return "\(displayIndex)/\(compositions.count)"
    }

    var isViewingEarlierComposition: Bool {
        let count = hypnogram.compositions.count
        guard count > 1 else { return false }
        return currentCompositionIndex < (count - 1)
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
                self.flashCompositionPositionIndicator()
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
            persistCurrentCompositionPreviewIfNeeded()
            player.hasPendingGeneratedNextComposition = true
            player.currentCompositionLoadFailure = nil
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
            if isUsingDefaultHypnogram {
                replaceDefaultHypnogramWithNewComposition()
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

    func moveComposition(sourceID: UUID, targetID: UUID) {
        guard sourceID != targetID else { return }

        var compositions = hypnogram.compositions
        guard let fromIndex = compositions.firstIndex(where: { $0.id == sourceID }) else { return }
        guard let toIndex = compositions.firstIndex(where: { $0.id == targetID }) else { return }
        guard fromIndex != toIndex else { return }

        let selectedCompositionID = currentComposition.id

        let movedComposition = compositions.remove(at: fromIndex)
        var destination = toIndex
        if fromIndex < toIndex {
            destination -= 1
        }
        compositions.insert(movedComposition, at: max(0, min(destination, compositions.count)))

        hypnogram.compositions = compositions

        if let selectedIndex = compositions.firstIndex(where: { $0.id == selectedCompositionID }) {
            currentCompositionIndex = selectedIndex
        }

        notifyHypnogramMutated()
    }

    func persistCurrentCompositionPreviewIfNeeded() {
        let composition = currentComposition
        let compositionIndex = max(0, min(currentCompositionIndex, max(0, hypnogram.compositions.count - 1)))
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

    private func flashCompositionPositionIndicator() {
        guard !hypnogram.compositions.isEmpty else { return }
        compositionPositionIndicatorText = currentCompositionPositionText

        compositionPositionIndicatorClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.compositionPositionIndicatorText = nil
        }
        compositionPositionIndicatorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }
}
