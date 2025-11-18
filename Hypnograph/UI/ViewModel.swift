//
//  ViewModel.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import Combine
import AVFoundation
import CoreMedia
import CoreGraphics

/// ViewModel that bridges the SwiftUI layer with the Hypnograph core:
/// - Owns a HypnogramSession (selection logic)
/// - Owns a RenderQueue (render jobs)
/// - Exposes simple intent methods for key commands (N, Return, M, R, Delete).
final class ViewModel: ObservableObject {
    @Published private(set) var currentSession: Session
    @Published var currentCandidateStartOverride: CMTime?
    @Published var isHUDVisible: Bool = false

    let renderQueue: RenderQueue

    private var settings: Settings

    private var autoPrimeTimer: Timer?

    init(settings: Settings, renderQueue: RenderQueue) {
        self.settings = settings
        self.currentSession = Session(settings: settings)
        self.renderQueue = renderQueue

        if settings.autoPrime {
            autoPrimeNow()          // pre-roll a stack as if the user had selected layers
            scheduleAutoPrimeTimer()
        }
    }

    // MARK: - Intents driven by key commands

    /// N: advance to the next random candidate for the current layer.
    func nextCandidate() {
        noteUserInteraction()
        currentCandidateStartOverride = nil
        _ = currentSession.nextCandidateForCurrentLayer()
        objectWillChange.send()
    }

    /// Return: accept the current candidate for this layer, possibly advancing to the next layer.
    func acceptCandidate() {
        noteUserInteraction()
        currentSession.acceptCandidateForCurrentLayer(usingStartTime: currentCandidateStartOverride)
        currentCandidateStartOverride = nil
        objectWillChange.send()
    }

    func randomizeLayer(index: Int, randomizeBlend: Bool = false) {
        noteUserInteraction()
        currentSession.randomizeLayer(index, randomizeBlend: randomizeBlend)
        objectWillChange.send()
    }

    /// M: cycle the blend mode for the current layer.
    func cycleBlendMode() {
        noteUserInteraction()
        currentSession.cycleBlendModeForCurrentLayer()
        objectWillChange.send()
    }

    /// R: if at least one layer has selected clips, enqueue a recipe for rendering
    /// and reset the session for the next hypnogram.
    func renderCurrentHypnogram() {
        noteUserInteraction()

        guard let recipe = currentSession.layersForRender() else {
            print("renderCurrentHypnogram(): no renderable hypnogram (no selected clips).")
            return
        }

        print("renderCurrentHypnogram(): enqueuing recipe with \(recipe.layers.count) layer(s).")
        renderQueue.enqueue(recipe: recipe)

        currentSession.resetForNextHypnogram()

        if settings.autoPrime {
            autoPrimeNow()
        }

        currentCandidateStartOverride = nil
        objectWillChange.send()
    }

    /// Space: generate a completely new auto-primed set.
    func newAutoPrimeSet() {
        noteUserInteraction()
        autoPrimeNow()
    }

    // Reloads settings
    func newSessionReloadingSettings() {
        do {
            let url = Environment.defaultSettingsURL
            let newSettings = try SettingsLoader.load(from: url)
            self.settings = newSettings
            self.currentSession = Session(settings: newSettings)
           print("🔄 Reloaded settings from \(url.path)")
        } catch {
            // If reload fails, keep old settings/session and log.
            print("⚠️ Failed to reload settings; keeping existing settings. Error: \(error)")
        }
    }
    func toggleHUD() {
        isHUDVisible.toggle()
        objectWillChange.send()
    }

    // MARK: - Convenience accessors for the UI

    /// Which layer index is currently being chosen (0-based).
    var currentLayerIndex: Int {
        currentSession.currentLayer
    }

    /// Maximum number of layers in this hypnogram (from settings).
    var maxLayers: Int {
        currentSession.maxLayers
    }

    /// Output size used for preview, following the same rules as the renderer:
    /// - if both outputWidth & outputHeight > 0 → use them exactly
    /// - if only width > 0 → derive height with 16:9 (height = width * 9/16)
    /// - if only height > 0 → derive width with 16:9 (width = height * 16/9)
    /// - if both are 0 → default 1920x1080
    var outputSize: CGSize {
        let cfg = currentSession.settings

        let defaultW: CGFloat = 1920
        let defaultH: CGFloat = 1080
        let aspect: CGFloat = 9.0 / 16.0   // height / width (16:9)

        let w = CGFloat(cfg.outputWidth)
        let h = CGFloat(cfg.outputHeight)

        switch (w > 0, h > 0) {
        case (true, true):
            return CGSize(width: w, height: h)

        case (true, false):
            // width set, derive height (16:9)
            return CGSize(width: w, height: round(w * aspect))

        case (false, true):
            // height set, derive width (16:9)
            return CGSize(width: round(h / aspect), height: h)

        default:
            // neither set → default 1920x1080
            return CGSize(width: defaultW, height: defaultH)
        }
    }

    /// The *literal* blend mode name for the current layer (e.g. "CIMultiplyBlendMode").
    var currentBlendModeName: String {
        currentSession.currentBlendMode.name
    }

    /// Current candidate clip for the active layer, if any.
    var currentCandidateClip: VideoClip? {
        let idx = currentSession.currentLayer
        guard idx >= 0 && idx < currentSession.candidateClips.count else { return nil }
        return currentSession.candidateClips[idx]
    }

    /// Layers (with clips + modes) to render in the live preview.
    var layersForPreview: [HypnogramLayer] {
        currentSession.layersForPreview()
    }

    /// Delete: step back a layer if possible; on the first layer, this is your
    /// "quit after renders finish" hook if you want it.
    func handleEscape() {
        noteUserInteraction()

        if currentSession.currentLayer > 0 {
            // Step back one layer, preserving its selection as candidate.
            currentSession.goBackOneLayer()
            currentCandidateStartOverride = nil
            objectWillChange.send()
        } else {
            // On the first layer: if you want graceful quit-after-queue, wire it here.
            // renderQueue.requestTerminateWhenDone()
        }
    }

    /// Called whenever the user presses a key that changes the state.
    private func noteUserInteraction() {
        scheduleAutoPrimeTimer()
    }

    /// Create a new random stack of layers, as if the user had manually chosen them.
    private func autoPrimeNow() {
        guard settings.maxLayers > 0 else { return }

        let total = settings.maxLayers
        // 2..maxLayers normally; fall back to 1 if maxLayers == 1.
        let minLayers = min(2, total)
        let activeCount = Int.random(in: minLayers...total)

        currentSession.primeRandomLayers(activeLayerCount: activeCount)
        currentCandidateStartOverride = nil
        objectWillChange.send()
    }

    /// (Re)schedule inactivity timeout to auto-prime again.
    private func scheduleAutoPrimeTimer() {
        guard settings.autoPrime, settings.autoPrimeTimeout > 0 else {
            autoPrimeTimer?.invalidate()
            autoPrimeTimer = nil
            return
        }

        autoPrimeTimer?.invalidate()
        autoPrimeTimer = Timer.scheduledTimer(
            withTimeInterval: settings.autoPrimeTimeout,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.autoPrimeNow()
            self.scheduleAutoPrimeTimer()
        }
    }
}
