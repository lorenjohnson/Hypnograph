//
//  MainHistoryActions.swift
//  Hypnograph
//

import Foundation
import Combine
import AppKit
import HypnoCore
import HypnoUI

@MainActor
extension Main {
    func setupClipHistoryPersistence() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveClipHistory(synchronous: true)
                self?.state.settingsStore.save(synchronous: true)
            }
        }

        player.$sessionRevision
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleClipHistorySave()
            }
            .store(in: &clipHistorySaveCancellables)

        player.$currentHypnogramIndex
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleClipHistorySave()
            }
            .store(in: &clipHistorySaveCancellables)
    }

    private func scheduleClipHistorySave() {
        clipHistorySaveTimer?.invalidate()
        clipHistorySaveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveClipHistory(synchronous: false)
            }
        }
    }

    func saveClipHistory(synchronous: Bool) {
        let history = ClipHistoryFile(
            hypnograms: player.session.hypnograms,
            currentHypnogramIndex: player.currentHypnogramIndex
        )
        clipHistoryPersistenceService.save(
            history,
            url: Environment.clipHistoryURL,
            historyLimit: state.settings.historyLimit,
            synchronous: synchronous
        )
    }

    func restoreClipHistory() {
        if let history = clipHistoryPersistenceService.load(
            url: Environment.clipHistoryURL,
            historyLimit: state.settings.historyLimit
        ),
           !history.hypnograms.isEmpty {
            let session = HypnographSession(hypnograms: history.hypnograms)
            player.session = session
            player.currentHypnogramIndex = history.currentHypnogramIndex
            player.notifySessionMutated()
            player.currentSourceIndex = -1
            player.effectManager.clearFrameBuffer()
            player.notifySessionChanged()
            print("📼 Restored clip history (\(history.hypnograms.count) hypnograms)")
            return
        }

        replaceHistoryWithNewClip()
    }

    var currentClipIndicatorText: String {
        let clips = player.session.hypnograms
        guard !clips.isEmpty else { return "Clip --" }
        let displayIndex = max(0, min(player.currentHypnogramIndex, clips.count - 1)) + 1
        return "Clip \(displayIndex)"
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
        let overflow = max(0, player.session.hypnograms.count - limit)
        guard overflow > 0 else { return }

        player.session.hypnograms.removeFirst(overflow)
        player.currentHypnogramIndex = max(0, player.currentHypnogramIndex - overflow)
        player.notifySessionMutated()
    }

    func applyClipSelectionChanged(manual: Bool) {
        player.clampCurrentSourceIndex()
        player.currentClipTimeOffset = nil
        player.effectManager.clearFrameBuffer()
        player.effectManager.invalidateBlendAnalysis()
        player.notifySessionChanged()

        if manual {
            flashClipHistoryIndicator()
        }
    }

    func previousClip() {
        guard player.currentHypnogramIndex > 0 else { return }
        player.currentHypnogramIndex -= 1
        applyClipSelectionChanged(manual: true)
    }

    func nextClip() {
        let nextIndex = player.currentHypnogramIndex + 1
        if nextIndex < player.session.hypnograms.count {
            player.currentHypnogramIndex = nextIndex
            applyClipSelectionChanged(manual: true)
        } else {
            new()
        }
    }

    func deleteCurrentClip() {
        guard !player.session.hypnograms.isEmpty else { return }

        if player.session.hypnograms.count == 1 {
            replaceHistoryWithNewClip()
            applyClipSelectionChanged(manual: true)
            return
        }

        let index = player.currentHypnogramIndex
        player.session.hypnograms.remove(at: index)
        if player.currentHypnogramIndex >= player.session.hypnograms.count {
            player.currentHypnogramIndex = max(0, player.session.hypnograms.count - 1)
        }
        player.notifySessionMutated()
        applyClipSelectionChanged(manual: true)
    }

    func clearClipHistory() {
        let hypnogram = player.currentHypnogram
        player.session = HypnographSession(hypnograms: [hypnogram])
        player.currentHypnogramIndex = 0
        player.notifySessionMutated()
        applyClipSelectionChanged(manual: true)
    }

    private func flashClipHistoryIndicator() {
        guard !player.session.hypnograms.isEmpty else { return }
        clipHistoryIndicatorText = "\(player.currentHypnogramIndex + 1)/\(player.session.hypnograms.count)"

        clipHistoryIndicatorClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.clipHistoryIndicatorText = nil
        }
        clipHistoryIndicatorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }
}
