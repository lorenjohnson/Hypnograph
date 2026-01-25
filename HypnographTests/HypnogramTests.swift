//
//  HypnogramTests.swift
//  HypnographTests
//
//  Created by Loren Johnson on 15.11.25.
//

import Testing
import CoreMedia
import HypnoCore
import Foundation
@testable import Hypnograph

struct HypnographTests {

    // Divine-specific tests moved to Divine (separate target)
    // Add Hypnograph-specific tests here

    @Test func ensureSettingsFileExists_repairsMixedSourcesDictionary() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let settingsURL = dir.appendingPathComponent("hypnograph-settings.json")
        let bundledURL = dir.appendingPathComponent("default-settings.json")

        let bundled = """
        {
          "watchMode": true,
          "sources": {
            "default": "~/Movies/Hypnograph/sources",
            "From Finder Helper": []
          },
          "outputFolder": "~/Movies/Hypnograph/renders"
        }
        """
        try Data(bundled.utf8).write(to: bundledURL, options: .atomic)

        Environment.ensureSettingsFileExists(
            at: settingsURL,
            bundledURL: bundledURL,
            defaultSettings: Settings.defaultValue
        )

        let data = try Data(contentsOf: settingsURL)
        let settings = try JSONDecoder().decode(Settings.self, from: data)

        #expect(settings.sources.libraries["default"]?.contains("~/Movies/Hypnograph/sources") == true)
        #expect(settings.sources.libraries["From Finder Helper"] != nil)
    }

    @Test func ensureSettingsFileExists_backsUpAndRewritesOnInvalidJSON() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let settingsURL = dir.appendingPathComponent("hypnograph-settings.json")
        try Data("not-json".utf8).write(to: settingsURL, options: .atomic)

        Environment.ensureSettingsFileExists(
            at: settingsURL,
            bundledURL: nil,
            defaultSettings: Settings.defaultValue
        )

        let data = try Data(contentsOf: settingsURL)
        _ = try JSONDecoder().decode(Settings.self, from: data)

        let names = try fm.contentsOfDirectory(atPath: dir.path)
        let backups = names.filter { $0.hasPrefix("hypnograph-settings.invalid-") && $0.hasSuffix(".json") }
        #expect(!backups.isEmpty)
    }
}
