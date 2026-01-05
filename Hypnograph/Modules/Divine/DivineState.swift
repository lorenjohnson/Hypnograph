import Foundation
import HypnoCore

@MainActor
final class DivineState {
    private let randomClipProvider: () -> VideoClip?
    private let excludeProvider: (MediaFile) -> Void
    private let favoriteStore: FavoriteStore

    init(state: HypnographState) {
        self.randomClipProvider = {
            state.library.randomClip()
        }
        self.excludeProvider = { file in
            state.library.exclude(file: file)
        }
        self.favoriteStore = state.favoriteStore
    }

    init(
        randomClip: @escaping () -> VideoClip?,
        exclude: @escaping (MediaFile) -> Void,
        favoriteStore: FavoriteStore
    ) {
        self.randomClipProvider = randomClip
        self.excludeProvider = exclude
        self.favoriteStore = favoriteStore
    }

    func randomClip() -> VideoClip? {
        randomClipProvider()
    }

    func exclude(file: MediaFile) {
        excludeProvider(file)
    }

    @discardableResult
    func toggleFavorite(_ source: MediaFile.Source) -> Bool {
        favoriteStore.toggle(source)
    }
}
