//
//  AppSettings.swift
//  Hypnograph
//

import Foundation

struct AppSettings: Codable {
    var keyboardAccessibilityOverridesEnabled: Bool
    var effectsStudioEnabled: Bool

    static let defaultValue = AppSettings(
        keyboardAccessibilityOverridesEnabled: true,
        effectsStudioEnabled: true
    )

    private enum CodingKeys: String, CodingKey {
        case keyboardAccessibilityOverridesEnabled
        case effectsStudioEnabled
    }

    init(
        keyboardAccessibilityOverridesEnabled: Bool = Self.defaultValue.keyboardAccessibilityOverridesEnabled,
        effectsStudioEnabled: Bool = Self.defaultValue.effectsStudioEnabled
    ) {
        self.keyboardAccessibilityOverridesEnabled = keyboardAccessibilityOverridesEnabled
        self.effectsStudioEnabled = effectsStudioEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyboardAccessibilityOverridesEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .keyboardAccessibilityOverridesEnabled)
            ?? Self.defaultValue.keyboardAccessibilityOverridesEnabled
        effectsStudioEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .effectsStudioEnabled)
            ?? Self.defaultValue.effectsStudioEnabled
    }
}
