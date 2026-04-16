//
//  CompositionPreviewActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Studio {
    func markCurrentCompositionPreviewNeedsRefresh() {
        guard !currentComposition.layers.isEmpty else {
            player.currentCompositionPreviewNeedsRefresh = false
            compositionPreviewPersistenceScheduler.cancel()
            return
        }

        player.currentCompositionPreviewNeedsRefresh = true
        scheduleCurrentCompositionPreviewPersistenceIfNeeded()
    }

    func syncCurrentCompositionPreviewPersistenceState() {
        compositionPreviewPersistenceScheduler.cancel()

        guard !hypnogram.compositions.isEmpty else {
            player.currentCompositionPreviewNeedsRefresh = false
            return
        }

        let composition = currentComposition
        let needsRefresh = !composition.layers.isEmpty
            && (composition.snapshot == nil || composition.thumbnail == nil)
        player.currentCompositionPreviewNeedsRefresh = needsRefresh

        if needsRefresh {
            scheduleCurrentCompositionPreviewPersistenceIfNeeded()
        }
    }

    func scheduleCurrentCompositionPreviewPersistenceIfNeeded() {
        guard player.currentCompositionPreviewNeedsRefresh else { return }

        let delay = ThumbnailWorkPolicy.compositionPreviewPersistenceDelay(
            isPlayerActive: !player.isPaused
        )

        compositionPreviewPersistenceScheduler.schedule(after: delay) { [weak self] in
            self?.persistCurrentCompositionPreviewIfNeeded()
        }
    }

    func persistCurrentCompositionPreviewIfNeeded() {
        guard player.currentCompositionPreviewNeedsRefresh else { return }

        compositionPreviewPersistenceScheduler.cancel()

        let composition = currentComposition
        guard !composition.layers.isEmpty else {
            player.currentCompositionPreviewNeedsRefresh = false
            return
        }

        let compositionID = composition.id

        Task(priority: ThumbnailWorkPolicy.compositionPreviewTaskPriority) { [weak self] in
            guard let previewImages = await CompositionPreviewGenerator.makePreviewImages(for: composition) else {
                return
            }

            await MainActor.run {
                guard let self else { return }
                guard let compositionIndex = self.hypnogram.compositions.firstIndex(where: { $0.id == compositionID }) else {
                    return
                }

                self.hypnogram.compositions[compositionIndex].snapshot = previewImages.snapshotBase64
                self.hypnogram.compositions[compositionIndex].thumbnail = previewImages.thumbnailBase64

                if self.currentComposition.id == compositionID {
                    self.player.currentCompositionPreviewNeedsRefresh = false
                }

                self.performWithoutMarkingWorkingHypnogramDirty {
                    self.notifyHypnogramMutated()
                }
            }
        }
    }
}
