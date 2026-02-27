//
//  ManifestParameterState.swift
//  Hypnograph
//

import Foundation
import Metal
import HypnoCore

extension EffectsStudioViewModel {
    func normalizedEffectUUID() -> String {
        runtimeEffectUUID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func normalizedEffectName() -> String {
        let name = runtimeEffectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled Effect" : name
    }

    func normalizedEffectVersion() -> String {
        let version = runtimeEffectVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? "1.0.0" : version
    }

    func runtimeEffectDirectoryURL(forUUID uuid: String) -> URL? {
        runtimeEffectsService.runtimeEffectDirectoryURL(forUUID: uuid)
    }

    func appendLogEntry(from message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if logEntries.last == trimmed { return }
        logEntries.append(trimmed)
    }

    func nextParameterName(base: String) -> String {
        let existing = Set(parameters.map { $0.name })
        if !existing.contains(base) {
            return base
        }
        var index = 1
        while existing.contains("\(base)\(index)") {
            index += 1
        }
        return "\(base)\(index)"
    }

    func canonicalChoiceValue(
        for draft: EffectsStudioParameterDraft,
        rawValue: AnyCodableValue
    ) -> AnyCodableValue {
        EffectsStudioParameterModeling.canonicalChoiceValue(for: draft, rawValue: rawValue)
    }

    func runtimeManifestFromCurrentState() -> RuntimeMetalEffectManifest {
        var parameterEntries: [String: RuntimeMetalParameterSchemaEntry] = [:]
        var order: [String] = []
        var autoBound: [String] = []

        for param in parameters {
            let name = param.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard let entry = runtimeParameterEntry(from: param) else { continue }
            parameterEntries[name] = entry
            order.append(name)
            if param.isAutoBound {
                autoBound.append(name)
            }
        }

        return RuntimeMetalEffectManifest(
            uuid: normalizedEffectUUID(),
            name: normalizedEffectName(),
            version: normalizedEffectVersion(),
            runtimeKind: activeRuntimeKind,
            requiredLookback: activeRequiredLookback,
            usesPersistentState: activeUsesPersistentState,
            parameters: parameterEntries,
            parameterOrder: order,
            autoBoundParameters: autoBound,
            bindings: activeBindings
        )
    }

    static func sanitizedChoiceOptions(for param: EffectsStudioParameterDraft) -> [EffectsStudioChoiceOption] {
        EffectsStudioParameterModeling.sanitizedChoiceOptions(for: param)
    }

    static func resolvedChoiceDefaultKey(
        for param: EffectsStudioParameterDraft,
        options: [EffectsStudioChoiceOption]? = nil
    ) -> String {
        EffectsStudioParameterModeling.resolvedChoiceDefaultKey(for: param, options: options)
    }

    func runtimeParameterEntry(from param: EffectsStudioParameterDraft) -> RuntimeMetalParameterSchemaEntry? {
        EffectsStudioParameterModeling.runtimeParameterEntry(from: param)
    }

    func encodeRuntimeManifestJSON(_ manifest: RuntimeMetalEffectManifest) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func rebuildParameterValues(preserveExisting: Bool) {
        let existing = parameterValues
        var rebuilt: [String: AnyCodableValue] = [:]

        for param in parameters {
            let name = param.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if preserveExisting, let old = existing[name] {
                rebuilt[name] = old
            } else {
                rebuilt[name] = Self.defaultValue(for: param)
            }
        }

        parameterValues = rebuilt
    }

    static func defaultValue(for param: EffectsStudioParameterDraft) -> AnyCodableValue {
        EffectsStudioParameterModeling.defaultValue(for: param)
    }

    static func parameterSpec(for param: EffectsStudioParameterDraft) -> ParameterSpec {
        EffectsStudioParameterModeling.parameterSpec(for: param)
    }

    static func parameterDrafts(from manifest: RuntimeMetalEffectManifest) -> [EffectsStudioParameterDraft] {
        EffectsStudioParameterModeling.parameterDrafts(from: manifest)
    }

    static func paramType(from raw: String) -> EffectsStudioParamType? {
        EffectsStudioParameterModeling.paramType(from: raw)
    }

    static func scalarType(for dataType: MTLDataType) -> EffectsStudioScalarValueType? {
        EffectsStudioParameterModeling.scalarType(for: dataType)
    }

    static func scalarSize(for type: EffectsStudioScalarValueType) -> Int? {
        EffectsStudioParameterModeling.scalarSize(for: type)
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        EffectsStudioParameterModeling.isValidIdentifier(value)
    }

    static func effectUUID(fromTypeName typeName: String) -> String? {
        EffectsStudioParameterModeling.effectUUID(fromTypeName: typeName)
    }

    static func isSystemParameterName(_ name: String) -> Bool {
        EffectsStudioParameterModeling.isSystemParameterName(name)
    }

    func ensureSystemParameters() {
        for blueprint in Self.systemParameterBlueprints {
            let name = blueprint.name
            if let index = parameters.firstIndex(where: { $0.name == name }) {
                var existing = parameters[index]
                var changed = false

                if existing.name != blueprint.name {
                    existing.name = blueprint.name
                    changed = true
                }
                if existing.type != blueprint.type {
                    existing.type = blueprint.type
                    changed = true
                }
                if existing.autoBind != blueprint.autoBind {
                    existing.autoBind = blueprint.autoBind
                    changed = true
                }
                if existing.defaultNumber != blueprint.defaultNumber {
                    existing.defaultNumber = blueprint.defaultNumber
                    changed = true
                }
                if existing.minNumber != blueprint.minNumber {
                    existing.minNumber = blueprint.minNumber
                    changed = true
                }
                if existing.maxNumber != blueprint.maxNumber {
                    existing.maxNumber = blueprint.maxNumber
                    changed = true
                }
                if existing.defaultBool != blueprint.defaultBool {
                    existing.defaultBool = blueprint.defaultBool
                    changed = true
                }

                if changed {
                    parameters[index] = existing
                }
            } else {
                parameters.append(blueprint)
            }
        }
    }

    static var defaultParameters: [EffectsStudioParameterDraft] {
        EffectsStudioParameterModeling.defaultParameters
    }

    static var systemParameterBlueprints: [EffectsStudioParameterDraft] {
        EffectsStudioParameterModeling.systemParameterBlueprints
    }

    static var defaultCodeBody: String {
        EffectsStudioParameterModeling.defaultCodeBody
    }
}
