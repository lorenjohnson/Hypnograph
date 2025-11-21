import Foundation

/// Simple persistent exclusion list for source videos.
final class ExclusionStore {
    static let shared = ExclusionStore()

    private var excludedPaths: Set<String> = []
    private let queue = DispatchQueue(label: "ExclusionStore.queue")

    private init() {
        load()
    }

    func isExcluded(url: URL) -> Bool {
        queue.sync {
            excludedPaths.contains(url.standardizedFileURL.path)
        }
    }

    func add(url: URL) {
        queue.sync {
            excludedPaths.insert(url.standardizedFileURL.path)
            save()
        }
    }

    private func load() {
        let url = Environment.exclusionsURL
        guard let data = try? Data(contentsOf: url) else { return }
        if let list = try? JSONDecoder().decode([String].self, from: data) {
            excludedPaths = Set(list)
        }
    }

    private func save() {
        let url = Environment.exclusionsURL
        let list = Array(excludedPaths)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: url)
        }
    }
}
