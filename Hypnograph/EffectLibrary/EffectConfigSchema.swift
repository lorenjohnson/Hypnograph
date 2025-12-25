//
//  EffectConfigSchema.swift
//  Hypnograph
//
//  Codable schema for effects. Two main types:
//  - EffectChain: A named container for 0-n effects (stored in recipe, per layer)
//  - EffectDefinition: A single effect with type + params
//

import Foundation

// MARK: - Core Types

/// An effect chain containing 0-n effects applied in sequence.
/// This is the top-level effect container stored on recipes (global or per-source).
struct EffectChain: Codable, Equatable {
    /// Display name for the chain
    var name: String?

    /// The effects to apply in sequence (0-n)
    var effects: [EffectDefinition]

    /// Future: chain-level parameters (e.g., overall strength/mix)
    var params: [String: AnyCodableValue]?

    /// Create an empty chain
    init() {
        self.name = nil
        self.effects = []
        self.params = nil
    }

    /// Create a named chain with effects
    init(name: String?, effects: [EffectDefinition], params: [String: AnyCodableValue]? = nil) {
        self.name = name
        self.effects = effects
        self.params = params
    }

    /// Whether this chain has any effects
    var isEmpty: Bool { effects.isEmpty }

    /// Whether this chain has any enabled effects
    var hasEnabledEffects: Bool {
        effects.contains { $0.isEnabled }
    }
}

/// Definition of a single effect within a chain.
struct EffectDefinition: Codable, Equatable {
    /// Optional display name for this effect
    var name: String?

    /// The effect type (e.g., "DatamoshEffect", "GlitchBlocksEffect")
    var type: String

    /// Parameters for this effect
    var params: [String: AnyCodableValue]?

    /// Create an effect with type and optional params
    init(type: String, params: [String: AnyCodableValue]? = nil) {
        self.name = nil
        self.type = type
        self.params = params
    }

    /// Create an effect with name, type, and optional params
    init(name: String?, type: String, params: [String: AnyCodableValue]? = nil) {
        self.name = name
        self.type = type
        self.params = params
    }

    /// Whether this effect is enabled (checks _enabled param, defaults to true)
    var isEnabled: Bool {
        params?["_enabled"]?.boolValue ?? true
    }

    /// Create a copy with updated params
    func with(params: [String: AnyCodableValue]?) -> EffectDefinition {
        EffectDefinition(name: name, type: type, params: params)
    }
}

// MARK: - Library Config (effects.json)

/// Root configuration for the effects library JSON file
struct EffectLibraryConfig: Codable {
    let version: Int
    let effects: [EffectChain]
}

// MARK: - Deprecated Aliases (for transition)



// MARK: - EffectChain JSON Compatibility

extension EffectChain {
    /// Coding keys for JSON
    enum CodingKeys: String, CodingKey {
        case name
        case effects
        case params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decodeIfPresent(String.self, forKey: .name)
        params = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .params)
        effects = try container.decodeIfPresent([EffectDefinition].self, forKey: .effects) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(effects, forKey: .effects)
        try container.encodeIfPresent(params, forKey: .params)
    }
}

/// Type-erased codable value to handle mixed parameter types
enum AnyCodableValue: Codable, Equatable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try each type in order of specificity
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported value type"
                )
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
    
    // Convenience accessors
    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        default: return nil
        }
    }
    
    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
    
    var floatValue: Float? {
        doubleValue.map { Float($0) }
    }
    
    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
    
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}

