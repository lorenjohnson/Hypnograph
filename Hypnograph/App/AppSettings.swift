//
//  AppSettings.swift
//  Hypnograph
//

import Foundation

struct AppSettings: Codable {
    var keyboardAccessibilityOverridesEnabled: Bool
    var effectsComposerEnabled: Bool

    static let defaultValue = AppSettings(
        keyboardAccessibilityOverridesEnabled: true,
        effectsComposerEnabled: true
    )

    private enum CodingKeys: String, CodingKey {
        case keyboardAccessibilityOverridesEnabled
        case effectsComposerEnabled
    }

    init(
        keyboardAccessibilityOverridesEnabled: Bool = Self.defaultValue.keyboardAccessibilityOverridesEnabled,
        effectsComposerEnabled: Bool = Self.defaultValue.effectsComposerEnabled
    ) {
        self.keyboardAccessibilityOverridesEnabled = keyboardAccessibilityOverridesEnabled
        self.effectsComposerEnabled = effectsComposerEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyboardAccessibilityOverridesEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .keyboardAccessibilityOverridesEnabled)
            ?? Self.defaultValue.keyboardAccessibilityOverridesEnabled
        effectsComposerEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .effectsComposerEnabled)
            ?? Self.defaultValue.effectsComposerEnabled
    }
}
