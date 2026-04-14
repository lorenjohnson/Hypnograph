//
//  DefaultHypnogramStore.swift
//  Hypnograph
//
//  Persistence store for the unnamed default hypnogram using the shared Hypnogram schema.
//

import Foundation
import HypnoCore

enum DefaultHypnogramStore {
    static func load(url: URL, historyLimit: Int) -> Hypnogram? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Hypnogram.self, from: data)
        else {
            return nil
        }

        return sanitize(decoded, historyLimit: historyLimit)
    }

    static func save(_ defaultHypnogram: Hypnogram, url: URL, historyLimit: Int) throws {
        let sanitized = sanitize(defaultHypnogram, historyLimit: historyLimit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sanitized)
        try data.write(to: url, options: .atomic)
    }

    static func sanitize(_ defaultHypnogram: Hypnogram, historyLimit: Int) -> Hypnogram {
        var compositions = defaultHypnogram.compositions
        var currentCompositionIndex = defaultHypnogram.currentCompositionIndex

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
            effectChain: defaultHypnogram.effectChain,
            aspectRatio: defaultHypnogram.aspectRatio,
            outputResolution: defaultHypnogram.outputResolution,
            sourceFraming: defaultHypnogram.sourceFraming,
            transitionStyle: defaultHypnogram.transitionStyle,
            transitionDuration: defaultHypnogram.transitionDuration,
            snapshot: nil,
            createdAt: defaultHypnogram.createdAt
        )
    }
}
