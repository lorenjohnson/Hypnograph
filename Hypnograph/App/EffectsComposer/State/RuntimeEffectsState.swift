//
//  RuntimeEffectsState.swift
//  Hypnograph
//

import Foundation
import HypnoCore

extension EffectsComposerViewModel {
    var runtimeEffectsDirectoryPath: String {
        runtimeEffectsService.runtimeEffectsDirectoryURL.path
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

    var editableParameterDefinitions: [EffectsComposerParameterDraft] {
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
        sourceCode = EffectsComposerViewModel.defaultCodeBody
        parameters = EffectsComposerViewModel.defaultParameters
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
        let effects = runtimeEffectsService
            .refreshAvailableRuntimeEffects()
            .map { EffectsComposerRuntimeEffectChoice(type: $0.type, displayName: $0.displayName) }

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

        do {
            let loaded = try runtimeEffectsService.loadRuntimeEffectAsset(uuid: uuid)
            let manifest = loaded.manifest

            runtimeEffectUUID = manifest.uuid
            runtimeEffectName = manifest.name
            runtimeEffectVersion = manifest.version
            selectedRuntimeType = runtimeEffectsService.typeName(forUUID: manifest.uuid)
            sourceCode = loaded.shaderSource
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

        do {
            let manifest = runtimeManifestFromCurrentState()
            guard let json = encodeRuntimeManifestJSON(manifest) else {
                compileLog = "Failed to encode effect manifest."
                return
            }

            let directory = try runtimeEffectsService.saveRuntimeEffectAsset(
                uuid: uuid,
                manifestJSON: json,
                sourceCode: sourceCode
            )
            refreshRuntimeEffectList()
            selectedRuntimeType = runtimeEffectsService.typeName(forUUID: uuid)
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

        do {
            try runtimeEffectsService.deleteRuntimeEffectAsset(uuid: uuid)
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
        guard let url = runtimeEffectsService.chooseCodeSourceFileURL() else { return }

        do {
            sourceCode = try runtimeEffectsService.loadCodeSource(from: url)
            compileLog = "Loaded shader source: \(url.lastPathComponent)"
        } catch {
            compileLog = "Failed to load shader source: \(error.localizedDescription)"
        }
    }
}
