//
//  HistoryMigration.swift
//  Hypnograph
//
//  One-way migration support for legacy history schema and path changes.
//

import Foundation
import HypnoCore

struct HistoryLoadResult {
    let hypnogram: Hypnogram
    let legacySelectedCompositionIndex: Int?
}

enum HistoryMigration {
    static func load(url: URL, historyLimit: Int) -> HistoryLoadResult? {
        if let current = loadCanonicalOrLegacy(at: url, migrateTo: url, historyLimit: historyLimit) {
            return current
        }

        guard url == Environment.historyURL else { return nil }

        let legacyURL = Environment.legacyClipHistoryURL
        guard legacyURL != url else { return nil }

        return loadCanonicalOrLegacy(at: legacyURL, migrateTo: url, historyLimit: historyLimit)
    }

    private static func loadCanonicalOrLegacy(
        at sourceURL: URL,
        migrateTo destinationURL: URL,
        historyLimit: Int
    ) -> HistoryLoadResult? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return nil }

        if let canonical = HistoryStore.loadCanonical(url: sourceURL, historyLimit: historyLimit) {
            if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
                persistCanonical(canonical.hypnogram, to: destinationURL, historyLimit: historyLimit)
            }
            return canonical
        }

        if let migrated = loadLegacyHistory(at: sourceURL, historyLimit: historyLimit) {
            persistCanonical(migrated.hypnogram, to: destinationURL, historyLimit: historyLimit)
            return migrated
        }

        HistoryStore.backupCorruptFile(at: sourceURL)
        return nil
    }

    private static func loadLegacyHistory(at url: URL, historyLimit: Int) -> HistoryLoadResult? {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(LegacyHistoryFile.self, from: data)
            let migratedHypnogram = Hypnogram(
                compositions: decoded.compositions,
                currentCompositionIndex: decoded.currentCompositionIndex,
                createdAt: decoded.compositions.first?.createdAt ?? Date()
            )
            return HistoryLoadResult(
                hypnogram: HistoryStore.sanitize(migratedHypnogram, historyLimit: historyLimit),
                legacySelectedCompositionIndex: decoded.currentCompositionIndex
            )
        } catch {
            return nil
        }
    }

    private static func persistCanonical(_ history: Hypnogram, to url: URL, historyLimit: Int) {
        do {
            try HistoryStore.save(history, url: url, historyLimit: historyLimit)
        } catch {
            print("⚠️ Studio: Failed to persist migrated history: \(error)")
        }
    }
}

private struct LegacyHistoryFile: Decodable {
    var compositions: [Composition]
    var currentCompositionIndex: Int

    private enum CodingKeys: String, CodingKey {
        case compositions
        case currentCompositionIndex
        case legacyHypnograms = "hypnograms"
        case legacyCurrentHypnogramIndex = "currentHypnogramIndex"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        compositions =
            try container.decodeIfPresent([Composition].self, forKey: .compositions)
            ?? container.decode([Composition].self, forKey: .legacyHypnograms)
        currentCompositionIndex =
            try container.decodeIfPresent(Int.self, forKey: .currentCompositionIndex)
            ?? container.decode(Int.self, forKey: .legacyCurrentHypnogramIndex)
    }
}
