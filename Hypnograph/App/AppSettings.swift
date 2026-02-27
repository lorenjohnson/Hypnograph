//
//  AppSettings.swift
//  Hypnograph
//

import Foundation

struct AppSettings: Codable {
    var keyboardAccessibilityOverridesEnabled: Bool

    static let defaultValue = AppSettings(
        keyboardAccessibilityOverridesEnabled: true
    )

    private enum CodingKeys: String, CodingKey {
        case keyboardAccessibilityOverridesEnabled
    }

    init(keyboardAccessibilityOverridesEnabled: Bool = Self.defaultValue.keyboardAccessibilityOverridesEnabled) {
        self.keyboardAccessibilityOverridesEnabled = keyboardAccessibilityOverridesEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyboardAccessibilityOverridesEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .keyboardAccessibilityOverridesEnabled)
            ?? Self.defaultValue.keyboardAccessibilityOverridesEnabled
    }
}
