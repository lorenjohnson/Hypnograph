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
@MainActor
enum EffectChainLibraryActions {

    // MARK: - Save to Default Library

    /// Save current effect chains to the default library location
    /// This saves immediately (no file picker - saves to ~/Library/Application Support/Hypnograph/effects.json)
    static func saveToDefaultLibrary(session: EffectsSession) {
        session.save()
        AppNotifications.show("Effects saved to default library", flash: true)
    }

    // MARK: - Restore Default Library

    /// Restore the built-in default effects library
    /// Replaces the current library with bundled defaults
    static func restoreDefaultLibrary(session: EffectsSession, completion: @escaping @MainActor () -> Void) {
        let defaults = EffectsSession.loadBundledDefaults()
        session.replaceChains(defaults)
        AppNotifications.show("Restored \(defaults.count) default effect chains", flash: true)
        completion()
    }

    // MARK: - Save to File

    /// Save current effect chains to a user-chosen file
    /// Opens a save file dialog for .json files
    static func saveLibraryToFile(session: EffectsSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "effects.json"
        panel.message = "Save effects library"

        // Start in the Application Support folder
        panel.directoryURL = EffectConfigLoader.userConfigURL.deletingLastPathComponent()

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                session.save(to: url)
                AppNotifications.show("Effects saved to \(url.lastPathComponent)", flash: true)
            }
        }
    }

    // MARK: - Load from File

    /// Load effect chain library from a file (.json or .hypnogram)
    /// Opens a file picker that accepts both file types
    /// Includes a "Merge" checkbox (default: on) to merge vs replace effects
    static func loadLibraryFromFile(session: EffectsSession, completion: @escaping @MainActor () -> Void) {
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

        // Add accessory view with Merge checkbox
        let mergeCheckbox = NSButton(checkboxWithTitle: "Merge with existing effects", target: nil, action: nil)
        mergeCheckbox.state = .on  // Default to merge
        panel.accessoryView = mergeCheckbox

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let shouldMerge = mergeCheckbox.state == .on

            Task { @MainActor in
                let ext = url.pathExtension.lowercased()

                if ext == RecipeStore.fileExtension {
                    // Load from hypnogram file
                    loadFromHypnogram(url: url, session: session, merge: shouldMerge)
                } else {
                    // Load from JSON file
                    loadFromJSON(url: url, session: session, merge: shouldMerge)
                }

                completion()
            }
        }
    }

    /// Load effect chains from a JSON library file
    private static func loadFromJSON(url: URL, session: EffectsSession, merge: Bool) {
        do {
            let chains = try EffectConfigLoader.loadFromURL(url)
            if merge {
                session.merge(chains: chains)
                AppNotifications.show("Merged \(chains.count) effect chains", flash: true)
            } else {
                session.replaceChains(chains)
                AppNotifications.show("Loaded \(chains.count) effect chains", flash: true)
            }
        } catch {
            print("⚠️ EffectChainLibraryActions: Failed to load library from \(url.path): \(error)")
            AppNotifications.show("Failed to load effects library", flash: true)
        }
    }

    /// Load effect chains from a hypnogram recipe file
    /// If the recipe has an effectsLibrarySnapshot, uses that
    /// Otherwise extracts only the chains used in the recipe
    private static func loadFromHypnogram(url: URL, session: EffectsSession, merge: Bool) {
        guard let recipe = RecipeStore.load(from: url) else {
            AppNotifications.show("Failed to load hypnogram", flash: true)
            return
        }

        // Prefer the full library snapshot if available
        if let snapshot = recipe.effectsLibrarySnapshot, !snapshot.isEmpty {
            if merge {
                session.merge(chains: snapshot)
                AppNotifications.show("Merged \(snapshot.count) effect chains from snapshot", flash: true)
            } else {
                session.replaceChains(snapshot)
                AppNotifications.show("Loaded \(snapshot.count) effect chains from snapshot", flash: true)
            }
            return
        }

        // Fallback: extract only the chains used in the recipe
        let chains = extractEffectChains(from: recipe)

        if chains.isEmpty {
            AppNotifications.show("No effect chains found in hypnogram", flash: true)
            return
        }

        if merge {
            session.merge(chains: chains)
            AppNotifications.show("Merged \(chains.count) effect chains", flash: true)
        } else {
            session.replaceChains(chains)
            AppNotifications.show("Loaded \(chains.count) effect chains", flash: true)
        }
    }

    // MARK: - Recipe Import

    /// Import effect chains from a recipe into the session (used when loading hypnograms)
    /// Merges chains into the library, avoiding duplicates by name
    static func importChainsFromRecipe(_ recipe: HypnogramRecipe, into session: EffectsSession) {
        let chains = extractEffectChains(from: recipe)
        guard !chains.isEmpty else { return }
        session.merge(chains: chains)
    }

    // MARK: - Private Helpers

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
}
