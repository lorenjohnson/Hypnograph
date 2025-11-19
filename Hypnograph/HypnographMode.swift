//
//  HypnographMode.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//

import Foundation
import CoreGraphics
import SwiftUI

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
    func reloadSettings()
}
