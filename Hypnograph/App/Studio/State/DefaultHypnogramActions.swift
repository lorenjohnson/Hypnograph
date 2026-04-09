//
//  DefaultHypnogramActions.swift
//  Hypnograph
//

import Foundation
import Combine
import AppKit
import HypnoCore

@MainActor
extension Studio {
    func setupDefaultHypnogramPersistence() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveDefaultHypnogram(synchronous: true)
                self?.state.settingsStore.save(synchronous: true)
            }
        }

        $hypnogramRevision
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleDefaultHypnogramSave()
                self?.markWorkingHypnogramDirtyIfNeeded()
            }
            .store(in: &defaultHypnogramSaveCancellables)

        $currentCompositionIndex
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleDefaultHypnogramSave()
                self?.syncCurrentCompositionIndexIntoHypnogram()
            }
            .store(in: &defaultHypnogramSaveCancellables)
    }

    private func scheduleDefaultHypnogramSave() {
        defaultHypnogramSaveTimer?.invalidate()
        defaultHypnogramSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveDefaultHypnogram(synchronous: false)
            }
        }
    }

    func saveDefaultHypnogram(synchronous: Bool) {
        guard isUsingDefaultHypnogram else { return }
        var defaultHypnogram = hypnogram
        defaultHypnogram.currentCompositionIndex = clampedCurrentCompositionIndex
        defaultHypnogram.snapshot = nil
        let historyLimit = state.settings.historyLimit
        let save = {
            do {
                try DefaultHypnogramStore.save(
                    defaultHypnogram,
                    url: Environment.defaultHypnogramURL,
                    historyLimit: historyLimit
                )
            } catch {
                print("⚠️ Studio: Failed to save default hypnogram\(synchronous ? " (sync)" : ""): \(error)")
            }
        }

        if synchronous {
            save()
        } else {
            DispatchQueue.global(qos: .utility).async(execute: save)
        }
    }

    func restoreDefaultHypnogram() {
        if let restoredHypnogram = DefaultHypnogramStore.load(
            url: Environment.defaultHypnogramURL,
            historyLimit: state.settings.historyLimit
        ),
           !restoredHypnogram.compositions.isEmpty {
            let restoredIndex = restoredHypnogram.currentCompositionIndex ?? 0
            var restoredHypnogram = restoredHypnogram
            restoredHypnogram.currentCompositionIndex = max(0, min(restoredIndex, restoredHypnogram.compositions.count - 1))
            activateWorkingHypnogram(restoredHypnogram, sourceURL: nil)
            print("📼 Restored default hypnogram (\(restoredHypnogram.compositions.count) compositions)")
            return
        }

        replaceDefaultHypnogramWithNewComposition()
    }

    func enforceDefaultHypnogramCompositionLimit() {
        guard isUsingDefaultHypnogram else { return }
        let limit = max(1, state.settings.historyLimit)
        let overflow = max(0, hypnogram.compositions.count - limit)
        guard overflow > 0 else { return }

        hypnogram.compositions.removeFirst(overflow)
        currentCompositionIndex = max(0, currentCompositionIndex - overflow)
        notifyHypnogramMutated()
    }

    func resetDefaultHypnogram() {
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
}
