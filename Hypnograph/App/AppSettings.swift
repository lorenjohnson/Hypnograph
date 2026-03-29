//
//  AppSettings.swift
//  Hypnograph
//

import Foundation

struct AppSettings: Codable {
    var keyboardAccessibilityOverridesEnabled: Bool
    var effectsComposerEnabled: Bool
    var autoHideWindowsEnabled: Bool

    static let defaultValue = AppSettings(
        keyboardAccessibilityOverridesEnabled: true,
        effectsComposerEnabled: true,
        autoHideWindowsEnabled: false
    )

    private enum CodingKeys: String, CodingKey {
        case keyboardAccessibilityOverridesEnabled
        case effectsComposerEnabled
        case autoHideWindowsEnabled
    }

    init(
        keyboardAccessibilityOverridesEnabled: Bool = Self.defaultValue.keyboardAccessibilityOverridesEnabled,
        effectsComposerEnabled: Bool = Self.defaultValue.effectsComposerEnabled,
        autoHideWindowsEnabled: Bool = Self.defaultValue.autoHideWindowsEnabled
    ) {
        self.keyboardAccessibilityOverridesEnabled = keyboardAccessibilityOverridesEnabled
        self.effectsComposerEnabled = effectsComposerEnabled
        self.autoHideWindowsEnabled = autoHideWindowsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyboardAccessibilityOverridesEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .keyboardAccessibilityOverridesEnabled)
            ?? Self.defaultValue.keyboardAccessibilityOverridesEnabled
        effectsComposerEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .effectsComposerEnabled)
            ?? Self.defaultValue.effectsComposerEnabled
        autoHideWindowsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .autoHideWindowsEnabled)
            ?? Self.defaultValue.autoHideWindowsEnabled
    }
}
