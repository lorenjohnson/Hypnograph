import Foundation

@MainActor
final class DivineState {
    private let randomClipProvider: () -> VideoClip?
    private let excludeProvider: (MediaFile) -> Void

    init(state: HypnographState) {
        self.randomClipProvider = {
            state.library.randomFullClip()
        }
        self.excludeProvider = { file in
            state.library.exclude(file: file)
        }
    }

    init(
        randomClip: @escaping () -> VideoClip?,
        exclude: @escaping (MediaFile) -> Void
    ) {
        self.randomClipProvider = randomClip
        self.excludeProvider = exclude
    }

    func randomClip() -> VideoClip? {
        randomClipProvider()
    }

    func exclude(file: MediaFile) {
        excludeProvider(file)
    }
}
