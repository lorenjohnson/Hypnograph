//
//  Settings.swift
//  Hypnograph
//

import Foundation
import AppKit
import CoreGraphics
import CoreMedia

// MARK: - Polymorphic sourceFolders

enum SourceFoldersParam: Codable {
    case array([String])
    case dictionary([String: [String]])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if let dictArray = try? c.decode([String: [String]].self) {
            self = .dictionary(dictArray)
            return
        }

        if let dictString = try? c.decode([String: String].self) {
            self = .dictionary(dictString.mapValues { [$0] })
            return
        }

        if let arr = try? c.decode([String].self) {
            self = .array(arr)
            return
        }

        throw DecodingError.typeMismatch(
            SourceFoldersParam.self,
            .init(codingPath: decoder.codingPath,
                  debugDescription: "Expected [String], [String: String], or [String: [String]]")
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .array(let arr):
            try c.encode(arr)
        case .dictionary(let dict):
            try c.encode(dict)
        }
    }

    var libraries: [String: [String]] {
        switch self {
        case .array(let arr):
            return ["default": arr]
        case .dictionary(let dict):
            return dict
        }
    }

    var libraryOrder: [String] {
        switch self {
        case .array:
            return ["default"]
        case .dictionary(let dict):
            return Array(dict.keys)
        }
    }

    var defaultKey: String {
        let libs = libraries
        if libs.keys.contains("default") { return "default" }
        if let k = libs.keys.first(where: { $0.lowercased() == "default" }) { return k }
        return libraryOrder.first ?? "default"
    }
}

// MARK: - Settings

struct Settings: Codable {
    // Required in JSON
    var outputFolder: String
    var sourceFolders: SourceFoldersParam

    // Optional in JSON (but non-optional in code)
    var watch: Bool
    var maxSourcesForNew: Int
    var outputSeconds: Int
    var snapshotsFolder: String
    var activeLibrariesPerMode: [String: [String]]
    var allowStillImages: Bool

    /// Aspect ratio for composition (e.g., 16:9, 4:3, 2.35:1)
    var aspectRatio: AspectRatio

    /// Max dimension for disk output (720, 1080, 2160)
    var maxOutputDimension: Int

    // Single source of truth for defaults
    private enum Defaults {
        static let watch: Bool = true
        static let maxSourcesForNew = 5
        static let outputFolder = "~/Movies/Hypnograph/renders"
        static let snapshotsFolder = "~/Movies/Hypnograph/snapshots"
        static let outputSeconds = 60
        static let sourceFolders = SourceFoldersParam.array([
            "~/Movies/Hypnograph/sources"
        ])
        static let activeLibrariesPerMode: [String: [String]] = [:]
        static let allowStillImages: Bool = true
        static let aspectRatio: AspectRatio = .ratio16x9
        static let maxOutputDimension: Int = 1080
    }

    private enum CodingKeys: String, CodingKey {
        case outputFolder, sourceFolders
        case watch, maxSourcesForNew, outputSeconds, snapshotsFolder
        case activeLibrariesPerMode, allowStillImages
        case aspectRatio, maxOutputDimension
    }

