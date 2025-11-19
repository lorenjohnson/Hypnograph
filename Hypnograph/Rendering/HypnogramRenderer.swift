//
//  HypnogramRenderer.swift
//  Hypnograph
//
//  Created by Loren Johnson on 17.11.25.
//


import Foundation

/// Engine-level contract: “turn this recipe into some output”.
public protocol HypnogramRenderer {
    /// Implementations decide what the URL points to (video file, JSON, etc.)
    func enqueue(recipe: HypnogramRecipe,
                 completion: @escaping (Result<URL, Error>) -> Void)
}
