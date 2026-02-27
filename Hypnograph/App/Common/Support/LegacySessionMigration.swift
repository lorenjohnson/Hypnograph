//
//  LegacySessionMigration.swift
//  Hypnograph
//
//  Temporary legacy support helpers for on-disk .hypno/.hypnogram JSON.
//
//  Remove this file (and its call site in SessionStore) once all legacy files
//  have been migrated and legacy decoding support can be dropped.
//

import Foundation
import HypnoCore

enum LegacySessionMigration {

    /// Detect legacy session schema and, if needed, rewrite the file using the new schema.
    ///
    /// This is intentionally separate from SessionStore so it can be removed as a single unit later.
    static func migrateSessionFileIfNeeded(originalData: Data, url: URL, decodedSession: HypnographSession) {
        guard shouldMigrateSessionJSON(data: originalData) else { return }

        // Temporary migration (Phase 4/5) — remove later:
        // We successfully decoded legacy keys via Codable fallbacks in HypnographSession/Hypnogram/HypnogramLayer.
        // Now re-save the file in the new schema (`hypnograms`, `layers`, `mediaClip`) for faster future loads.
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

        // Legacy variants:
        // - Phase 1–3: `clips: [...]`
        // - Pre-multi-clip: `sources: [...]` (single hypnogram at top-level)
        return json["clips"] != nil || json["sources"] != nil
    }
}

