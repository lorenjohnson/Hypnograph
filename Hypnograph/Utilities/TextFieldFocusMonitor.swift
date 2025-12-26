//
//  TextFieldFocusMonitor.swift
//  Hypnograph
//
//  Monitors text field editing state using AppKit notifications.
//  This is the bulletproof solution - works for ALL text fields automatically
//  without requiring per-field wiring.
//
//  Use: Disable single-key shortcuts when isEditing == true
//

import Foundation
import AppKit
import Combine

/// Monitors when any text field in the app starts/ends editing.
/// Uses NSText notifications which fire for all TextField/TextEditor controls.
@MainActor
final class TextFieldFocusMonitor: ObservableObject {
    
    /// True when any text field is being edited
    @Published private(set) var isEditing: Bool = false
    
    private var beginObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    
    init() {
        // NSText.didBeginEditingNotification fires when ANY text field starts editing
        beginObserver = NotificationCenter.default.addObserver(
            forName: NSText.didBeginEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isEditing = true
            }
        }
        
        // NSText.didEndEditingNotification fires when editing ends
        endObserver = NotificationCenter.default.addObserver(
            forName: NSText.didEndEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isEditing = false
            }
        }
    }
    
    deinit {
        if let observer = beginObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

