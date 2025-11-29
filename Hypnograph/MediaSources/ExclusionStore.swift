import Foundation

/// Simple persistent exclusion list for source videos.
/// Works with VideoFile.Source to support both file URLs and (future) Photos identifiers.
final class ExclusionStore {
    static let shared = ExclusionStore()

    private var excludedIdentifiers: Set<String> = []
    private let queue = DispatchQueue(label: "ExclusionStore.queue")

    private init() {
        load()
    }

    func isExcluded(_ source: VideoFile.Source) -> Bool {
        queue.sync {
            excludedIdentifiers.contains(identifier(for: source))
        }
    }

    func add(_ source: VideoFile.Source) {
        queue.sync {
            excludedIdentifiers.insert(identifier(for: source))
            save()
        }
    }

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
        let url = Environment.exclusionsURL
        guard let data = try? Data(contentsOf: url) else { return }
        if let list = try? JSONDecoder().decode([String].self, from: data) {
            excludedIdentifiers = Set(list)
        }
    }

    private func save() {
        let url = Environment.exclusionsURL
        let list = Array(excludedIdentifiers)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: url)
        }
    }
}
