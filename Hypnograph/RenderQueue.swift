////
////  RenderQueue.swift
////  Hypnograph
////
////  Created by Loren Johnson on 15.11.25.
////

import Foundation

/// Manages a queue of rendering jobs for Hypnogram.
/// Wraps a HypnogramRenderer and keeps track of active jobs.
final class RenderQueue: ObservableObject {
    private let renderer: HypnogramRenderer

    /// Number of currently active jobs (being processed).
    @Published private(set) var activeJobs: Int = 0

    /// Called on the main thread whenever `activeJobs` drops to 0.
    /// The app can use this to e.g. reply to `applicationShouldTerminate`.
    var onAllJobsFinished: (() -> Void)?

    init(renderer: HypnogramRenderer) {
        self.renderer = renderer
    }

    /// Enqueue a new HypnogramRecipe for rendering.
    func enqueue(recipe: HypnogramRecipe) {
        activeJobs += 1

        renderer.enqueue(recipe: recipe) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activeJobs -= 1

                switch result {
                case .success(let url):
                    print("Render job finished: \(url.path)")
                case .failure(let error):
                    print("Render job failed: \(error.localizedDescription)")
                }

                if self.activeJobs == 0 {
                    self.onAllJobsFinished?()
                }
            }
        }
    }
}
