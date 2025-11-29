//
//  ModuleTypes.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//

import Foundation
import SwiftUI

/// Available module types for the application
enum ModuleType: String, Codable {
    case dream
    case divine
}

/// Represents a module-specific command with keyboard shortcut
struct ModuleCommand {
    let title: String
    let keyEquivalent: KeyEquivalent
    let modifiers: EventModifiers
    let action: () -> Void

    init(
        title: String,
        key: KeyEquivalent,
        modifiers: EventModifiers = [],
        action: @escaping () -> Void
    ) {
        self.title = title
        self.keyEquivalent = key
        self.modifiers = modifiers
        self.action = action
    }
}

