//
//  HypnogramStore.swift
//  Hypnograph
//
//  Tracks favorited and saved hypnograms with metadata.
//  Provides a list for the favorites panel UI.
//

import Foundation
import Combine

/// Metadata for a saved hypnogram
struct HypnogramEntry: Identifiable, Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let recipeURL: URL
    var thumbnailURL: URL?
    var isFavorite: Bool

    init(name: String, recipeURL: URL, thumbnailURL: URL? = nil, isFavorite: Bool = false) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.recipeURL = recipeURL
        self.thumbnailURL = thumbnailURL
        self.isFavorite = isFavorite
    }
}

/// Observable store for hypnogram entries (favorites and history)
@MainActor
final class HypnogramStore: ObservableObject {
    static let shared = HypnogramStore()

    @Published private(set) var entries: [HypnogramEntry] = []

    /// Filtered list of favorites only
    var favorites: [HypnogramEntry] {
        entries.filter { $0.isFavorite }
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
    ///   - recipe: The recipe to save
    ///   - name: Display name for the entry
    ///   - isFavorite: Whether to mark as favorite
    ///   - thumbnailURL: Optional thumbnail image URL
    /// - Returns: The created entry, or nil if save failed
    @discardableResult
    func add(recipe: HypnogramRecipe, name: String? = nil, isFavorite: Bool = false, thumbnailURL: URL? = nil) -> HypnogramEntry? {
        // Save recipe to file
        guard let recipeURL = RecipeStore.save(recipe) else {
            return nil
        }

        let displayName = name ?? "Hypnogram \(DateFormatter.shortDateTime.string(from: Date()))"
        let entry = HypnogramEntry(
            name: displayName,
            recipeURL: recipeURL,
            thumbnailURL: thumbnailURL,
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
            recipeURL: url,
            thumbnailURL: nil,
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
        // RecipeStore.delete(at: entry.recipeURL)
        save()
    }

    /// Toggle favorite status
    func toggleFavorite(_ entry: HypnogramEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isFavorite.toggle()
        save()
    }

    /// Load recipe from an entry
    func loadRecipe(from entry: HypnogramEntry) -> HypnogramRecipe? {
        RecipeStore.load(from: entry.recipeURL)
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

