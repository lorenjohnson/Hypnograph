//
//  FocusedValues.swift
//  Hypnograph
//
//  Exposes text field focus state to Commands without global state.
//  Uses SwiftUI's FocusedValues mechanism for proper responder chain handling.
//

import SwiftUI

/// Key for exposing whether a text field is currently being edited
struct IsTypingKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    /// Whether a text field is currently focused and accepting keyboard input.
    /// Commands should check this to disable single-key shortcuts while typing.
    var isTyping: Bool? {
        get { self[IsTypingKey.self] }
        set { self[IsTypingKey.self] = newValue }
    }
}

