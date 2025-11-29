//
//  HypnogramRecipe.swift
//  Hypnograph
//
//  "Blueprint" for a render: pure data, no renderer knowledge.
//

import Foundation
import CoreMedia

// MARK: - Hypnogram recipe

/// A complete "hypnogram" recipe: ordered sources plus the target render duration.
struct HypnogramRecipe {
    var sources: [HypnogramSource]
    var targetDuration: CMTime

    init(
        sources: [HypnogramSource],
        targetDuration: CMTime
    ) {
        self.sources = sources
        self.targetDuration = targetDuration
    }
}
