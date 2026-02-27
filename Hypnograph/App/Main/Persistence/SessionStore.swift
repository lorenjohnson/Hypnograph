//
//  SessionStore.swift
//  Hypnograph
//
//  Handles saving and loading HypnographSession files (.hypno / .hypnogram)
//  These files are JSON with an embedded base64 JPEG snapshot.
//

import Foundation
import AppKit
import HypnoCore

/// Handles saving and loading HypnographSession files (.hypno/.hypnogram = JSON with embedded snapshot)
enum SessionStore {

    /// Preferred file extension for new session files
    static let fileExtension = "hypno"

    /// All supported file extensions
    static let fileExtensions = ["hypno", "hypnogram"]

    /// Snapshot resolution (1080p)
    static let snapshotWidth: CGFloat = 1920
    static let snapshotHeight: CGFloat = 1080

    /// JPEG compression quality for snapshots
    static let snapshotJPEGQuality: CGFloat = 0.85

    /// Directory for saved hypnograms (kept as "recipes" on disk for backwards compatibility)
    static var sessionsDirectory: URL {
        let url = Environment.appSupportDirectory.appendingPathComponent("recipes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Save

    /// Save a hypnograph session with snapshot to default directory
    /// - Parameters:
    ///   - session: The session to save
    ///   - snapshotImage: The CGImage snapshot (will be resized to 1080p and encoded as JPEG)
    /// - Returns: URL of the saved .hypno file, or nil if save failed
    @discardableResult
    static func save(_ session: HypnographSession, snapshot: CGImage) -> URL? {
        let filename = defaultFilename()
        let url = sessionsDirectory.appendingPathComponent(filename)

        return save(session, snapshot: snapshot, to: url)
    }

    /// Save a hypnograph session with snapshot to a specific URL
    /// - Parameters:
    ///   - session: The session to save
    ///   - snapshotImage: The CGImage snapshot (will be resized to 1080p and encoded as JPEG)
    ///   - url: The URL to save to
    /// - Returns: URL of the saved file, or nil if save failed
    @discardableResult
    static func save(_ session: HypnographSession, snapshot: CGImage, to url: URL) -> URL? {
        // Encode the snapshot as base64 JPEG
        guard let snapshotBase64 = encodeSnapshot(snapshot) else {
            print("❌ SessionStore: Failed to encode snapshot")
            return nil
        }

        // Create session with embedded snapshot
        var sessionWithSnapshot = session
        sessionWithSnapshot.snapshot = snapshotBase64

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(sessionWithSnapshot)
            try data.write(to: url, options: .atomic)
            print("✅ SessionStore: Saved hypnogram to \(url.lastPathComponent) (\(data.count / 1024) KB)")
            return url
        } catch {
            print("❌ SessionStore: Failed to save session: \(error)")
            return nil
        }
    }

    /// Default filename for a new session file.
    static func defaultFilename(prefix: String = "hypno") -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "\(prefix)-\(timestamp).\(fileExtension)"
    }

    static func isSupportedExtension(_ ext: String) -> Bool {
        fileExtensions.contains(ext.lowercased())
    }

    // MARK: - Load

    /// Load a session from a .hypno or .hypnogram file
    /// - Parameter url: The URL to load from
    /// - Returns: The loaded session, or nil if load failed
    static func load(from url: URL) -> HypnographSession? {
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

            let session = try JSONDecoder().decode(HypnographSession.self, from: data)

            // Rewrites legacy-compatible files in current schema after successful decode.
            LegacySessionMigration.migrateSessionFileIfNeeded(
                originalData: data,
                url: url,
                decodedSession: session
            )

            print("✅ SessionStore: Loaded session from \(url.lastPathComponent)")
            return session
        } catch {
            print("❌ SessionStore: Failed to load session: \(error)")
            return nil
        }
    }

    /// Load the snapshot image from a .hypno or .hypnogram file
    /// - Parameter url: The URL to load from
    /// - Returns: The snapshot as NSImage, or nil if not available
    static func loadThumbnail(from url: URL) -> NSImage? {
        guard let session = load(from: url),
              let base64 = session.snapshot,
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
            at: sessionsDirectory,
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
        print("🗑️ SessionStore: Deleted \(url.lastPathComponent)")
    }

    // MARK: - Snapshot Encoding

    /// Encode a CGImage as base64 JPEG, resized to 1080p
    /// - Parameter image: The source CGImage
    /// - Returns: Base64-encoded JPEG string, or nil if encoding failed
    private static func encodeSnapshot(_ image: CGImage) -> String? {
        // Calculate target size maintaining aspect ratio, fitting within 1080p
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)

        let widthRatio = snapshotWidth / sourceWidth
        let heightRatio = snapshotHeight / sourceHeight
        let scale = min(widthRatio, heightRatio, 1.0) // Don't upscale

        let targetWidth = Int(sourceWidth * scale)
        let targetHeight = Int(sourceHeight * scale)

        // Create scaled image using Core Graphics
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: targetWidth,
                  height: targetHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            print("⚠️ SessionStore: Failed to create graphics context for snapshot")
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let scaledImage = context.makeImage() else {
            print("⚠️ SessionStore: Failed to create scaled image")
            return nil
        }

        // Convert to JPEG data
        let nsImage = NSImage(cgImage: scaledImage, size: NSSize(width: targetWidth, height: targetHeight))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: snapshotJPEGQuality]
              ) else {
            print("⚠️ SessionStore: Failed to encode snapshot as JPEG")
            return nil
        }

        print("📷 SessionStore: Encoded \(targetWidth)×\(targetHeight) snapshot (\(jpegData.count / 1024) KB)")
        return jpegData.base64EncodedString()
    }

    // Compatibility rewrite logic lives in `Hypnograph/LegacySessionMigration.swift`.
}
