//
//  HistoryPersistenceService.swift
//  Hypnograph
//

import Foundation
import HypnoCore

struct HistoryPersistenceService {
    func load(url: URL, historyLimit: Int) -> HistoryLoadResult? {
        HistoryMigration.load(url: url, historyLimit: historyLimit)
    }

    func save(
        _ history: Hypnogram,
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
