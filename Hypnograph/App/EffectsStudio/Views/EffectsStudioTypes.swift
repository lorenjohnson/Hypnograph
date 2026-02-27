//
//  EffectsStudioTypes.swift
//  Hypnograph
//

import Foundation

extension Notification.Name {
    static let effectsStudioToggleCleanScreen = Notification.Name("Hypnograph.EffectsStudio.ToggleCleanScreen")
}

enum EffectsStudioParamType: String, CaseIterable, Identifiable {
    case float
    case int
    case uint
    case bool
    case choice

    var id: String { rawValue }

    var metalType: String {
        switch self {
        case .float: return "float"
        case .int: return "int"
        case .uint: return "uint"
        case .bool: return "bool"
        case .choice: return "int"
        }
    }

    var usesNumericRange: Bool {
        switch self {
        case .float, .int, .uint:
            return true
        case .bool, .choice:
            return false
        }
    }
}

enum EffectsStudioAutoBind: String, CaseIterable, Identifiable {
    case none
    case timeSeconds
    case textureWidth
    case textureHeight
    case frameIndex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .timeSeconds: return "Time"
        case .textureWidth: return "Texture Width"
        case .textureHeight: return "Texture Height"
        case .frameIndex: return "Frame Index"
        }
    }

    static func infer(from parameterName: String) -> EffectsStudioAutoBind {
        switch parameterName {
        case "timeSeconds", "time":
            return .timeSeconds
        case "textureWidth", "width":
            return .textureWidth
        case "textureHeight", "height":
            return .textureHeight
        case "frameIndex", "frame", "frame_index":
            return .frameIndex
        default:
            return .none
        }
    }
}

struct EffectsStudioChoiceOption: Identifiable, Equatable {
    var id: UUID = UUID()
    var key: String
    var label: String
}

struct EffectsStudioParameterDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var type: EffectsStudioParamType
    var defaultNumber: Double
    var minNumber: Double
    var maxNumber: Double
    var defaultBool: Bool
    var defaultChoiceKey: String = ""
    var choiceOptions: [EffectsStudioChoiceOption] = []
    var autoBind: EffectsStudioAutoBind

    var isAutoBound: Bool { autoBind != .none }

    static func `default`(named name: String = "param") -> EffectsStudioParameterDraft {
        EffectsStudioParameterDraft(
            name: name,
            type: .float,
            defaultNumber: 0,
            minNumber: 0,
            maxNumber: 1,
            defaultBool: false,
            autoBind: .none
        )
    }
}

struct EffectsStudioRuntimeEffectChoice: Identifiable, Hashable {
    var type: String
    var displayName: String
    var id: String { type }
}
