//
//  HypnogramStore.swift
//  Hypnograph
//
//  Tracks favorited and saved hypnograms with metadata.
//  Provides a list for the favorites panel UI.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers
import HypnoCore

/// Metadata for a saved hypnogram
struct HypnogramEntry: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var favoritedAt: Date?
    let sessionURL: URL
    var isFavorite: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, favoritedAt, sessionURL, isFavorite

        // Backward-compatible decode key from older store schema.
        case recipeURL
        case thumbnailBase64
    }

    init(
        name: String,
        sessionURL: URL,
        isFavorite: Bool = false,
        favoritedAt: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.favoritedAt = favoritedAt ?? (isFavorite ? Date() : nil)
        self.sessionURL = sessionURL
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        favoritedAt = try container.decodeIfPresent(Date.self, forKey: .favoritedAt)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        _ = try container.decodeIfPresent(String.self, forKey: .thumbnailBase64)

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
        try container.encode(isFavorite, forKey: .isFavorite)
    }

    var thumbnailImage: NSImage? {
        HypnogramEntryThumbnailCache.image(for: sessionURL)
    }
}

private enum HypnogramEntryThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for url: URL) -> NSImage? {
        let key = url.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = HypnogramFileStore.loadThumbnail(from: url) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    static func invalidate(_ url: URL) {
        cache.removeObject(forKey: url.standardizedFileURL.path as NSString)
    }
}

/// Observable store for saved hypnogram entries (recent and favorites)
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
        HypnogramEntryThumbnailCache.invalidate(sessionURL)

        let displayName = name ?? "Hypnogram \(DateFormatter.shortDateTime.string(from: Date()))"
        let entry = HypnogramEntry(
            name: displayName,
            sessionURL: sessionURL,
            isFavorite: isFavorite
        )

        var updatedEntries = entries
        updatedEntries.append(entry)
        entries = updatedEntries
        save()

        return entry
    }

    /// Add an existing recipe file as an entry
    func addFromFile(url: URL, name: String? = nil, isFavorite: Bool = false) -> HypnogramEntry? {
        let displayName = name ?? url.deletingPathExtension().lastPathComponent
        let entry = HypnogramEntry(
            name: displayName,
            sessionURL: url,
            isFavorite: isFavorite
        )

        var updatedEntries = entries
        updatedEntries.append(entry)
        entries = updatedEntries
        save()

        return entry
    }

    @discardableResult
    func upsertSavedSession(
        at sessionURL: URL,
        snapshot: CGImage,
        name: String? = nil,
        isFavorite: Bool = false
    ) -> HypnogramEntry {
        HypnogramEntryThumbnailCache.invalidate(sessionURL)

        if let index = entries.firstIndex(where: { $0.sessionURL.standardizedFileURL == sessionURL.standardizedFileURL }) {
            var updatedEntries = entries
            updatedEntries[index].name = name ?? updatedEntries[index].name
            updatedEntries[index].createdAt = Date()
            updatedEntries[index].isFavorite = updatedEntries[index].isFavorite || isFavorite
            if updatedEntries[index].isFavorite {
                updatedEntries[index].favoritedAt = updatedEntries[index].favoritedAt ?? Date()
            }
            entries = updatedEntries
            save()
            return entries[index]
        }

        let displayName = name ?? sessionURL.deletingPathExtension().lastPathComponent
        let entry = HypnogramEntry(
            name: displayName,
            sessionURL: sessionURL,
            isFavorite: isFavorite
        )
        var updatedEntries = entries
        updatedEntries.append(entry)
        entries = updatedEntries
        save()
        return entry
    }

    /// Remove an entry
    func remove(_ entry: HypnogramEntry) {
        entries = entries.filter { $0.id != entry.id }
        HypnogramEntryThumbnailCache.invalidate(entry.sessionURL)
        // Optionally delete the recipe file
        // HypnogramFileStore.delete(at: entry.sessionURL)
        save()
    }

    /// Toggle favorite status
    func toggleFavorite(_ entry: HypnogramEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updatedEntries = entries
        updatedEntries[index].isFavorite.toggle()
        updatedEntries[index].favoritedAt = updatedEntries[index].isFavorite ? Date() : nil
        entries = updatedEntries
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
