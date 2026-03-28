//
//  ClipHistoryFile.swift
//  Hypnograph
//
//  Persistence for the materialized clip history + selection index.
//

import Foundation
import HypnoCore

struct ClipHistoryFile: Codable {
    var hypnograms: [Hypnogram]
    var currentHypnogramIndex: Int

    private enum CodingKeys: String, CodingKey {
        case hypnograms
        case currentHypnogramIndex
    }

    init(
        hypnograms: [Hypnogram],
        currentHypnogramIndex: Int
    ) {
        self.hypnograms = hypnograms
        self.currentHypnogramIndex = currentHypnogramIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hypnograms = try container.decode([Hypnogram].self, forKey: .hypnograms)
        currentHypnogramIndex = try container.decode(Int.self, forKey: .currentHypnogramIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hypnograms, forKey: .hypnograms)
        try container.encode(currentHypnogramIndex, forKey: .currentHypnogramIndex)
    }
}
