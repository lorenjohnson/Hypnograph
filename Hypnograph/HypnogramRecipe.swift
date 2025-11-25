//
//  HypnogramRecipe.swift
//  Hypnograph
//
//  “Blueprint” for a render: pure data, no renderer knowledge.
//

import Foundation
import CoreMedia

// MARK: - Mode-specific per-source data

/// Mode-specific per-source data: arbitrary string → string
typealias ModeSourceData = [String: String]

/// Typed keys for data stored in `ModeSourceData`.
enum ModeSourceKey: String, Codable {
    case blendMode
    // Later: case sourceEffect, case maskID, etc.
}

/// Mode-specific data attached to a HypnogramRecipe.
///
/// Shape:
/// - `name`       → which mode this recipe is for (montage / sequence / divine).
/// - `sourceData` → one extra object per source, same order as `sources`.
struct HypnogramMode: Codable {
    var name: ModeType
    var sourceData: [ModeSourceData]

    init(name: ModeType, sourceData: [ModeSourceData] = []) {
        self.name = name
        self.sourceData = sourceData
    }
}

extension HypnogramMode {
    /// Read a value for a given key/sourceIndex from the mode payload.
    func value(for key: ModeSourceKey, sourceIndex: Int) -> String? {
        guard sourceIndex >= 0 && sourceIndex < sourceData.count else { return nil }
        return sourceData[sourceIndex][key.rawValue]
    }
}

// MARK: - ModeSourceData convenience helpers

extension Array where Element == ModeSourceData {
    /// Ensure the array has at least `count` elements, padding with empty dictionaries.
    mutating func ensureCount(_ count: Int) {
        if self.count < count {
            self.append(contentsOf: repeatElement([:], count: count - self.count))
        } else if self.count > count {
            self.removeLast(self.count - count)
        }
    }

    /// Get a value for a given key at a given source index.
    func value(forKey key: String, at index: Int) -> String? {
        guard indices.contains(index) else { return nil }
        return self[index][key]
    }

    /// Set a value for a given key at a given source index, auto-expanding as needed.
    mutating func setValue(_ value: String, forKey key: String, at index: Int) {
        ensureCount(index + 1)
        self[index][key] = value
    }
}


// MARK: - Hypnogram recipe

/// A complete “hypnogram” recipe: ordered sources of clips plus the target render duration.
///
/// Additionally, a recipe can carry a *mode-specific* payload (`mode`), which
/// includes the mode name and per-source extra data (e.g. Montage blend modes).
struct HypnogramRecipe {
    var mode: HypnogramMode?
    var sources: [HypnogramSource]
    var targetDuration: CMTime

    init(
        sources: [HypnogramSource],
        targetDuration: CMTime,
        mode: HypnogramMode? = nil
    ) {
        self.sources = sources
        self.targetDuration = targetDuration
        self.mode = mode
    }
}

extension HypnogramRecipe {
    /// Ensure there is a `mode` attached with the given name.
    mutating func ensureMode(named modeName: ModeType) {
        if mode == nil || mode?.name != modeName {
            mode = HypnogramMode(name: modeName, sourceData: [])
        }
    }

    /// Read a mode-specific value for a given key/sourceIndex from this recipe’s mode payload.
    func modeValue(for key: ModeSourceKey, sourceIndex: Int) -> String? {
        guard let m = mode, sourceIndex >= 0, sourceIndex < m.sourceData.count else { return nil }
        return m.sourceData[sourceIndex][key.rawValue]
    }

    /// Set a mode-specific value for a given key/sourceIndex, creating/expanding mode payload as needed.
    mutating func setModeValue(
        _ value: String,
        key: ModeSourceKey,
        sourceIndex: Int,
        modeName: ModeType
    ) {
        ensureMode(named: modeName)
        guard var m = mode else { return }
        m.sourceData.ensureCount(sourceIndex + 1)
        m.sourceData[sourceIndex][key.rawValue] = value
        mode = m
    }

    /// Build a “display” recipe for preview, using a subset of sources and
    /// mapping mode.sourceData through `sourceIndices`.
    func subrecipeForDisplay(
        sources displaySources: [HypnogramSource],
        sourceIndices: [Int]
    ) -> HypnogramRecipe {
        var displayMode: HypnogramMode?

        if let m = mode {
            let subset = sourceIndices.map { idx -> ModeSourceData in
                if idx >= 0 && idx < m.sourceData.count {
                    return m.sourceData[idx]
                } else {
                    return [:]
                }
            }
            displayMode = HypnogramMode(name: m.name, sourceData: subset)
        }

        return HypnogramRecipe(
            sources: displaySources,
            targetDuration: targetDuration,
            mode: displayMode
        )
    }
}
