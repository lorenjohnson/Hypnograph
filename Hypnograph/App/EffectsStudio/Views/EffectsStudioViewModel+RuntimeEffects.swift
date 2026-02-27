//
//  EffectsStudioViewModel+RuntimeEffects.swift
//  Hypnograph
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import HypnoCore

extension EffectsStudioViewModel {
    var runtimeEffectsDirectoryPath: String {
        runtimeEffectsDirectoryURL.path
    }

    var manifestPreviewJSON: String {
        guard let json = encodeRuntimeManifestJSON(runtimeManifestFromCurrentState()) else {
            return "{}"
        }
        return json
    }

    var editableParameterNames: [String] {
        parameters
            .filter { !$0.isAutoBound && !Self.isSystemParameterName($0.name) }
            .map(\.name)
            .filter { !$0.isEmpty }
    }

    var autoBoundParameterSummaries: [String] {
        parameters.compactMap { parameter in
            let name = parameter.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, parameter.isAutoBound, !Self.isSystemParameterName(name) else { return nil }
            return "\(name) <- \(parameter.autoBind.label)"
        }
    }

    var editableParameterDefinitions: [EffectsStudioParameterDraft] {
        parameters.filter { !Self.isSystemParameterName($0.name) }
    }

    func parameterSpec(named name: String) -> ParameterSpec? {
        guard let draft = parameters.first(where: { $0.name == name }) else { return nil }
        return Self.parameterSpec(for: draft)
    }

    func parameterValue(named name: String) -> AnyCodableValue? {
        parameterValues[name]
    }

    func updateControlParameter(name: String, value: AnyCodableValue) {
        if let draft = parameters.first(where: { $0.name == name }), draft.type == .choice {
            parameterValues[name] = canonicalChoiceValue(for: draft, rawValue: value)
        } else {
            parameterValues[name] = value
        }
        renderPreview()
    }

    func parameterDefinitionDidChange() {
        ensureSystemParameters()
        rebuildParameterValues(preserveExisting: true)
    }

    func addParameter() {
        let name = nextParameterName(base: "param")
        parameters.append(.default(named: name))
        parameterDefinitionDidChange()
    }

    func removeParameter(id: UUID) {
        parameters.removeAll { $0.id == id }
        parameterDefinitionDidChange()
    }

    func insertParameterUsage(name: String) {
        guard !name.isEmpty else { return }
        pendingCodeInsertion = "params.\(name)"
    }

    func resetToTemplate() {
        sourceCode = EffectsStudioViewModel.defaultCodeBody
        parameters = EffectsStudioViewModel.defaultParameters
        ensureSystemParameters()
        activeRuntimeKind = .metal
        activeRequiredLookback = 0
        activeUsesPersistentState = false
        activeBindings = Self.defaultRuntimeBindings
        selectedRuntimeType = ""
        runtimeEffectUUID = UUID().uuidString.lowercased()
        runtimeEffectName = "New Effect"
        runtimeEffectVersion = "1.0.0"
        rebuildParameterValues(preserveExisting: false)
        resetPreviewHistory()
        compileLog = "Template restored."
    }

