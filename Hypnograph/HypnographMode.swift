//
//  HypnographMode.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//

import Foundation
import CoreGraphics
import SwiftUI

/// Represents a mode-specific command with keyboard shortcut
struct ModeCommand {
    let title: String
    let keyEquivalent: KeyEquivalent
    let modifiers: EventModifiers
    let action: () -> Void

    init(title: String, key: KeyEquivalent, modifiers: EventModifiers = [], action: @escaping () -> Void) {
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
protocol HypnographMode: AnyObject {
    /// The render queue managed by this mode.
    /// (The app may observe it for HUD, quitting, etc.)
    var renderQueue: RenderQueue { get }

    /// Root preview/display view for this mode.
    /// ContentView doesn't know which concrete view it is.
    func makeDisplayView(
        state: HypnogramState,
        renderQueue: RenderQueue
    ) -> AnyView

    /// Mode-specific HUD items.
    /// Returns an array of HUDItems that will be merged with global items.
    /// Use ordering indices to position items (e.g., 15, 25, 35 to fit between global items at 10, 20, 30, 40).
    func hudItems(
        state: HypnogramState,
        renderQueue: RenderQueue
    ) -> [HUDItem]

    /// Mode-specific commands for the menu.
    /// Returns an array of ModeCommands that will be added to the "Current" menu.
    func modeCommands() -> [ModeCommand]

    // MARK: - Hypnogram lifecycle

    /// Create a new random setup for this mode.
    func newRandomHypnogram()

    /// Save / render the current hypnogram using the mode's queue.
    func saveCurrentHypnogram()

    // MARK: - Source navigation

    func nextSource()
    func previousSource()
    func selectSource(index: Int)

    // MARK: - Candidate / selection

    func nextCandidate()
    func acceptCandidate()
    func deleteCurrentSource()

    // MARK: - Mode-specific tweaks

    func cycleEffect()
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
