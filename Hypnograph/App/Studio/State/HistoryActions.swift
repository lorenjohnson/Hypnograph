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

        player.$hypnogramRevision
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleHistorySave()
            }
            .store(in: &historySaveCancellables)

        player.$currentCompositionIndex
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleHistorySave()
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
        let history = HistoryFile(
            compositions: player.hypnogram.compositions,
            currentCompositionIndex: player.currentCompositionIndex
        )
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
           !history.compositions.isEmpty {
            let hypnogram = Hypnogram(compositions: history.compositions)
            player.hypnogram = hypnogram
            player.currentCompositionIndex = history.currentCompositionIndex
            player.notifyHypnogramMutated()
            player.currentLayerIndex = -1
            player.effectManager.clearFrameBuffer()
            player.notifyHypnogramChanged()
            print("📼 Restored composition history (\(history.compositions.count) compositions)")
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

    var timelinePlaybackRate: Double {
        get { Self.normalizedTimelinePlaybackRate(state.settings.timelinePlaybackRate) }
        set {
            let normalized = Self.normalizedTimelinePlaybackRate(newValue)
            if abs(normalized - state.settings.timelinePlaybackRate) < 0.0001 {
                return
            }
            state.settingsStore.update { $0.timelinePlaybackRate = normalized }
        }
    }

    var timelinePlaybackControlValue: Double {
        get { Self.timelineControlValue(fromRate: timelinePlaybackRate) }
        set { timelinePlaybackRate = Self.timelineRate(fromControlValue: newValue, reverse: isTimelinePlaybackReverse) }
    }

    var isTimelinePlaybackReverse: Bool {
        get { timelinePlaybackRate < 0 }
        set {
            let magnitude = abs(timelinePlaybackRate)
            let direction = newValue ? -1.0 : 1.0
            timelinePlaybackRate = direction * magnitude
        }
    }

    var timelinePlaybackDirection: Int {
        timelinePlaybackRate < 0 ? -1 : 1
    }

    private static func normalizedTimelinePlaybackRate(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        let direction = value < 0 ? -1.0 : 1.0
        let magnitude = min(max(abs(value), 1.0), 20.0)
        return direction * magnitude
    }

    private static func timelineControlValue(fromRate rate: Double) -> Double {
        let normalized = normalizedTimelinePlaybackRate(rate)
        let magnitude = abs(normalized)
        let position = ((magnitude - 1.0) / 19.0) * 20.0
        return min(max(position, 0.0), 20.0)
    }

    private static func timelineRate(fromControlValue value: Double, reverse: Bool) -> Double {
        let clamped = min(max(value, 0.0), 20.0)
        let magnitude = 1.0 + (clamped / 20.0) * 19.0
        return (reverse ? -1.0 : 1.0) * magnitude
    }

    func enforceHistoryLimit() {
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
            self.player.currentClipTimeOffset = nil
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
        guard player.currentCompositionIndex > 0 else { return }
        player.hasPendingGeneratedNextComposition = false
        player.currentCompositionLoadFailure = nil
        player.currentCompositionIndex -= 1
        applyCompositionSelectionChanged(manual: true)
    }

    func nextComposition() {
        let nextIndex = player.currentCompositionIndex + 1
        if nextIndex < player.hypnogram.compositions.count {
            player.hasPendingGeneratedNextComposition = false
            player.currentCompositionLoadFailure = nil
            player.currentCompositionIndex = nextIndex
            applyCompositionSelectionChanged(manual: true)
        } else {
            guard !player.hasPendingGeneratedNextComposition else { return }
            player.hasPendingGeneratedNextComposition = true
            appendNewCompositionAndSelect(manual: false)
        }
    }

    func deleteCurrentComposition() {
        guard !player.hypnogram.compositions.isEmpty else { return }

        if player.hypnogram.compositions.count == 1 {
            replaceHistoryWithNewComposition()
            applyCompositionSelectionChanged(manual: true)
            return
        }

        let index = player.currentCompositionIndex
        player.hypnogram.compositions.remove(at: index)
        if player.currentCompositionIndex >= player.hypnogram.compositions.count {
            player.currentCompositionIndex = max(0, player.hypnogram.compositions.count - 1)
        }
        player.notifyHypnogramMutated()
        applyCompositionSelectionChanged(manual: true)
    }

    func clearHistory() {
        let composition = player.currentComposition
        player.hypnogram = Hypnogram(compositions: [composition])
        player.currentCompositionIndex = 0
        player.notifyHypnogramMutated()
        applyCompositionSelectionChanged(manual: true)
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
