//
//  HypnogramFileStore.swift
//  Hypnograph
//
//  Handles saving and loading Hypnogram files (.hypno / .hypnogram)
//  These files are JSON with an embedded base64 JPEG snapshot.
//

import Foundation
import AppKit
import HypnoCore

/// Handles saving and loading Hypnogram files (.hypno/.hypnogram = JSON with embedded snapshot)
enum HypnogramFileStore {

    /// Preferred file extension for new hypnogram files
    static let fileExtension = "hypno"

    /// All supported file extensions
    static let fileExtensions = ["hypno", "hypnogram"]

    /// Directory for saved hypnograms (kept as "recipes" on disk for backwards compatibility)
    static var hypnogramsDirectory: URL {
        let url = Environment.appSupportDirectory.appendingPathComponent("recipes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Save

    /// Save a hypnogram with snapshot to default directory
    /// - Parameters:
    ///   - hypnogram: The hypnogram to save
    ///   - snapshotImage: The CGImage snapshot (will be resized to 1080p and encoded as JPEG)
    /// - Returns: URL of the saved .hypno file, or nil if save failed
    @discardableResult
    static func save(_ hypnogram: Hypnogram, snapshot: CGImage) -> URL? {
        let filename = defaultFilename()
        let url = hypnogramsDirectory.appendingPathComponent(filename)

        return save(hypnogram, snapshot: snapshot, to: url)
    }

    /// Save a hypnogram with snapshot to a specific URL
    /// - Parameters:
    ///   - hypnogram: The hypnogram to save
    ///   - snapshotImage: The CGImage snapshot (will be resized to 1080p and encoded as JPEG)
    ///   - url: The URL to save to
    /// - Returns: URL of the saved file, or nil if save failed
    @discardableResult
    static func save(_ hypnogram: Hypnogram, snapshot: CGImage, to url: URL) -> URL? {
        guard let previewImages = CompositionPreviewImageCodec.makePreviewImages(from: snapshot) else {
            print("❌ HypnogramFileStore: Failed to encode hypnogram poster image")
            return nil
        }

        var hypnogramWithPreview = hypnogram

        // Preserve an explicit document-level poster image for save/favorite flows.
        // Composition previews are persisted separately from deterministic thumbnail generation.
        hypnogramWithPreview.snapshot = previewImages.snapshotBase64

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(hypnogramWithPreview)
            try data.write(to: url, options: .atomic)
            print("✅ HypnogramFileStore: Saved hypnogram to \(url.lastPathComponent) (\(data.count / 1024) KB)")
            return url
        } catch {
            print("❌ HypnogramFileStore: Failed to save hypnogram: \(error)")
            return nil
        }
    }

    /// Default filename for a new hypnogram file.
    static func defaultFilename(prefix: String = "hypno") -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "\(prefix)-\(timestamp).\(fileExtension)"
    }

    static func isSupportedExtension(_ ext: String) -> Bool {
        fileExtensions.contains(ext.lowercased())
    }

    // MARK: - Load

    /// Load a hypnogram from a .hypno or .hypnogram file
    /// - Parameter url: The URL to load from
    /// - Returns: The loaded hypnogram, or nil if load failed
    static func load(from url: URL) -> Hypnogram? {
        do {
            var data = try Data(contentsOf: url)

            // Strip comments (lines starting with //) for JSONC support
            if let string = String(data: data, encoding: .utf8) {
                let lines = string.components(separatedBy: .newlines)
                let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                if let filteredData = filtered.joined(separator: "\n").data(using: .utf8) {
                    data = filteredData
                }
            }

            let hypnogram = try JSONDecoder().decode(Hypnogram.self, from: data)

            // Rewrites legacy-compatible files in current schema after successful decode.
            LegacyHypnogramMigration.migrateSessionFileIfNeeded(
                originalData: data,
                url: url,
                decodedSession: hypnogram
            )

            print("✅ HypnogramFileStore: Loaded hypnogram from \(url.lastPathComponent)")
            return hypnogram
        } catch {
            print("❌ HypnogramFileStore: Failed to load hypnogram: \(error)")
            return nil
        }
    }

    /// Load the snapshot image from a .hypno or .hypnogram file
    /// - Parameter url: The URL to load from
    /// - Returns: The snapshot as NSImage, or nil if not available
    static func loadThumbnail(from url: URL) -> NSImage? {
        guard let hypnogram = load(from: url),
              let base64 = hypnogram.thumbnail,
              let data = Data(base64Encoded: base64),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }

    // MARK: - List

    /// List all saved hypnogram files
    /// - Returns: Array of hypnogram file URLs, sorted by date (newest first)
    static func listSavedRecipes() -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: hypnogramsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { isSupportedExtension($0.pathExtension) }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return date1 > date2
            }
    }

    /// Delete a saved hypnogram
    /// - Parameter url: URL of the hypnogram to delete
    static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        print("🗑️ HypnogramFileStore: Deleted \(url.lastPathComponent)")
    }
    // Compatibility rewrite logic lives in `Hypnograph/LegacyHypnogramMigration.swift`.
}
