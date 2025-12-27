//
//  EffectChainLibraryActions.swift
//  Hypnograph
//
//  Actions for saving and loading effect chain libraries.
//  Handles file dialogs and library import/export operations.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Actions for saving and loading effect chain libraries
enum EffectChainLibraryActions {
    
    // MARK: - Save to Default Library

    /// Save current effect chains to the default library location
    /// This saves immediately (no file picker - saves to ~/Library/Application Support/Hypnograph/effects.json)
    static func saveToDefaultLibrary() {
        EffectConfigLoader.save()
        AppNotifications.show("Effects saved to default library", flash: true)
    }

    // MARK: - Save to File

    /// Save current effect chains to a user-chosen file
    /// Opens a save file dialog for .json files
    static func saveLibraryToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "effects.json"
        panel.message = "Save effects library"

        // Start in the Application Support folder
        panel.directoryURL = EffectConfigLoader.userConfigURL.deletingLastPathComponent()

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            EffectConfigLoader.save(to: url)

            AppNotifications.show("Effects saved to \(url.lastPathComponent)", flash: true)
        }
    }

    // MARK: - Load from File

    /// Load effect chain library from a file (.json or .hypnogram)
    /// Opens a file picker that accepts both file types
    static func loadLibraryFromFile() {
        let panel = NSOpenPanel()

        // Allow both JSON and Hypnogram files
        var allowedTypes: [UTType] = [UTType.json]
        if let hypnogramType = UTType(filenameExtension: RecipeStore.fileExtension) {
            allowedTypes.append(hypnogramType)
        }
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.message = "Select an effects library (.json) or hypnogram file"

        // Start in the Application Support folder
        panel.directoryURL = EffectConfigLoader.userConfigURL.deletingLastPathComponent()

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let ext = url.pathExtension.lowercased()

            if ext == RecipeStore.fileExtension {
                // Load from hypnogram file
                loadFromHypnogram(url: url)
            } else {
                // Load from JSON file
                loadFromJSON(url: url)
            }
        }
    }

    /// Load effect chains from a JSON library file
    private static func loadFromJSON(url: URL) {
        do {
            let chains = try EffectConfigLoader.loadFromURL(url)
            replaceLibrary(with: chains)
            AppNotifications.show("Loaded \(chains.count) effect chains", flash: true)
        } catch {
            print("⚠️ EffectChainLibraryActions: Failed to load library from \(url.path): \(error)")
            AppNotifications.show("Failed to load effects library", flash: true)
        }
    }

    /// Load effect chains from a hypnogram recipe file
    private static func loadFromHypnogram(url: URL) {
        guard let recipe = RecipeStore.load(from: url) else {
            AppNotifications.show("Failed to load hypnogram", flash: true)
            return
        }

        let chains = extractEffectChains(from: recipe)

        if chains.isEmpty {
            AppNotifications.show("No effect chains found in hypnogram", flash: true)
            return
        }

        // Merge extracted chains into current library
        mergeChains(chains)

        AppNotifications.show("Imported \(chains.count) effect chains", flash: true)
    }
    
    // MARK: - Recipe Import

    /// Import effect chains from a recipe into the library (used when loading hypnograms)
    /// Merges chains into the library, avoiding duplicates by name
    static func importChainsFromRecipe(_ recipe: HypnogramRecipe) {
        let chains = extractEffectChains(from: recipe)
        guard !chains.isEmpty else { return }
        mergeChains(chains)
    }

    // MARK: - Private Helpers

    /// Replace the current library with new chains
    private static func replaceLibrary(with chains: [EffectChain]) {
        // Use EffectChainLibrary to update the cache
        EffectChainLibrary.updateCache(with: chains)
    }

    /// Extract effect chains from a recipe (global + per-source)
    private static func extractEffectChains(from recipe: HypnogramRecipe) -> [EffectChain] {
        var chains: [EffectChain] = []

        // Add global effect chain if it has effects
        if !recipe.effectChain.effects.isEmpty {
            let globalChain = recipe.effectChain.copy()
            // Ensure it has a name
            if globalChain.name == nil || globalChain.name?.isEmpty == true {
                globalChain.name = "Global (imported)"
            }
            chains.append(globalChain)
        }

        // Add per-source effect chains that have effects
        for (index, source) in recipe.sources.enumerated() {
            if !source.effectChain.effects.isEmpty {
                let sourceChain = source.effectChain.copy()
                // Ensure it has a name
                if sourceChain.name == nil || sourceChain.name?.isEmpty == true {
                    sourceChain.name = "Source \(index + 1) (imported)"
                }
                chains.append(sourceChain)
            }
        }

        return chains
    }
    
    /// Merge new chains into the current library (overwrites on name collision)
    private static func mergeChains(_ newChains: [EffectChain]) {
        var currentChains = EffectConfigLoader.currentChains

        for chain in newChains {
            // If chain with same name exists, replace it
            if let name = chain.name,
               let existingIndex = currentChains.firstIndex(where: { $0.name == name }) {
                currentChains[existingIndex] = chain
            } else {
                currentChains.append(chain)
            }
        }

        EffectChainLibrary.updateCache(with: currentChains)
    }
}

