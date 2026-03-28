//
//  CompositionHistoryStore.swift
//  Hypnograph
//
//  Persistence store for composition history materialized hypnograms + selection index.
//

import Foundation

enum CompositionHistoryStore {
    static func load(url: URL, historyLimit: Int) -> CompositionHistoryFile? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(CompositionHistoryFile.self, from: data)
            return sanitize(decoded, historyLimit: historyLimit)
        } catch {
            backupCorruptFile(at: url)
            return nil
        }
    }

    static func save(_ history: CompositionHistoryFile, url: URL, historyLimit: Int) throws {
        let sanitized = sanitize(history, historyLimit: historyLimit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sanitized)
        try data.write(to: url, options: .atomic)
    }

    private static func sanitize(_ history: CompositionHistoryFile, historyLimit: Int) -> CompositionHistoryFile {
        var compositions = history.compositions
        var index = history.currentCompositionIndex

        let limit = max(1, historyLimit)
        if compositions.count > limit {
            let overflow = compositions.count - limit
            compositions.removeFirst(overflow)
            index = max(0, index - overflow)
        }

        guard !compositions.isEmpty else {
            return CompositionHistoryFile(
                compositions: [],
                currentCompositionIndex: 0
            )
        }

        index = max(0, min(index, compositions.count - 1))

        return CompositionHistoryFile(
            compositions: compositions,
            currentCompositionIndex: index
        )
    }

    private static func backupCorruptFile(at url: URL) {
        let fm = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupName = "clip-history.corrupt-\(timestamp).json"
        let backupURL = url.deletingLastPathComponent().appendingPathComponent(backupName)

        do {
            if fm.fileExists(atPath: backupURL.path) {
                try fm.removeItem(at: backupURL)
            }
            try fm.moveItem(at: url, to: backupURL)
            print("⚠️ CompositionHistoryStore: Backed up corrupt history to \(backupURL.lastPathComponent)")
        } catch {
            print("⚠️ CompositionHistoryStore: Failed to backup corrupt history: \(error)")
        }
    }
}
