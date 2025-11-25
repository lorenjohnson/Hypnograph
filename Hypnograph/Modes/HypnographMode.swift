//
//  HypnographMode.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//

import Foundation
import CoreGraphics
import SwiftUI

/// Available mode types for the application
enum ModeType: String, Codable {
    case montage
    case sequence
    case divine
}

/// Represents a mode-specific command with keyboard shortcut
struct ModeCommand {
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

/// High-level contract for a Hypnograph "mode"
///
/// The app defines global commands (Save, Reload, etc.)
/// and delegates their meaning to the current mode.
///
/// Most methods have sensible defaults implemented in the extension
/// that simply wire through to `state`. Concrete modes can override
/// anything they need to specialize.
protocol HypnographMode: AnyObject {
    /// Shared session state backing this mode.
    var state: HypnographState { get }

    /// The render queue managed by this mode (shared across modes).
    /// The app may observe it for HUD, quitting, etc.
    var renderQueue: RenderQueue { get }

    /// Short text to display when solo is active (e.g., "SOLO 1").
    var soloIndicatorText: String? { get }

    // MARK: - Display

    /// Root preview/display view for this mode.
    /// ContentView doesn't know which concrete view it is.
    func makeDisplayView(
        state: HypnographState,
        renderQueue: RenderQueue
    ) -> AnyView

    /// Mode-specific HUD items.
    /// Returns an array of HUDItems that will be merged with global items.
    func hudItems(
        state: HypnographState,
        renderQueue: RenderQueue
    ) -> [HUDItem]

    /// Mode-specific Composition commands for the "Composition" menu.
    func compositionCommands() -> [ModeCommand]

    /// Mode-specific Source commands for the "Current Source" menu.
    func sourceCommands() -> [ModeCommand]

    // MARK: - Hypnogram lifecycle

    /// Create a new random setup for this mode.
    func new()

    /// Save / render the current hypnogram using the mode's own renderer + queue.
    func save()

    // MARK: - Source navigation

    /// Add a new source/slot and jump to it (if supported by the mode).
    func addSource()

    func nextSource()
    func previousSource()
    func selectSource(index: Int)

    // MARK: - Clip / selection

    /// Replace the current source’s clip with a new random clip.
    func newRandomClip()

    /// Delete the current source.
    func deleteCurrentSource()

    // MARK: - Mode-specific tweaks

    func toggleHUD()
    func toggleSolo()
    func reloadSettings()

    // MARK: - Effects

    func cycleGlobalEffect()
    func cycleSourceEffect()
    func clearAllEffects()

    var globalEffectName: String { get }
    var sourceEffectName: String { get }
}

// MARK: - Default behavior backed by HypnographState

extension HypnographMode {
    var soloIndicatorText: String? {
        if let solo = state.soloSourceIndex {
            return "SOLO \(solo + 1)"
        } else if !state.sources.isEmpty {
            return "\(state.currentSourceIndex + 1)"
        } else {
            return nil
        }
    }

    // MARK: - Lifecycle

    func new() {
        state.resetForNextHypnogram()
        state.newRandomHypnogram()
    }

    // NOTE: no default `save()` here – each mode must provide its own save()
    // so it can choose an appropriate renderer.

    // MARK: - Source navigation

    func addSource() {
        _ = state.addSource()
    }

    func nextSource() {
        state.nextSource()
    }

    func previousSource() {
        state.previousSource()
    }

    func selectSource(index: Int) {
        state.selectSource(index)
    }

    // MARK: - Clip / selection

    func newRandomClip() {
        state.replaceClipForCurrentSource()
    }

    func deleteCurrentSource() {
        state.deleteCurrentSource()
    }

    // MARK: - Mode-specific tweaks

    func toggleWatchMode() {
        state.toggleWatchMode()
    }

    func toggleHUD() {
        state.toggleHUD()
    }

    func toggleSolo() {
        state.soloSource(index: state.currentSourceIndex)
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
    }

    // MARK: - Effects

    func cycleGlobalEffect() {
        state.renderHooks.cycleGlobalEffect()
    }

    func cycleSourceEffect() {
        state.renderHooks.cycleSourceEffect(for: state.currentSourceIndex)
    }

    func clearAllEffects() {
        state.renderHooks.setGlobalEffect(nil)
        for i in 0..<state.activeSourceCount {
            state.renderHooks.setSourceEffect(nil, for: i)
        }
    }

    var globalEffectName: String {
        state.renderHooks.globalEffectName
    }

    var sourceEffectName: String {
        state.renderHooks.sourceEffectName(for: state.currentSourceIndex)
    }

    // MARK: - Default HUD / commands

    func hudItems(
        state: HypnographState,
        renderQueue: RenderQueue
    ) -> [HUDItem] {
        []
    }

    func compositionCommands() -> [ModeCommand] {
        []
    }

    func sourceCommands() -> [ModeCommand] {
        []
    }
}
