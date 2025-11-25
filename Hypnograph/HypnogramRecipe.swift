//
//  HypnogramRecipe.swift
//  Hypnograph
//
//  “Blueprint” for a render: pure data, no renderer knowledge.
//

import Foundation
import CoreMedia

// MARK: - Mode-specific per-source data

// Mode-specific per-source data: arbitrary string → string
typealias ModeSourceData = [String: String]

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
