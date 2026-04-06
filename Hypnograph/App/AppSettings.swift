//
//  AppSettings.swift
//  Hypnograph
//

import Foundation

struct AppSettings: Codable {
    var keyboardAccessibilityOverridesEnabled: Bool
    var effectsComposerEnabled: Bool
    var autoHidePanelsEnabled: Bool

    static let defaultValue = AppSettings(
        keyboardAccessibilityOverridesEnabled: true,
        effectsComposerEnabled: true,
        autoHidePanelsEnabled: false
    )

    private enum CodingKeys: String, CodingKey {
        case keyboardAccessibilityOverridesEnabled
        case effectsComposerEnabled
        case autoHidePanelsEnabled
        case autoHideWindowsEnabled
    }

    init(
        keyboardAccessibilityOverridesEnabled: Bool = Self.defaultValue.keyboardAccessibilityOverridesEnabled,
        effectsComposerEnabled: Bool = Self.defaultValue.effectsComposerEnabled,
        autoHidePanelsEnabled: Bool = Self.defaultValue.autoHidePanelsEnabled
    ) {
        self.keyboardAccessibilityOverridesEnabled = keyboardAccessibilityOverridesEnabled
        self.effectsComposerEnabled = effectsComposerEnabled
        self.autoHidePanelsEnabled = autoHidePanelsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyboardAccessibilityOverridesEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .keyboardAccessibilityOverridesEnabled)
            ?? Self.defaultValue.keyboardAccessibilityOverridesEnabled
        effectsComposerEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .effectsComposerEnabled)
            ?? Self.defaultValue.effectsComposerEnabled
        autoHidePanelsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .autoHidePanelsEnabled)
            ?? (try container.decodeIfPresent(Bool.self, forKey: .autoHideWindowsEnabled))
            ?? Self.defaultValue.autoHidePanelsEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyboardAccessibilityOverridesEnabled, forKey: .keyboardAccessibilityOverridesEnabled)
        try container.encode(effectsComposerEnabled, forKey: .effectsComposerEnabled)
        try container.encode(autoHidePanelsEnabled, forKey: .autoHidePanelsEnabled)
    }
}
