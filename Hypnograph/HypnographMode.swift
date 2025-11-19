//
//  HypnographMode.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//


import Foundation
import CoreGraphics

/// High-level contract for a Hypnograph "mode"
/// (e.g. Montage, Sequence, ...).
///
/// The app defines global commands (Save, Reload, etc.)
/// and delegates their meaning to the current mode.
protocol HypnographMode: AnyObject {
    /// The mode's preferred output size (used for window sizing).
    var outputSize: CGSize { get }

    // MARK: - Hypnogram lifecycle

    /// Create a new random setup for this mode.
    func newRandomHypnogram()

    /// Save / render the current hypnogram using the given render queue.
    func saveCurrentHypnogram(using queue: RenderQueue)

    // MARK: - Source navigation

    /// Move to the "next source" in this mode.
    /// In MontageMode this maps to next layer.
    func nextSource()

    /// Move to the "previous source" in this mode.
    /// In MontageMode this maps to previous layer.
    func previousSource()

    /// Select a specific source index.
    /// In MontageMode this maps to selectLayer(index:).
    func selectSource(index: Int)

    // MARK: - Candidate / selection

    /// Get a new candidate source for the current position.
    func nextCandidate()

    /// Accept the current candidate at this position.
    func acceptCandidate()

    /// Delete / back out of the current position.
    func deleteCurrentSource()

    // MARK: - Mode-specific tweaks

    /// Cycle the current effect (blend mode, etc.).
    func cycleEffect()

    /// Toggle HUD / overlay UI for this mode.
    func toggleHUD()

    /// Reload mode settings from disk.
    func reloadSettings()
}
