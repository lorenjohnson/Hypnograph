//
//  CompositionHistoryFile.swift
//  Hypnograph
//
//  Persistence for the materialized composition history + selection index.
//

import Foundation
import HypnoCore

struct CompositionHistoryFile: Codable {
    var compositions: [Composition]
    var currentCompositionIndex: Int

    private enum CodingKeys: String, CodingKey {
        case compositions = "hypnograms"
        case currentCompositionIndex = "currentHypnogramIndex"
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
        compositions = try container.decode([Composition].self, forKey: .compositions)
        currentCompositionIndex = try container.decode(Int.self, forKey: .currentCompositionIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(compositions, forKey: .compositions)
        try container.encode(currentCompositionIndex, forKey: .currentCompositionIndex)
    }
}
