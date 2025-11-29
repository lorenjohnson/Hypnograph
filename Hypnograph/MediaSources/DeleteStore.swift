//
//  DeleteStore.swift
//  Hypnograph
//
//  Persistent queue of sources marked for deletion.
//  Similar to ExclusionStore but for files the user wants to actually remove.
//

import Foundation

/// Persistent queue of sources the user has marked for deletion.
/// The actual deletion is deferred - this just tracks the list.
final class DeleteStore {
    static let shared = DeleteStore()

    private var queuedIdentifiers: Set<String> = []
    private let queue = DispatchQueue(label: "DeleteStore.queue")

    private init() {
        load()
    }

    /// Check if a source is queued for deletion
    func isQueued(_ source: VideoFile.Source) -> Bool {
        queue.sync {
            queuedIdentifiers.contains(identifier(for: source))
        }
    }

    /// Add a source to the delete queue
    func add(_ source: VideoFile.Source) {
        queue.sync {
            queuedIdentifiers.insert(identifier(for: source))
            save()
        }
    }

    /// Remove a source from the delete queue (if user changes their mind)
    func remove(_ source: VideoFile.Source) {
        queue.sync {
            queuedIdentifiers.remove(identifier(for: source))
            save()
        }
    }

    /// Get all queued identifiers (for processing)
    var allQueued: [String] {
        queue.sync {
            Array(queuedIdentifiers)
        }
    }

    /// Clear the entire queue
    func clearAll() {
        queue.sync {
            queuedIdentifiers.removeAll()
            save()
        }
    }

    /// Number of items in queue
    var count: Int {
        queue.sync { queuedIdentifiers.count }
    }

    // MARK: - Private

    /// Extract a stable identifier from the source for persistence
    private func identifier(for source: VideoFile.Source) -> String {
        switch source {
        case .url(let url):
            return "file:" + url.standardizedFileURL.path
        case .photos(let id):
            return "photos:" + id
        }
    }

    private func load() {
        let url = Environment.deletionsURL
        guard let data = try? Data(contentsOf: url) else { return }
        if let list = try? JSONDecoder().decode([String].self, from: data) {
            queuedIdentifiers = Set(list)
        }
    }

    private func save() {
        let url = Environment.deletionsURL
        let list = Array(queuedIdentifiers)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: url)
        }
    }
}

