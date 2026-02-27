//
//  RuntimeEffectsService.swift
//  Hypnograph
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import HypnoCore

enum RuntimeEffectsServiceError: LocalizedError {
    case effectNotFound(String)

    var errorDescription: String? {
        switch self {
        case .effectNotFound(let uuid):
            return "Runtime effect '\(uuid)' was not found."
        }
    }
}

struct RuntimeEffectsService {
    struct RuntimeEffectChoice {
        var type: String
        var displayName: String
    }

    struct LoadedRuntimeEffectAsset {
        var manifest: RuntimeMetalEffectManifest
        var shaderSource: String
    }

    let fileManager: FileManager
    let runtimeLibrary: RuntimeMetalEffectLibrary

    init(
        fileManager: FileManager = .default,
        runtimeLibrary: RuntimeMetalEffectLibrary = .shared
    ) {
        self.fileManager = fileManager
        self.runtimeLibrary = runtimeLibrary
    }

    static let live = RuntimeEffectsService()

    var runtimeEffectsDirectoryURL: URL {
        HypnoCoreConfig.shared.runtimeEffectsDirectory
    }

    func runtimeEffectDirectoryURL(forUUID uuid: String) -> URL? {
        let direct = runtimeEffectsDirectoryURL.appendingPathComponent(uuid, isDirectory: true)
        return fileManager.fileExists(atPath: direct.path) ? direct : nil
    }

    func refreshAvailableRuntimeEffects() -> [RuntimeEffectChoice] {
        runtimeLibrary.reload()
        return EffectRegistry.availableEffectTypes
            .filter { RuntimeMetalEffectLibrary.isRuntimeType($0.type) }
            .map { RuntimeEffectChoice(type: $0.type, displayName: $0.displayName) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func typeName(forUUID uuid: String) -> String {
        RuntimeMetalEffectLibrary.typeName(forUUID: uuid)
    }

    func loadRuntimeEffectAsset(uuid: String) throws -> LoadedRuntimeEffectAsset {
        guard let directory = runtimeEffectDirectoryURL(forUUID: uuid) else {
            throw RuntimeEffectsServiceError.effectNotFound(uuid)
        }

        let manifestURL = directory.appendingPathComponent("effect.json")
        let shaderURL = directory.appendingPathComponent("shader.metal")

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(RuntimeMetalEffectManifest.self, from: manifestData)
        let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)
        return LoadedRuntimeEffectAsset(manifest: manifest, shaderSource: shaderSource)
    }

    func saveRuntimeEffectAsset(
        uuid: String,
        manifestJSON: String,
        sourceCode: String
    ) throws -> URL {
        let directory = runtimeEffectsDirectoryURL.appendingPathComponent(uuid, isDirectory: true)
        let manifestURL = directory.appendingPathComponent("effect.json")
        let shaderURL = directory.appendingPathComponent("shader.metal")

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)
        try sourceCode.write(to: shaderURL, atomically: true, encoding: .utf8)
        runtimeLibrary.reload()
        return directory
    }

    func deleteRuntimeEffectAsset(uuid: String) throws {
        guard let directory = runtimeEffectDirectoryURL(forUUID: uuid) else {
            throw RuntimeEffectsServiceError.effectNotFound(uuid)
        }

        try fileManager.removeItem(at: directory)
        runtimeLibrary.reload()
    }

    func chooseCodeSourceFileURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        var contentTypes: [UTType] = [.plainText, .sourceCode]
        if let metalType = UTType(filenameExtension: "metal") {
            contentTypes.append(metalType)
        }
        panel.allowedContentTypes = contentTypes

        panel.title = "Open Metal Source"
        panel.message = "Select a .metal or text source file."

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func loadCodeSource(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
