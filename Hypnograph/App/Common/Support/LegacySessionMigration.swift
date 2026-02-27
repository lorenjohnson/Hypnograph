//
//  LegacySessionMigration.swift
//  Hypnograph
//
//  Compatibility helpers for on-disk .hypno/.hypnogram JSON written by older schemas.
//

import Foundation
import HypnoCore

enum LegacySessionMigration {

    /// Detect older session schema variants and rewrite using the current schema after decode.
    static func migrateSessionFileIfNeeded(originalData: Data, url: URL, decodedSession: HypnographSession) {
        guard shouldMigrateSessionJSON(data: originalData) else { return }

        // We decoded via backward-compatible Codable fallbacks.
        // Re-save in the current schema (`hypnograms`, `layers`, `mediaClip`) to normalize on-disk data.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let migrated = try? encoder.encode(decodedSession) {
            try? migrated.write(to: url, options: .atomic)
        }
    }

    private static func shouldMigrateSessionJSON(data: Data) -> Bool {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        if json["hypnograms"] != nil { return false }

        // Older variants:
        // - `clips: [...]`
        // - `sources: [...]` (single hypnogram at top-level)
        return json["clips"] != nil || json["sources"] != nil
    }
}
