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
    var outputHeight: Int
    var outputSeconds: Int
    var outputWidth: Int
    var snapshotsFolder: String
    var activeLibrariesPerMode: [String: [String]]
    var allowStillImages: Bool  // Temporary: set to false to test if still images cause performance issues

    // Single source of truth for defaults
    private enum Defaults {
        static let watch: Bool = true
        static let maxSourcesForNew = 5
        static let outputFolder = "~/Movies/Hypnograph/renders"
        static let snapshotsFolder = "~/Movies/Hypnograph/snapshots"
        static let outputHeight = 1080
        static let outputSeconds = 60
        static let outputWidth = 1920
        static let sourceFolders = SourceFoldersParam.array([
            "~/Movies/Hypnograph/sources"
        ])
        static let activeLibrariesPerMode: [String: [String]] = [:]
        static let allowStillImages: Bool = true
    }

    private enum CodingKeys: String, CodingKey {
        case outputFolder, sourceFolders
        case watch, maxSourcesForNew, outputHeight, outputSeconds, outputWidth, snapshotsFolder
        case activeLibrariesPerMode, allowStillImages
    }
    init(
        outputFolder: String,
        sourceFolders: SourceFoldersParam,
        watch: Bool = Defaults.watch,
        maxSourcesForNew: Int = Defaults.maxSourcesForNew,
        outputHeight: Int = Defaults.outputHeight,
        outputSeconds: Int = Defaults.outputSeconds,
        outputWidth: Int = Defaults.outputWidth,
        snapshotsFolder: String = Defaults.snapshotsFolder,
        activeLibrariesPerMode: [String: [String]] = Defaults.activeLibrariesPerMode,
        allowStillImages: Bool = Defaults.allowStillImages
    ) {
        self.outputFolder = outputFolder
        self.sourceFolders = sourceFolders
        self.watch = watch
        self.maxSourcesForNew = maxSourcesForNew
        self.outputHeight = outputHeight
        self.outputSeconds = outputSeconds
        self.outputWidth = outputWidth
        self.snapshotsFolder = snapshotsFolder
        self.activeLibrariesPerMode = activeLibrariesPerMode
        self.allowStillImages = allowStillImages
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
        outputHeight = try c.decodeIfPresent(Int.self, forKey: .outputHeight)
            ?? Defaults.outputHeight
        outputSeconds = try c.decodeIfPresent(Int.self, forKey: .outputSeconds)
            ?? Defaults.outputSeconds
        outputWidth = try c.decodeIfPresent(Int.self, forKey: .outputWidth)
            ?? Defaults.outputWidth
        snapshotsFolder = try c.decodeIfPresent(String.self, forKey: .snapshotsFolder)
            ?? Defaults.snapshotsFolder
        activeLibrariesPerMode = try c.decodeIfPresent([String: [String]].self, forKey: .activeLibrariesPerMode)
            ?? Defaults.activeLibrariesPerMode
        allowStillImages = try c.decodeIfPresent(Bool.self, forKey: .allowStillImages)
            ?? Defaults.allowStillImages
    }

    // MARK: - Derived values

    var outputDuration: CMTime {
        CMTime(seconds: Double(outputSeconds), preferredTimescale: 600)
    }

    var outputSize: CGSize {
        Self.computeOutputSize(outputHeight: outputHeight, outputWidth: outputWidth)
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

    private static func computeOutputSize(outputHeight: Int, outputWidth: Int) -> CGSize {
        let defaultW: CGFloat = 1920
        let defaultH: CGFloat = 1080
        let aspect: CGFloat   = 9.0 / 16.0

        let w = CGFloat(outputWidth)
        let h = CGFloat(outputHeight)

        switch (w > 0, h > 0) {
        case (true, true):
            return CGSize(width: w, height: h)
        case (true, false):
            return CGSize(width: w, height: round(w * aspect))
        case (false, true):
            return CGSize(width: round(h / aspect), height: h)
        default:
            return CGSize(width: defaultW, height: defaultH)
        }
    }
}

// MARK: - Loader

enum SettingsLoader {
    static func load(from url: URL) throws -> Settings {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Settings.self, from: data)
    }
}
