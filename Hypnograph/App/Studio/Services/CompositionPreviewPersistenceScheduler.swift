//
//  CompositionPreviewPersistenceScheduler.swift
//  Hypnograph
//

import Foundation

@MainActor
final class CompositionPreviewPersistenceScheduler {
    private var pendingTask: Task<Void, Never>?

    func schedule(
        after delaySeconds: TimeInterval,
        priority: TaskPriority = ThumbnailWorkPolicy.compositionPreviewTaskPriority,
        operation: @escaping @MainActor () async -> Void
    ) {
        cancel()

        pendingTask = Task(priority: priority) {
            let delayNanoseconds = UInt64(max(0, delaySeconds) * 1_000_000_000)
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
