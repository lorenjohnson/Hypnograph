//
//  EffectsStudioViewModel+ManifestParameters.swift
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
        let direct = runtimeEffectsDirectoryURL.appendingPathComponent(uuid, isDirectory: true)
        return FileManager.default.fileExists(atPath: direct.path) ? direct : nil
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
        let options = Self.sanitizedChoiceOptions(for: draft)
        guard !options.isEmpty else { return rawValue }

        if let stringValue = rawValue.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let option = options.first(where: { $0.key == stringValue }) {
                return .string(option.key)
            }
            if let option = options.first(where: { $0.key.caseInsensitiveCompare(stringValue) == .orderedSame }) {
                return .string(option.key)
            }
            if let option = options.first(where: { $0.label == stringValue }) {
                return .string(option.key)
            }
            if let option = options.first(where: { $0.label.caseInsensitiveCompare(stringValue) == .orderedSame }) {
                return .string(option.key)
            }
            if let parsedIndex = Int(stringValue), options.indices.contains(parsedIndex) {
                return .string(options[parsedIndex].key)
            }
            return .string(stringValue)
        }

        if let intValue = rawValue.intValue, options.indices.contains(intValue) {
            return .string(options[intValue].key)
        }

        if let doubleValue = rawValue.doubleValue {
            let index = Int(doubleValue.rounded())
            if options.indices.contains(index) {
                return .string(options[index].key)
            }
        }

        return rawValue
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
        var seenKeys = Set<String>()
        var sanitized: [EffectsStudioChoiceOption] = []

        for option in param.choiceOptions {
            let key = option.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)

            let label = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitized.append(
                EffectsStudioChoiceOption(
                    id: option.id,
                    key: key,
                    label: label.isEmpty ? key : label
                )
            )
        }

        return sanitized
    }

    static func resolvedChoiceDefaultKey(
        for param: EffectsStudioParameterDraft,
        options: [EffectsStudioChoiceOption]? = nil
    ) -> String {
        let resolvedOptions = options ?? sanitizedChoiceOptions(for: param)
        let explicit = param.defaultChoiceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedOptions.contains(where: { $0.key == explicit }) {
            return explicit
        }
        return resolvedOptions.first?.key ?? ""
    }

    func runtimeParameterEntry(from param: EffectsStudioParameterDraft) -> RuntimeMetalParameterSchemaEntry? {
        switch param.type {
        case .float:
            return RuntimeMetalParameterSchemaEntry(
                type: "float",
                defaultValue: .double(param.defaultNumber),
                min: param.minNumber,
                max: max(param.maxNumber, param.minNumber + 0.0001),
                options: nil
            )

        case .int:
            return RuntimeMetalParameterSchemaEntry(
                type: "int",
                defaultValue: .int(Int(param.defaultNumber.rounded())),
                min: param.minNumber,
                max: max(param.maxNumber, param.minNumber + 1),
                options: nil
            )

        case .uint:
            return RuntimeMetalParameterSchemaEntry(
                type: "uint",
                defaultValue: .int(max(0, Int(param.defaultNumber.rounded()))),
                min: max(0, param.minNumber),
                max: max(max(0, param.maxNumber), max(0, param.minNumber) + 1),
                options: nil
            )

        case .bool:
            return RuntimeMetalParameterSchemaEntry(
                type: "bool",
                defaultValue: .bool(param.defaultBool),
                min: nil,
                max: nil,
                options: nil
            )

        case .choice:
            let options = Self.sanitizedChoiceOptions(for: param)
            let defaultKey = Self.resolvedChoiceDefaultKey(for: param, options: options)
            return RuntimeMetalParameterSchemaEntry(
                type: "choice",
                defaultValue: .string(defaultKey),
                min: nil,
                max: nil,
                options: options.map { RuntimeMetalChoiceOption(key: $0.key, label: $0.label) }
            )
        }
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
        switch param.type {
        case .float:
            return .double(param.defaultNumber)
        case .int:
            return .int(Int(param.defaultNumber.rounded()))
        case .uint:
            return .int(max(0, Int(param.defaultNumber.rounded())))
        case .bool:
            return .bool(param.defaultBool)
        case .choice:
            return .string(resolvedChoiceDefaultKey(for: param))
        }
    }

    static func parameterSpec(for param: EffectsStudioParameterDraft) -> ParameterSpec {
        switch param.type {
        case .float:
            let minV = Float(param.minNumber)
            let maxV = Float(max(param.maxNumber, param.minNumber + 0.0001))
            let def = Float(param.defaultNumber)
            return .float(default: def, range: minV...maxV)

        case .int:
            let minV = Int(param.minNumber.rounded())
            let maxV = Int(max(param.maxNumber, param.minNumber + 1).rounded())
            let def = Int(param.defaultNumber.rounded())
            return .int(default: def, range: minV...maxV)

        case .uint:
            let minV = max(0, Int(param.minNumber.rounded()))
            let maxV = max(minV + 1, Int(max(param.maxNumber, param.minNumber + 1).rounded()))
            let def = max(0, Int(param.defaultNumber.rounded()))
            return .int(default: def, range: minV...maxV)

        case .bool:
            return .bool(default: param.defaultBool)

        case .choice:
            let options = sanitizedChoiceOptions(for: param)
            let normalized = options.map { (key: $0.key, label: $0.label) }
            let defaultKey = resolvedChoiceDefaultKey(for: param, options: options)
            return .choice(default: defaultKey, options: normalized)
        }
    }

    static func parameterDrafts(from manifest: RuntimeMetalEffectManifest) -> [EffectsStudioParameterDraft] {
        let autoBoundSet = Set(manifest.autoBoundParameters ?? [])
        let order = manifest.parameterOrder ?? manifest.parameters.keys.sorted()

        var result: [EffectsStudioParameterDraft] = []
        for name in order {
            guard let entry = manifest.parameters[name] else { continue }
            guard let type = paramType(from: entry.type) else { continue }

            let autoBind: EffectsStudioAutoBind = autoBoundSet.contains(name) ? EffectsStudioAutoBind.infer(from: name) : .none
            switch type {
            case .bool:
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .bool,
                        defaultNumber: 0,
                        minNumber: 0,
                        maxNumber: 1,
                        defaultBool: entry.defaultValue.boolValue ?? false,
                        autoBind: autoBind
                    )
                )

            case .float:
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .float,
                        defaultNumber: entry.defaultValue.doubleValue ?? 0,
                        minNumber: entry.min ?? 0,
                        maxNumber: entry.max ?? 1,
                        defaultBool: false,
                        autoBind: autoBind
                    )
                )

            case .int:
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .int,
                        defaultNumber: Double(entry.defaultValue.intValue ?? 0),
                        minNumber: entry.min ?? 0,
                        maxNumber: entry.max ?? 1,
                        defaultBool: false,
                        autoBind: autoBind
                    )
                )

            case .uint:
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .uint,
                        defaultNumber: Double(max(0, entry.defaultValue.intValue ?? 0)),
                        minNumber: max(0, entry.min ?? 0),
                        maxNumber: max(1, entry.max ?? 1),
                        defaultBool: false,
                        autoBind: autoBind
                    )
                )

            case .choice:
                let options = (entry.options ?? []).map {
                    EffectsStudioChoiceOption(key: $0.key, label: $0.label)
                }
                let defaultKey = entry.defaultValue.stringValue
                    ?? options.first?.key
                    ?? ""
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .choice,
                        defaultNumber: 0,
                        minNumber: 0,
                        maxNumber: 1,
                        defaultBool: false,
                        defaultChoiceKey: defaultKey,
                        choiceOptions: options,
                        autoBind: autoBind
                    )
                )
            }
        }

        return result
    }

    static func paramType(from raw: String) -> EffectsStudioParamType? {
        switch raw.lowercased() {
        case "float", "double":
            return .float
        case "int":
            return .int
        case "uint":
            return .uint
        case "bool":
            return .bool
        case "choice":
            return .choice
        default:
            return nil
        }
    }

    static func scalarType(for dataType: MTLDataType) -> EffectsStudioScalarValueType? {
        switch dataType {
        case .float:
            return .float
        case .int:
            return .int
        case .uint:
            return .uint
        case .bool:
            return .bool
        default:
            return nil
        }
    }

    static func scalarSize(for type: EffectsStudioScalarValueType) -> Int? {
        switch type {
        case .float, .int, .uint:
            return 4
        case .bool:
            return 1
        }
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        let pattern = "^[A-Za-z_][A-Za-z0-9_]*$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    static func effectUUID(fromTypeName typeName: String) -> String? {
        RuntimeMetalEffectLibrary.uuid(fromTypeName: typeName)
    }

    static func isSystemParameterName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return systemParameterBlueprints.contains { $0.name == trimmed }
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

    static let defaultParameters: [EffectsStudioParameterDraft] = [
        EffectsStudioParameterDraft(
            name: "offsetAmount",
            type: .float,
            defaultNumber: 10,
            minNumber: 0,
            maxNumber: 500,
            defaultBool: false,
            autoBind: .none
        ),
        EffectsStudioParameterDraft(
            name: "animated",
            type: .bool,
            defaultNumber: 0,
            minNumber: 0,
            maxNumber: 1,
            defaultBool: true,
            autoBind: .none
        ),
    ] + systemParameterBlueprints

    static let systemParameterBlueprints: [EffectsStudioParameterDraft] = [
        EffectsStudioParameterDraft(
            name: "timeSeconds",
            type: .float,
            defaultNumber: 0,
            minNumber: 0,
            maxNumber: 100000,
            defaultBool: false,
            autoBind: .timeSeconds
        ),
        EffectsStudioParameterDraft(
            name: "textureWidth",
            type: .int,
            defaultNumber: 1920,
            minNumber: 1,
            maxNumber: 8192,
            defaultBool: false,
            autoBind: .textureWidth
        ),
        EffectsStudioParameterDraft(
            name: "textureHeight",
            type: .int,
            defaultNumber: 1080,
            minNumber: 1,
            maxNumber: 8192,
            defaultBool: false,
            autoBind: .textureHeight
        )
    ]

    static let defaultCodeBody: String = """
    #include <metal_stdlib>
    using namespace metal;

    inline float animatedPhase(float t) {
        float slow = sin(t * 0.7);
        float medium = sin(t * 2.3 + 1.5) * 0.4;
        float fast = sin(t * 7.1 + 3.0) * 0.15;
        float erratic = sin(t * 13.7 + t * 0.3) * 0.1;
        float combined = slow + medium + fast + erratic;
        return (combined + 1.0) * 0.45 + 0.1;
    }

    kernel void render(
        texture2d<float, access::sample> inputTexture [[texture(0)]],
        texture2d<float, access::write> outputTexture [[texture(1)]],
        constant HypnoParams& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= uint(params.textureWidth) || gid.y >= uint(params.textureHeight)) {
            return;
        }

        constexpr sampler samplerLinear(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

        float2 texSize = float2(params.textureWidth, params.textureHeight);
        float2 uv = (float2(gid) + 0.5) / texSize;

        float offsetPixels = params.offsetAmount;
        if (params.animated != 0) {
            offsetPixels *= animatedPhase(params.timeSeconds);
        }
        float offsetUV = offsetPixels / max(texSize.x, 1.0);

        float4 center = inputTexture.sample(samplerLinear, uv);
        float4 redShifted = inputTexture.sample(samplerLinear, uv + float2(offsetUV, 0.0));
        float4 blueShifted = inputTexture.sample(samplerLinear, uv - float2(offsetUV, 0.0));

        float3 rgb = float3(redShifted.r, center.g, blueShifted.b);
        outputTexture.write(float4(clamp(rgb, 0.0, 1.0), center.a), gid);
    }
    """
}
