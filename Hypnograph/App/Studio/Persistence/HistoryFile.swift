//
//  HistoryFile.swift
//  Hypnograph
//
//  Persistence for the materialized composition history + selection index.
//

import Foundation
import HypnoCore

struct HistoryFile: Codable {
    var compositions: [Composition]
    var currentCompositionIndex: Int

    private enum CodingKeys: String, CodingKey {
        case compositions
        case currentCompositionIndex
        case legacyHypnograms = "hypnograms"
        case legacyCurrentHypnogramIndex = "currentHypnogramIndex"
    }

    init(
        compositions: [Composition],
        currentCompositionIndex: Int
    ) {
        self.compositions = compositions
        self.currentCompositionIndex = currentCompositionIndex
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(compositions, forKey: .compositions)
        try container.encode(currentCompositionIndex, forKey: .currentCompositionIndex)
    }
}
