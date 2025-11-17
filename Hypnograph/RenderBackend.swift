//
//  RenderBackend.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//


import Foundation

/// A backend that knows how to take a HypnogramRecipe and
/// turn it into *something* (JSON, a rendered video file, etc.).
///
/// For now we'll only implement JSONRecipeBackend, which writes a
/// simple JSON description of the recipe to disk. A Python/ffmpeg
/// script can then watch that folder and do the heavy rendering.
protocol RenderBackend {
    /// Enqueue a recipe for rendering. The backend is responsible for
    /// performing work off the main thread as needed and calling
    /// `completion` when done.
    func enqueue(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void)
}

// MARK: - JSON Recipe Backend

/// Codable representation of a HypnogramRecipe for JSON output.
private struct JSONHypnogramRecipe: Codable {
    struct Clip: Codable {
        var path: String
        var startSeconds: Double
        var lengthSeconds: Double
    }

    struct Mode: Codable {
        var name: String
    }

    struct Layer: Codable {
        var clip: Clip
        var blendMode: Mode
    }

    var layers: [Layer]
}

/// A simple backend that writes each recipe as a JSON file
/// into an output folder. External tooling (e.g. a Python+ffmpeg
/// script) can watch this folder and produce final videos.
final class JSONRecipeBackend: RenderBackend {
    private let outputFolder: URL
    private let encoder: JSONEncoder

    init(outputFolder: URL) {
        self.outputFolder = outputFolder
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func enqueue(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void) {
        // Convert the in-memory recipe to a simple codable struct.
        let jsonLayers: [JSONHypnogramRecipe.Layer] = recipe.layers.map { layer in
            let c = layer.clip
            let m = layer.blendMode
            return JSONHypnogramRecipe.Layer(
                clip: .init(
                    path: c.file.url.path,
                    startSeconds: c.startTime.seconds,
                    lengthSeconds: c.duration.seconds
                ),
                blendMode: .init(name: m.name)
            )
        }

        let jsonRecipe = JSONHypnogramRecipe(layers: jsonLayers)

        // Perform the encoding + file write on a background queue.
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try self.encoder.encode(jsonRecipe)
                let fileManager = FileManager.default

                // Ensure the output directory exists.
                try fileManager.createDirectory(
                    at: self.outputFolder,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                // Unique filename per recipe.
                let filename = "hypnogram-\(UUID().uuidString).json"
                let url = self.outputFolder.appendingPathComponent(filename)

                try data.write(to: url)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
