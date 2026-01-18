//
//  LiveWindow.swift
//  Hypnograph
//
//  Custom NSWindow for the live display.
//  Borderless, fullscreen-capable, designed for external monitor output.
//

import AppKit

/// Borderless window for clean live output
/// Does not steal focus from the main window
final class LiveWindow: NSWindow {

    // Don't steal keyboard focus from main window
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configureForLive() {
        // Hide title bar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Black background
        backgroundColor = .black
    }
}
