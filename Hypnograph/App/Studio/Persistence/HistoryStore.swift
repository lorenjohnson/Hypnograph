//
//  HistoryStore.swift
//  Hypnograph
//
//  Persistence store for history using the shared Hypnogram document schema.
//

import Foundation
import HypnoCore

enum HistoryStore {
    static func loadCanonical(url: URL, historyLimit: Int) -> HistoryLoadResult? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Hypnogram.self, from: data)
        else {
            return nil
        }

        return HistoryLoadResult(
            hypnogram: sanitize(decoded, historyLimit: historyLimit),
            legacySelectedCompositionIndex: nil
        )
    }

    static func save(_ history: Hypnogram, url: URL, historyLimit: Int) throws {
        let sanitized = sanitize(history, historyLimit: historyLimit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sanitized)
        try data.write(to: url, options: .atomic)
    }

    static func sanitize(_ history: Hypnogram, historyLimit: Int) -> Hypnogram {
        var compositions = history.compositions
        var currentCompositionIndex = history.currentCompositionIndex

        let limit = max(1, historyLimit)
        if compositions.count > limit {
            let removedCount = compositions.count - limit
            compositions.removeFirst(removedCount)
            if let index = currentCompositionIndex {
                currentCompositionIndex = max(0, index - removedCount)
            }
        }

        if let index = currentCompositionIndex {
            if compositions.isEmpty {
                currentCompositionIndex = nil
            } else {
                currentCompositionIndex = max(0, min(index, compositions.count - 1))
            }
        }

        return Hypnogram(
            compositions: compositions,
            currentCompositionIndex: currentCompositionIndex,
            snapshot: nil,
            createdAt: history.createdAt
        )
    }

    static func backupCorruptFile(at url: URL) {
        let fm = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupName = "history.corrupt-\(timestamp).json"
        let backupURL = url.deletingLastPathComponent().appendingPathComponent(backupName)

        do {
            if fm.fileExists(atPath: backupURL.path) {
                try fm.removeItem(at: backupURL)
            }
            try fm.moveItem(at: url, to: backupURL)
            print("⚠️ HistoryStore: Backed up corrupt history to \(backupURL.lastPathComponent)")
        } catch {
            print("⚠️ HistoryStore: Failed to backup corrupt history: \(error)")
        }
    }
}
