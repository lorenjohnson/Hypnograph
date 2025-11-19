////
////  RenderQueue.swift
////  Hypnograph
////
////  Created by Loren Johnson on 15.11.25.
////

import Foundation

/// Manages a queue of rendering jobs for Hypnogram.
/// Wraps a HypnogramRenderer and keeps track of active jobs.
///
/// This also supports the "quit when all renders are done" behavior:
/// - Call `requestTerminateWhenDone()` when the user presses Esc.
/// - When `activeJobs` reaches 0, `onAllJobsFinished` is invoked.
final class RenderQueue: ObservableObject {
    private let renderer: HypnogramRenderer

    /// Number of currently active jobs (being processed).
    @Published private(set) var activeJobs: Int = 0

    /// If true, we should terminate the app when activeJobs reaches 0.
    private var pendingTerminate: Bool = false

    /// Called on the main thread when all jobs are finished
    /// and `requestTerminateWhenDone()` had been called.
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

                // You can add logging here if desired:
                switch result {
                case .success(let url):
                    print("Render job finished: \(url.path)")
                case .failure(let error):
                    print("Render job failed: \(error.localizedDescription)")
                }

                // If we had requested termination and there are no more jobs,
                // trigger the callback so the app can terminate.
                if self.activeJobs == 0, self.pendingTerminate {
                    self.onAllJobsFinished?()
                }
            }
        }
    }
}