    func refreshRuntimeEffectList() {
        RuntimeMetalEffectLibrary.shared.reload()

        let effects = EffectRegistry.availableEffectTypes
            .filter { RuntimeMetalEffectLibrary.isRuntimeType($0.type) }
            .map { EffectsStudioRuntimeEffectChoice(type: $0.type, displayName: $0.displayName) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        runtimeEffects = effects

        if selectedRuntimeType.isEmpty {
            if !hasAppliedInitialRuntimeSelection, let first = effects.first {
                selectedRuntimeType = first.type
                hasAppliedInitialRuntimeSelection = true
            }
            return
        }

        let validTypes = Set(effects.map(\.type))
        if !validTypes.contains(selectedRuntimeType), let first = effects.first {
            selectedRuntimeType = first.type
        }
    }

    func loadRuntimeEffectAsset() {
        let uuid = Self.effectUUID(fromTypeName: selectedRuntimeType) ?? normalizedEffectUUID()
        guard !uuid.isEmpty else {
            compileLog = "Enter a valid effect UUID before loading."
            return
        }

        guard let directory = runtimeEffectDirectoryURL(forUUID: uuid) else {
            compileLog = "Runtime effect '\(uuid)' was not found."
            return
        }
        let manifestURL = directory.appendingPathComponent("effect.json")
        let shaderURL = directory.appendingPathComponent("shader.metal")

        do {
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(RuntimeMetalEffectManifest.self, from: manifestData)
            let shader = try String(contentsOf: shaderURL, encoding: .utf8)

            runtimeEffectUUID = manifest.uuid
            runtimeEffectName = manifest.name
            runtimeEffectVersion = manifest.version
            selectedRuntimeType = RuntimeMetalEffectLibrary.typeName(forUUID: manifest.uuid)
            sourceCode = shader
            activeRuntimeKind = manifest.runtimeKind ?? .metal
            activeRequiredLookback = max(0, manifest.requiredLookback ?? 0)
            activeUsesPersistentState = manifest.usesPersistentState ?? false
            activeBindings = manifest.bindings
            parameters = Self.parameterDrafts(from: manifest)
            ensureSystemParameters()
            rebuildParameterValues(preserveExisting: false)
            resetPreviewHistory()
            _ = compileCode()
            refreshRuntimeEffectList()
            compileLog = "Loaded runtime effect '\(manifest.name)' (\(manifest.uuid))."
        } catch {
            compileLog = "Failed to load runtime effect '\(uuid)': \(error.localizedDescription)"
        }
    }

    func saveRuntimeEffectAsset() {
        let uuid = normalizedEffectUUID()
        guard UUID(uuidString: uuid) != nil else {
            compileLog = "Enter a valid effect UUID before saving."
            return
        }
        runtimeEffectUUID = uuid

        let fm = FileManager.default
        let directory = runtimeEffectsDirectoryURL.appendingPathComponent(uuid, isDirectory: true)
        let manifestURL = directory.appendingPathComponent("effect.json")
        let shaderURL = directory.appendingPathComponent("shader.metal")

        do {
            if !fm.fileExists(atPath: directory.path) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let manifest = runtimeManifestFromCurrentState()
            guard let json = encodeRuntimeManifestJSON(manifest) else {
                compileLog = "Failed to encode effect manifest."
                return
            }

            try json.write(to: manifestURL, atomically: true, encoding: .utf8)
            try sourceCode.write(to: shaderURL, atomically: true, encoding: .utf8)
            refreshRuntimeEffectList()
            selectedRuntimeType = RuntimeMetalEffectLibrary.typeName(forUUID: uuid)
            compileLog = "Saved runtime effect '\(runtimeEffectName)' (\(uuid)) to \(directory.path)"
        } catch {
            compileLog = "Failed to save runtime effect '\(uuid)': \(error.localizedDescription)"
        }
    }

    func deleteRuntimeEffectAsset() {
        let uuid = Self.effectUUID(fromTypeName: selectedRuntimeType) ?? normalizedEffectUUID()
        guard UUID(uuidString: uuid) != nil else {
            compileLog = "Select a valid runtime effect before deleting."
            return
        }

        guard let directory = runtimeEffectDirectoryURL(forUUID: uuid) else {
            compileLog = "Runtime effect '\(uuid)' was not found."
            return
        }

        do {
            try FileManager.default.removeItem(at: directory)
            refreshRuntimeEffectList()

            if runtimeEffects.isEmpty {
                selectedRuntimeType = ""
                resetToTemplate()
                compileLog = "Deleted runtime effect '\(uuid)'. No runtime effects remain."
            } else {
                compileLog = "Deleted runtime effect '\(uuid)'."
            }
        } catch {
            compileLog = "Failed to delete runtime effect '\(uuid)': \(error.localizedDescription)"
        }
    }

    func chooseCodeSourceFile() {
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

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            sourceCode = try String(contentsOf: url, encoding: .utf8)
            compileLog = "Loaded shader source: \(url.lastPathComponent)"
        } catch {
            compileLog = "Failed to load shader source: \(error.localizedDescription)"
        }
    }
}
