//
//  RecipeStore.swift
//  Hypnograph
//
//  Handles saving and loading HypnogramRecipe files (.hypnogram)
//

import Foundation

/// Handles saving and loading HypnogramRecipe files
enum RecipeStore {

    /// File extension for hypnogram recipe files
    static let fileExtension = "hypnogram"

    /// Directory for saved recipes
    static var recipesDirectory: URL {
        let url = Environment.appSupportDirectory.appendingPathComponent("recipes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Save

    /// Save a recipe to a file with timestamp
    /// - Parameter recipe: The recipe to save
    /// - Returns: URL of the saved file, or nil if save failed
    @discardableResult
    static func save(_ recipe: HypnogramRecipe) -> URL? {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "hypnogram-\(timestamp).\(fileExtension)"
        let url = recipesDirectory.appendingPathComponent(filename)

        return save(recipe, to: url)
    }

    /// Save a recipe to a specific URL
    /// - Parameters:
    ///   - recipe: The recipe to save
    ///   - url: The URL to save to
    /// - Returns: URL of the saved file, or nil if save failed
    @discardableResult
    static func save(_ recipe: HypnogramRecipe, to url: URL) -> URL? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(recipe)
            try data.write(to: url, options: .atomic)
            print("✅ RecipeStore: Saved recipe to \(url.lastPathComponent)")
            return url
        } catch {
            print("❌ RecipeStore: Failed to save recipe: \(error)")
            return nil
        }
    }

    // MARK: - Load

    /// Load a recipe from a URL
    /// - Parameter url: The URL to load from
    /// - Returns: The loaded recipe, or nil if load failed
    static func load(from url: URL) -> HypnogramRecipe? {
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

            let recipe = try JSONDecoder().decode(HypnogramRecipe.self, from: data)
            print("✅ RecipeStore: Loaded recipe from \(url.lastPathComponent)")
            return recipe
        } catch {
            print("❌ RecipeStore: Failed to load recipe: \(error)")
            return nil
        }
    }

    // MARK: - List

    /// List all saved recipe files
    /// - Returns: Array of recipe file URLs, sorted by date (newest first)
    static func listSavedRecipes() -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: recipesDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == fileExtension }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return date1 > date2
            }
    }

    /// Delete a saved recipe
    /// - Parameter url: URL of the recipe to delete
    static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        print("🗑️ RecipeStore: Deleted \(url.lastPathComponent)")
    }
}

