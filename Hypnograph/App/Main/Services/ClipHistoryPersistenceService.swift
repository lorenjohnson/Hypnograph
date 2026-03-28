//
//  ClipHistoryPersistenceService.swift
//  Hypnograph
//

import Foundation

struct ClipHistoryPersistenceService {
    func load(url: URL, historyLimit: Int) -> ClipHistoryFile? {
        ClipHistoryStore.load(url: url, historyLimit: historyLimit)
    }

    func save(
        _ history: ClipHistoryFile,
        url: URL,
        historyLimit: Int,
        synchronous: Bool
    ) {
        if synchronous {
            do {
                try ClipHistoryStore.save(history, url: url, historyLimit: historyLimit)
            } catch {
                print("⚠️ Main: Failed to save clip history (sync): \(error)")
            }
            return
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                try ClipHistoryStore.save(history, url: url, historyLimit: historyLimit)
            } catch {
                print("⚠️ Main: Failed to save clip history: \(error)")
            }
        }
    }

    static let live = ClipHistoryPersistenceService()
}
