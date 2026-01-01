//
//  RecipeFileActions.swift
//  Hypnograph
//
//  UI helpers for opening and saving recipe files.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum RecipeFileActions {
    static func saveAs(
        recipe: HypnogramRecipe,
        snapshot: CGImage,
        onSaved: (() -> Void)? = nil
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes()
        panel.nameFieldStringValue = RecipeStore.defaultFilename()
        panel.directoryURL = RecipeStore.recipesDirectory

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if RecipeStore.save(recipe, snapshot: snapshot, to: url) != nil {
                onSaved?()
            }
        }
    }

    static func openRecipe(
        onLoaded: @escaping (HypnogramRecipe) -> Void,
        onFailure: (() -> Void)? = nil
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedContentTypes()
        panel.directoryURL = RecipeStore.recipesDirectory
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let recipe = RecipeStore.load(from: url) else {
                onFailure?()
                return
            }
            onLoaded(recipe)
        }
    }

    private static func allowedContentTypes() -> [UTType] {
        let types = RecipeStore.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [UTType.data] : types
    }
}