    init(
        outputFolder: String,
        sourceFolders: SourceFoldersParam,
        watch: Bool = Defaults.watch,
        maxSourcesForNew: Int = Defaults.maxSourcesForNew,
        outputSeconds: Int = Defaults.outputSeconds,
        snapshotsFolder: String = Defaults.snapshotsFolder,
        activeLibrariesPerMode: [String: [String]] = Defaults.activeLibrariesPerMode,
        allowStillImages: Bool = Defaults.allowStillImages,
        aspectRatio: AspectRatio = Defaults.aspectRatio,
        maxOutputDimension: Int = Defaults.maxOutputDimension
    ) {
        self.outputFolder = outputFolder
        self.sourceFolders = sourceFolders
        self.watch = watch
        self.maxSourcesForNew = maxSourcesForNew
        self.outputSeconds = outputSeconds
        self.snapshotsFolder = snapshotsFolder
        self.activeLibrariesPerMode = activeLibrariesPerMode
        self.allowStillImages = allowStillImages
        self.aspectRatio = aspectRatio
        self.maxOutputDimension = maxOutputDimension
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        outputFolder   = try c.decodeIfPresent(String.self, forKey: .outputFolder)
            ?? Defaults.outputFolder
        sourceFolders  = try c.decodeIfPresent(SourceFoldersParam.self, forKey: .sourceFolders)
            ?? Defaults.sourceFolders
        watch = try c.decodeIfPresent(Bool.self, forKey: .watch)
            ?? Defaults.watch
        maxSourcesForNew = try c.decodeIfPresent(Int.self, forKey: .maxSourcesForNew)
            ?? Defaults.maxSourcesForNew
        outputSeconds = try c.decodeIfPresent(Int.self, forKey: .outputSeconds)
            ?? Defaults.outputSeconds
        snapshotsFolder = try c.decodeIfPresent(String.self, forKey: .snapshotsFolder)
            ?? Defaults.snapshotsFolder
        activeLibrariesPerMode = try c.decodeIfPresent([String: [String]].self, forKey: .activeLibrariesPerMode)
            ?? Defaults.activeLibrariesPerMode
        allowStillImages = try c.decodeIfPresent(Bool.self, forKey: .allowStillImages)
            ?? Defaults.allowStillImages
        aspectRatio = try c.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio)
            ?? Defaults.aspectRatio
        maxOutputDimension = try c.decodeIfPresent(Int.self, forKey: .maxOutputDimension)
            ?? Defaults.maxOutputDimension
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(outputFolder, forKey: .outputFolder)
        try c.encode(sourceFolders, forKey: .sourceFolders)
        try c.encode(watch, forKey: .watch)
        try c.encode(maxSourcesForNew, forKey: .maxSourcesForNew)
        try c.encode(outputSeconds, forKey: .outputSeconds)
        try c.encode(snapshotsFolder, forKey: .snapshotsFolder)
        try c.encode(activeLibrariesPerMode, forKey: .activeLibrariesPerMode)
        try c.encode(allowStillImages, forKey: .allowStillImages)
        try c.encode(aspectRatio, forKey: .aspectRatio)
        try c.encode(maxOutputDimension, forKey: .maxOutputDimension)
    }

    // MARK: - Derived values

    var outputDuration: CMTime {
        CMTime(seconds: Double(outputSeconds), preferredTimescale: 600)
    }

    var outputURL: URL {
        URL(
            fileURLWithPath: (outputFolder as NSString).expandingTildeInPath,
            isDirectory: true
        )
    }

    var snapshotsURL: URL {
        URL(
            fileURLWithPath: (snapshotsFolder as NSString).expandingTildeInPath,
            isDirectory: true
        )
    }

    var sourceLibraries: [String: [String]] {
        sourceFolders.libraries.mapValues { folders in
            folders.map { ($0 as NSString).expandingTildeInPath }
        }
    }

    var sourceLibraryOrder: [String] {
        let order = sourceFolders.libraryOrder
        return order.isEmpty ? [defaultSourceLibraryKey] : order
    }

    var defaultSourceLibraryKey: String {
        sourceFolders.defaultKey
    }

    var activeSourceFolders: [String] {
        sourceLibraries[defaultSourceLibraryKey]
            ?? sourceLibraryOrder.first.flatMap { sourceLibraries[$0] }
            ?? sourceLibraries.values.first
            ?? []
    }

    func folders(forLibraries keys: Set<String>) -> [String] {
        var result: [String] = []
        for key in sourceLibraryOrder where keys.contains(key) {
            if let paths = sourceLibraries[key] {
                result.append(contentsOf: paths)
            }
        }
        return result
    }
}

// MARK: - Loader

enum SettingsLoader {
    static func load(from url: URL) throws -> Settings {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Settings.self, from: data)
    }
}
