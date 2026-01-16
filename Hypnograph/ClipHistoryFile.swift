//
//  ClipHistoryFile.swift
//  Hypnograph
//
//  Persistence for the materialized clip history + selection index.
//

import Foundation
import HypnoCore

struct ClipHistoryFile: Codable {
    var clips: [HypnogramClip]
    var currentClipIndex: Int
}

enum ClipHistoryIO {
    static func load(url: URL, historyLimit: Int) -> ClipHistoryFile? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ClipHistoryFile.self, from: data)
            return sanitize(decoded, historyLimit: historyLimit)
        } catch {
            backupCorruptFile(at: url)
            return nil
        }
    }

    static func save(_ history: ClipHistoryFile, url: URL, historyLimit: Int) throws {
        let sanitized = sanitize(history, historyLimit: historyLimit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sanitized)
        try data.write(to: url, options: .atomic)
    }

    private static func sanitize(_ history: ClipHistoryFile, historyLimit: Int) -> ClipHistoryFile {
        var clips = history.clips
        var index = history.currentClipIndex

        let limit = max(1, historyLimit)
        if clips.count > limit {
            let overflow = clips.count - limit
            clips.removeFirst(overflow)
            index = max(0, index - overflow)
        }

        if clips.isEmpty {
            return ClipHistoryFile(clips: [], currentClipIndex: 0)
        }

        index = max(0, min(index, clips.count - 1))
        return ClipHistoryFile(clips: clips, currentClipIndex: index)
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
            print("⚠️ ClipHistoryIO: Backed up corrupt history to \(backupURL.lastPathComponent)")
        } catch {
            print("⚠️ ClipHistoryIO: Failed to backup corrupt history: \(error)")
        }
    }
}

