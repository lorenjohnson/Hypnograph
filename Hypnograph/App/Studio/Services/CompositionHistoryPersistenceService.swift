//
//  CompositionHistoryPersistenceService.swift
//  Hypnograph
//

import Foundation

struct CompositionHistoryPersistenceService {
    func load(url: URL, historyLimit: Int) -> CompositionHistoryFile? {
        CompositionHistoryStore.load(url: url, historyLimit: historyLimit)
    }

    func save(
        _ history: CompositionHistoryFile,
        url: URL,
        historyLimit: Int,
        synchronous: Bool
    ) {
        if synchronous {
            do {
                try CompositionHistoryStore.save(history, url: url, historyLimit: historyLimit)
            } catch {
                print("⚠️ Studio: Failed to save composition history (sync): \(error)")
            }
            return
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                try CompositionHistoryStore.save(history, url: url, historyLimit: historyLimit)
            } catch {
                print("⚠️ Studio: Failed to save composition history: \(error)")
            }
        }
    }

    static let live = CompositionHistoryPersistenceService()
}
