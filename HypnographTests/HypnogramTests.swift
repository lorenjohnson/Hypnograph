//
//  HypnographTests.swift
//  HypnographTests
//
//  Created by Loren Johnson on 15.11.25.
//

import Testing
import CoreMedia
import HypnoCore
import HypnoEffects
@testable import Hypnograph

struct HypnographTests {

    @MainActor
    @Test func divineCardManagerCreatesUniqueCards() async throws {
        var clips = makeClips()
        let state = DivineState(
            randomClip: {
                guard !clips.isEmpty else { return nil }
                return clips.removeFirst()
            },
            exclude: { _ in }
        )

        let manager = DivineCardManager(state: state)
        manager.addCardAtOffsetAtCenter()
        manager.addCardAtOffsetAtCenter()

        #expect(manager.cards.count == 2)
        let ids = Set(manager.cards.map { $0.clip.file.id })
        #expect(ids.count == 2)
    }

    private func makeClips() -> [VideoClip] {
        [
            makeClip(name: "clip-a.mov"),
            makeClip(name: "clip-b.mov")
        ]
    }

    private func makeClip(name: String) -> VideoClip {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        let duration = CMTime(seconds: 5, preferredTimescale: 600)
        let file = MediaFile(source: .url(url), mediaKind: .video, duration: duration)
        return VideoClip(file: file, startTime: .zero, duration: duration)
    }

}
