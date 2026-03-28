//
//  EffectsComposerTypes.swift
//  Hypnograph
//

import Foundation

extension Notification.Name {
    static let effectsComposerToggleCleanScreen = Notification.Name("Hypnograph.EffectsComposer.ToggleCleanScreen")
}

enum EffectsComposerParamType: String, CaseIterable, Identifiable {
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

enum EffectsComposerAutoBind: String, CaseIterable, Identifiable {
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

    static func infer(from parameterName: String) -> EffectsComposerAutoBind {
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

struct EffectsComposerChoiceOption: Identifiable, Equatable {
    var id: UUID = UUID()
    var key: String
    var label: String
}

struct EffectsComposerParameterDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var type: EffectsComposerParamType
    var defaultNumber: Double
    var minNumber: Double
    var maxNumber: Double
    var defaultBool: Bool
    var defaultChoiceKey: String = ""
    var choiceOptions: [EffectsComposerChoiceOption] = []
    var autoBind: EffectsComposerAutoBind

    var isAutoBound: Bool { autoBind != .none }

    static func `default`(named name: String = "param") -> EffectsComposerParameterDraft {
        EffectsComposerParameterDraft(
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

struct EffectsComposerRuntimeEffectChoice: Identifiable, Hashable {
    var type: String
    var displayName: String
    var id: String { type }
}
