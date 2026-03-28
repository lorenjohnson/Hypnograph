//
//  HypnogramStore.swift
//  Hypnograph
//
//  Tracks favorited and saved hypnograms with metadata.
//  Provides a list for the favorites panel UI.
//

import Foundation
import Combine
import CoreImage
import AppKit
import UniformTypeIdentifiers
import HypnoCore

/// Metadata for a saved hypnogram
struct HypnogramEntry: Identifiable, Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    var favoritedAt: Date?
    let sessionURL: URL
    var thumbnailBase64: String?
    var isFavorite: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, favoritedAt, sessionURL, thumbnailBase64, isFavorite

        // Backward-compatible decode key from older store schema.
        case recipeURL
    }

    init(
        name: String,
        sessionURL: URL,
        thumbnailBase64: String? = nil,
        isFavorite: Bool = false,
        favoritedAt: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.favoritedAt = favoritedAt ?? (isFavorite ? Date() : nil)
        self.sessionURL = sessionURL
        self.thumbnailBase64 = thumbnailBase64
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        favoritedAt = try container.decodeIfPresent(Date.self, forKey: .favoritedAt)
        thumbnailBase64 = try container.decodeIfPresent(String.self, forKey: .thumbnailBase64)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false

        if let url = try container.decodeIfPresent(URL.self, forKey: .sessionURL) {
            sessionURL = url
        } else {
            // Older store entries used `recipeURL`.
            sessionURL = try container.decode(URL.self, forKey: .recipeURL)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(favoritedAt, forKey: .favoritedAt)
        try container.encode(sessionURL, forKey: .sessionURL)
        try container.encodeIfPresent(thumbnailBase64, forKey: .thumbnailBase64)
        try container.encode(isFavorite, forKey: .isFavorite)
    }

    /// Decode thumbnail from base64 to NSImage
    var thumbnailImage: NSImage? {
        guard let base64 = thumbnailBase64,
              let data = Data(base64Encoded: base64),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }
}

/// Observable store for hypnogram entries (favorites and history)
@MainActor
final class HypnogramStore: ObservableObject {
    static let shared = HypnogramStore()

    @Published private(set) var entries: [HypnogramEntry] = []

    /// Filtered list of favorites only
    var favorites: [HypnogramEntry] {
        entries
            .filter { $0.isFavorite }
            .sorted { ($0.favoritedAt ?? $0.createdAt) > ($1.favoritedAt ?? $1.createdAt) }
    }

    /// Recent entries (sorted by date, newest first)
    var recent: [HypnogramEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    private let storeURL: URL

    private init() {
        storeURL = Environment.appSupportDirectory.appendingPathComponent("hypnogram-store.json")
        load()
    }

    // MARK: - Add/Remove

    /// Add a new hypnogram entry
    /// - Parameters:
    ///   - hypnogram: The hypnogram to save
    ///   - snapshot: CGImage snapshot of the current frame (required for .hypno/.hypnogram format)
    ///   - name: Display name for the entry
    ///   - isFavorite: Whether to mark as favorite
    /// - Returns: The created entry, or nil if save failed
    @discardableResult
    func add(hypnogram: Hypnogram, snapshot: CGImage, name: String? = nil, isFavorite: Bool = false) -> HypnogramEntry? {
        // Save hypnogram + snapshot as .hypno file (JPEG with embedded snapshot)
        guard let sessionURL = HypnogramFileStore.save(hypnogram, snapshot: snapshot) else {
            return nil
        }

        // The .hypno/.hypnogram file IS the thumbnail now - encode a smaller version for quick loading in list
        let thumbnailBase64 = Self.encodeThumbnail(CIImage(cgImage: snapshot))

        let displayName = name ?? "Hypnogram \(DateFormatter.shortDateTime.string(from: Date()))"
        let entry = HypnogramEntry(
            name: displayName,
            sessionURL: sessionURL,
            thumbnailBase64: thumbnailBase64,
            isFavorite: isFavorite
        )

        entries.append(entry)
        save()

        return entry
    }

    /// Add an existing recipe file as an entry
    func addFromFile(url: URL, name: String? = nil, isFavorite: Bool = false) -> HypnogramEntry? {
        let displayName = name ?? url.deletingPathExtension().lastPathComponent
        let entry = HypnogramEntry(
            name: displayName,
            sessionURL: url,
            thumbnailBase64: nil,
            isFavorite: isFavorite
        )

        entries.append(entry)
        save()

        return entry
    }

    /// Remove an entry
    func remove(_ entry: HypnogramEntry) {
        entries.removeAll { $0.id == entry.id }
        // Optionally delete the recipe file
        // HypnogramFileStore.delete(at: entry.sessionURL)
        save()
    }

    /// Toggle favorite status
    func toggleFavorite(_ entry: HypnogramEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isFavorite.toggle()
        entries[index].favoritedAt = entries[index].isFavorite ? Date() : nil
        save()
    }

    /// Load a hypnogram from an entry
    func loadHypnogram(from entry: HypnogramEntry) -> Hypnogram? {
        HypnogramFileStore.load(from: entry.sessionURL)
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        do {
            let data = try Data(contentsOf: storeURL)
            entries = try JSONDecoder().decode([HypnogramEntry].self, from: data)
            print("✅ HypnogramStore: Loaded \(entries.count) entries")
        } catch {
            print("⚠️ HypnogramStore: Failed to load: \(error)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(entries)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("⚠️ HypnogramStore: Failed to save: \(error)")
        }
    }

    // MARK: - Thumbnail Encoding

    /// Thumbnail size (square, small for base64 efficiency)
    private static let thumbnailSize: CGFloat = 120

    /// Encode a CIImage to base64 JPEG string (resized to thumbnail size)
    static func encodeThumbnail(_ image: CIImage) -> String? {
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

        // Scale down to thumbnail size
        let extent = image.extent
        let scale = thumbnailSize / max(extent.width, extent.height)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaledImage.extent

        // Create CGImage
        guard let cgImage = context.createCGImage(scaledImage, from: scaledExtent) else {
            print("⚠️ HypnogramStore: Failed to create CGImage for thumbnail")
            return nil
        }

        // Convert to JPEG data
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: scaledExtent.width, height: scaledExtent.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            print("⚠️ HypnogramStore: Failed to encode thumbnail as JPEG")
            return nil
        }

        return jpegData.base64EncodedString()
    }
}

// MARK: - Date Formatter Helper

private extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
