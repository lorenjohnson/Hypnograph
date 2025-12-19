//
//  EffectConfigSchema.swift
//  Hypnograph
//
//  Codable schema for loading effects from JSON configuration.
//

import Foundation

/// Root configuration containing all available effects
struct EffectConfig: Codable {
    let version: Int
    let effects: [EffectDefinition]
}

/// Definition of a single effect or chained effect
struct EffectDefinition: Codable {
    /// Display name for the effect
    let name: String
    
    /// Hook type (e.g., "BlackAndWhiteHook", "ChainedHook")
    let type: String
    
    /// Parameters for this hook (varies by type)
    let params: [String: AnyCodableValue]?
    
    /// For ChainedHook: the child hooks to apply in sequence
    let hooks: [EffectDefinition]?
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

