//
//  HistoryPersistenceService.swift
//  Hypnograph
//

import Foundation

struct HistoryPersistenceService {
    func load(url: URL, historyLimit: Int) -> HistoryFile? {
        if let current = HistoryStore.load(url: url, historyLimit: historyLimit) {
            return current
        }

        guard url == Environment.historyURL else { return nil }

        let legacyURL = Environment.legacyClipHistoryURL
        guard legacyURL != url else { return nil }
        guard let legacy = HistoryStore.load(url: legacyURL, historyLimit: historyLimit) else { return nil }

        do {
            try HistoryStore.save(legacy, url: url, historyLimit: historyLimit)
        } catch {
            print("⚠️ Studio: Failed to migrate legacy history to new path: \(error)")
        }

        return legacy
    }

    func save(
        _ history: HistoryFile,
        url: URL,
        historyLimit: Int,
        synchronous: Bool
    ) {
        if synchronous {
            do {
                try HistoryStore.save(history, url: url, historyLimit: historyLimit)
            } catch {
                print("⚠️ Studio: Failed to save composition history (sync): \(error)")
            }
            return
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                try HistoryStore.save(history, url: url, historyLimit: historyLimit)
            } catch {
                print("⚠️ Studio: Failed to save composition history: \(error)")
            }
        }
    }

    static let live = HistoryPersistenceService()
}
