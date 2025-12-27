//
//  WindowState.swift
//  Hypnograph
//
//  Unified window visibility state with clean screen support.
//  Tab toggles clean screen mode, hiding all windows temporarily.
//

import Foundation

/// Protocol for objects that provide access to the shared WindowState
@MainActor
protocol WindowStateProvider: AnyObject {
    var windowState: WindowState { get set }
}

/// Which window/overlay to show or hide
enum Window: CaseIterable {
    // Per-player windows (managed by DreamPlayerState)
    case hud
    case effectsEditor
    case playerSettings

    // App-level windows (managed by HypnographState)
    case hypnogramList
    case performancePreview
}

/// Manages visibility state for all windows/overlays
struct WindowState {

    // MARK: - Window Visibility

    /// Per-player window visibility states
    var hud: Bool = false
    var effectsEditor: Bool = false
    var playerSettings: Bool = false

    /// App-level window visibility states
    var hypnogramList: Bool = false
    var performancePreview: Bool = false

    // MARK: - Clean Screen Mode

    /// When true, all windows are hidden regardless of their individual visibility states
    var isCleanScreen: Bool = false

    // MARK: - Computed Properties

    /// Whether any window is currently visible (ignoring clean screen)
    var hasAnyWindowVisible: Bool {
        hud || effectsEditor || playerSettings || hypnogramList || performancePreview
    }

    /// Check if a specific window should actually be shown right now
    /// (respects clean screen mode)
    func isVisible(_ window: Window) -> Bool {
        if isCleanScreen { return false }
        switch window {
        case .hud: return hud
        case .effectsEditor: return effectsEditor
        case .playerSettings: return playerSettings
        case .hypnogramList: return hypnogramList
        case .performancePreview: return performancePreview
        }
    }

    // MARK: - Toggle Actions

    /// Toggle a specific window. If in clean screen mode, exits clean screen first
    /// and consumes the keypress (doesn't toggle the window).
    /// - Returns: true if the toggle was consumed by exiting clean screen
    @discardableResult
    mutating func toggle(_ window: Window) -> Bool {
        // If in clean screen, exit and consume the keypress
        if isCleanScreen {
            isCleanScreen = false
            return true  // Consumed
        }

        // Normal toggle
        switch window {
        case .hud:
            hud.toggle()
        case .effectsEditor:
            effectsEditor.toggle()
        case .playerSettings:
            playerSettings.toggle()
        case .hypnogramList:
            hypnogramList.toggle()
        case .performancePreview:
            performancePreview.toggle()
        }
        return false  // Not consumed
    }

    /// Toggle clean screen mode
    /// - Does nothing if no windows are visible (can't enter clean screen with nothing to hide)
    mutating func toggleCleanScreen() {
        if isCleanScreen {
            // Exit clean screen
            isCleanScreen = false
        } else {
            // Enter clean screen only if something is visible
            if hasAnyWindowVisible {
                isCleanScreen = true
            }
        }
    }

    /// Set a specific window's visibility directly (used for menu commands)
    /// Exits clean screen mode if setting a window to visible
    mutating func set(_ window: Window, visible: Bool) {
        if visible && isCleanScreen {
            isCleanScreen = false
        }

        switch window {
        case .hud:
            hud = visible
        case .effectsEditor:
            effectsEditor = visible
        case .playerSettings:
            playerSettings = visible
        case .hypnogramList:
            hypnogramList = visible
        case .performancePreview:
            performancePreview = visible
        }
    }
}

