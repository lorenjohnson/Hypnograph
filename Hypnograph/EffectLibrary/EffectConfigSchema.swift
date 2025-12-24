//
//  EffectConfigSchema.swift
//  Hypnograph
//
//  Codable schema for effects. Two main types:
//  - EffectChain: A named container for 0-n hooks (stored in recipe, per layer)
//  - HookDefinition: A single effect with type + params
//

import Foundation

// MARK: - Core Types

/// An effect chain containing 0-n hooks applied in sequence.
/// This is the top-level effect container stored on recipes (global or per-source).
struct EffectChain: Codable, Equatable {
    /// Display name for the chain
    var name: String?

    /// The hooks to apply in sequence (0-n)
    var hooks: [HookDefinition]

    /// Future: chain-level parameters (e.g., overall strength/mix)
    var params: [String: AnyCodableValue]?

    /// Create an empty chain
    init() {
        self.name = nil
        self.hooks = []
        self.params = nil
    }

    /// Create a named chain with hooks
    init(name: String?, hooks: [HookDefinition], params: [String: AnyCodableValue]? = nil) {
        self.name = name
        self.hooks = hooks
        self.params = params
    }

    /// Whether this chain has any hooks
    var isEmpty: Bool { hooks.isEmpty }

    /// Whether this chain has any enabled hooks
    var hasEnabledHooks: Bool {
        hooks.contains { $0.isEnabled }
    }

    /// For single-hook chains, returns the hook type. For multi-hook chains, returns nil.
    /// Used for backward compatibility with code that expects a single effect type.
    var resolvedType: String? {
        hooks.count == 1 ? hooks.first?.type : nil
    }

    /// Whether this is a chained effect (has multiple hooks or is explicitly a chain)
    /// For backward compatibility - all EffectChains are conceptually "chained"
    var isChained: Bool {
        true  // All chains are chained by definition
    }
}

/// Definition of a single hook (effect) within a chain.
struct HookDefinition: Codable, Equatable {
    /// Optional display name for this hook
    var name: String?

    /// The hook type (e.g., "DatamoshMetalHook", "GlitchBlocksMetalHook")
    var type: String

    /// Parameters for this hook
    var params: [String: AnyCodableValue]?

    /// Create a hook with type and optional params
    init(type: String, params: [String: AnyCodableValue]? = nil) {
        self.name = nil
        self.type = type
        self.params = params
    }

    /// Create a hook with name, type, and optional params
    init(name: String?, type: String, params: [String: AnyCodableValue]? = nil) {
        self.name = name
        self.type = type
        self.params = params
    }

    /// Whether this hook is enabled (checks _enabled param, defaults to true)
    var isEnabled: Bool {
        params?["_enabled"]?.boolValue ?? true
    }

    /// The resolved type - for HookDefinition this is always the type
    var resolvedType: String {
        type
    }

    /// Create a copy with updated params
    func with(params: [String: AnyCodableValue]?) -> HookDefinition {
        HookDefinition(name: name, type: type, params: params)
    }
}

// MARK: - Library Config (effects.json)

/// Root configuration for the effects library JSON file
struct EffectLibraryConfig: Codable {
    let version: Int
    let effects: [EffectChain]
}

// MARK: - Deprecated Aliases (for transition)

/// @deprecated Use EffectChain instead
typealias EffectDefinition = EffectChain

/// @deprecated Use EffectLibraryConfig instead
typealias EffectConfig = EffectLibraryConfig

// MARK: - EffectChain JSON Compatibility

extension EffectChain {
    /// Coding keys for JSON compatibility with old format
    enum CodingKeys: String, CodingKey {
        case name
        case hooks
        case params
        // Legacy keys for reading old format
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decodeIfPresent(String.self, forKey: .name)
        params = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .params)

        // Try to decode hooks array first (new format)
        if let hooksArray = try container.decodeIfPresent([HookDefinition].self, forKey: .hooks) {
            hooks = hooksArray
        }
        // Legacy: if no hooks but has type, this is a single-hook chain
        else if let type = try container.decodeIfPresent(String.self, forKey: .type) {
            hooks = [HookDefinition(type: type, params: params)]
            // Clear params since they belong to the hook, not the chain
            self.params = nil
        }
        // Empty chain
        else {
            hooks = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(hooks, forKey: .hooks)
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

