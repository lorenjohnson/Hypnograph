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
import Foundation
@testable import Hypnograph

struct HypnographTests {

    @MainActor
    @Test func divineCardManagerCreatesUniqueCards() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let imageAURL = tempDir.appendingPathComponent("clip-a.png")
        let imageBURL = tempDir.appendingPathComponent("clip-b.png")
        try writeTestImage(at: imageAURL)
        try writeTestImage(at: imageBURL)

        let settingsURL = tempDir.appendingPathComponent("divine-settings.json")
        let settings = DivineSettings(
            sources: .array([tempDir.path]),
            sourceMediaTypes: [.images],
            activeLibraryKeys: ["default"]
        )
        let settingsData = try JSONEncoder().encode(settings)
        try settingsData.write(to: settingsURL)

        let coreConfig = HypnoCoreConfig(appSupportDirectory: tempDir)
        HypnoCoreConfig.shared = coreConfig
        let state = DivineState(coreConfig: coreConfig, settingsURL: settingsURL)

        let manager = DivineCardManager(state: state)
        manager.addCardAtOffsetAtCenter()
        manager.addCardAtOffsetAtCenter()

        #expect(manager.cards.count == 2)
        let ids = Set(manager.cards.map { $0.clip.file.id })
        #expect(ids.count == 2)
    }

    private func writeTestImage(at url: URL) throws {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5bVx8AAAAASUVORK5CYII="
        guard let data = Data(base64Encoded: pngBase64) else {
            throw NSError(domain: "HypnographTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode PNG"])
        }
        try data.write(to: url)
    }

}
