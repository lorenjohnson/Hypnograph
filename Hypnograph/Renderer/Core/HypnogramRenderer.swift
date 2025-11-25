//
//  HypnogramRenderer.swift
//  Hypnograph
//
//  Protocol for render backends (Montage, Sequence, etc.).
//

import Foundation

/// A renderer takes a *pure* HypnogramRecipe (blueprint)
/// and produces a rendered movie file on disk.
protocol HypnogramRenderer: AnyObject {
    /// Enqueue a render for the given recipe.
    ///
    /// - Parameters:
    ///   - recipe: Mode-agnostic blueprint with optional mode payload.
    ///   - completion: Called on the main thread with success/failure + output URL.
    func enqueue(
        recipe: HypnogramRecipe,
        completion: @escaping (Result<URL, Error>) -> Void
    )
}
