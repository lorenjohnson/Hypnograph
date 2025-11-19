//
//  HypnogramState.swift
//  Hypnograph
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import Combine
import CoreMedia
import CoreGraphics

/// Manages the current in-progress hypnogram:
public final class HypnogramState: ObservableObject {
    // MARK: - Core configuration

    public private(set) var settings: Settings
    private var library: VideoSourcesLibrary
    public var blendModes: [BlendMode]

    // MARK: - Layer state

    /// Index of the layer currently being chosen [0 ..< maxLayers]
    @Published public private(set) var currentLayerIndex: Int = 0

    /// For each layer, the current candidate clip (Space cycles this).
    @Published public private(set) var candidateClips: [VideoClip?]

    /// For each layer, the accepted clip (after Return is pressed).
    @Published public private(set) var selectedClips: [VideoClip?]

    /// For each layer, index into `blendModes` determining its mode.
    @Published public private(set) var layerBlendIndices: [Int]

    // MARK: - UI-ish state

    /// Preview time offset for the current candidate (composition-relative time).
    @Published public var currentCandidateStartOverride: CMTime?

    /// HUD visibility flag (for the overlay in ContentView).
    @Published public var isHUDVisible: Bool = false

    // MARK: - Auto-prime timer

    private var autoPrimeTimer: Timer?

    // MARK: - Init

    public init(settings: Settings) {
        self.settings = settings
        self.library  = VideoSourcesLibrary(sourceFolders: settings.sourceFolders)
        self.blendModes = settings.blendModes.map { BlendMode(key: $0) }
        self.currentLayerIndex = 0

        let layers = max(1, settings.maxLayers)
        self.candidateClips    = Array(repeating: nil, count: layers)
        self.selectedClips     = Array(repeating: nil, count: layers)
        self.layerBlendIndices = Array(repeating: 0,  count: layers)

        _ = nextCandidateForCurrentLayer()

        if settings.autoPrime {
            autoPrimeNow()
            scheduleAutoPrimeTimer()
        }
    }

    // MARK: - Derived properties

    public var maxLayers: Int {
        candidateClips.count
    }

    /// The blend mode currently selected for the active layer.
    public var currentBlendMode: BlendMode {
        let idx = layerBlendIndices[currentLayerIndex]
        return blendModes[idx]
    }

    public var currentBlendModeName: String {
        currentBlendMode.name
    }

    /// Current candidate clip for the active layer, if any.
    public var currentCandidateClip: VideoClip? {
        guard currentLayerIndex >= 0 && currentLayerIndex < candidateClips.count else { return nil }
        return candidateClips[currentLayerIndex]
    }

    /// All layers, using candidate if present, else selected.
    public var layers: [HypnogramLayer] {
        var result: [HypnogramLayer] = []

        for layerIndex in 0..<maxLayers {
            let modeIndex = layerBlendIndices[layerIndex]
            let mode = blendModes[modeIndex]

            if let clip = candidateClips[layerIndex] ?? selectedClips[layerIndex] {
                result.append(HypnogramLayer(clip: clip, blendMode: mode))
            }
        }

        return result
    }
    /// Build a HypnogramRecipe for rendering.
    public func layersForRender() -> HypnogramRecipe? {
        guard !layers.isEmpty else { return nil }

        return HypnogramRecipe(
            layers: layers,
            targetDuration: self.settings.outputDuration
        )
    }

    // MARK: - High-level “intent” API (what the UI calls)

    public func nextCandidate() {
        noteUserInteraction()
        currentCandidateStartOverride = nil
        _ = nextCandidateForCurrentLayer()
    }

    public func acceptCandidate() {
        noteUserInteraction()

        if let offset = currentCandidateStartOverride,
           let candidate = currentCandidateClip {
            // Preview time is relative to the clip's current startTime.
            // Convert back to an absolute time in the source file.
            let absoluteStart = CMTimeAdd(candidate.startTime, offset)
            acceptCandidateForCurrentLayer(usingStartTime: absoluteStart)
        } else {
            acceptCandidateForCurrentLayer(usingStartTime: nil)
        }

        currentCandidateStartOverride = nil
    }

    public func prevLayer() {
        noteUserInteraction()
        currentLayerIndex = max(0, currentLayerIndex - 1)
    }

    public func nextLayer() {
        noteUserInteraction()
        currentLayerIndex = min(maxLayers - 1, currentLayerIndex + 1)
    }

    public func selectLayer(index: Int) {
        noteUserInteraction()
        let clamped = max(0, min(maxLayers - 1, index))
        currentLayerIndex = clamped
    }

    public func cycleBlendMode() {
        noteUserInteraction()
        cycleBlendModeForCurrentLayer()
    }

    public func toggleHUD() {
        isHUDVisible.toggle()
    }

    /// Step back a layer if possible.
    public func handleEscape() {
        noteUserInteraction()

        if currentLayerIndex > 0 {
            goBackOneLayer()
            currentCandidateStartOverride = nil
        } else {
            // Base layer: you could request queue termination here if desired.
        }
    }

    /// Generate a completely new auto-primed set.
    public func newAutoPrimeSet() {
        noteUserInteraction()
        autoPrimeNow()
    }

    /// Reload settings from disk and reconfigure the state.
    public func reloadSettings(from url: URL) {
        do {
            let newSettings = try SettingsLoader.load(from: url)
            applySettings(newSettings)
            print("🔄 Reloaded settings from \(url.path)")
        } catch {
            print("⚠️ Failed to reload settings; keeping existing settings. Error: \(error)")
        }
    }

    /// After enqueuing a recipe for render, call this to start a fresh one.
    /// This does *not* auto-prime; caller decides that.
    public func resetForNextHypnogram() {
        let layersCount = maxLayers

        selectedClips     = Array(repeating: nil, count: layersCount)
        candidateClips    = Array(repeating: nil, count: layersCount)
        layerBlendIndices = Array(repeating: 0,  count: layersCount)
        currentLayerIndex = 0
        currentCandidateStartOverride = nil

        _ = nextCandidateForCurrentLayer()
    }

    // MARK: - Core actions (lower-level, used internally)

    /// Get a new random candidate for the current layer.
    @discardableResult
    public func nextCandidateForCurrentLayer() -> VideoClip? {
        guard let clip = library.randomClip(clipLength: settings.outputDuration.seconds) else {
            return nil
        }
        candidateClips[currentLayerIndex] = clip
        return clip
    }

    /// Accept the current candidate for this layer,
    /// optionally overriding its start time with a custom playhead time,
    /// and move to the next layer if there is one.
    public func acceptCandidateForCurrentLayer(usingStartTime customStart: CMTime? = nil) {
        guard let candidate = candidateClips[currentLayerIndex] else { return }

        let finalClip: VideoClip

        if let customStart = customStart {
            let fileDuration = candidate.file.duration

            // Ensure customStart isn't beyond the end of the file.
            let startSeconds = min(customStart.seconds, fileDuration.seconds)
            let remaining = max(0.0, fileDuration.seconds - startSeconds)
            guard remaining > 0 else { return }

            // Keep original requested duration, but don't exceed remaining.
            let newLength = min(candidate.duration.seconds, remaining)

            let newStartTime = CMTime(
                seconds: startSeconds,
                preferredTimescale: candidate.startTime.timescale
            )
            let newDuration = CMTime(
                seconds: newLength,
                preferredTimescale: candidate.duration.timescale
            )

            finalClip = VideoClip(
                file: candidate.file,
                startTime: newStartTime,
                duration: newDuration
            )
        } else {
            finalClip = candidate
        }

        selectedClips[currentLayerIndex] = finalClip
        candidateClips[currentLayerIndex] = finalClip

        if currentLayerIndex + 1 < maxLayers {
            // Inherit blend mode from this layer to the next.
            let currentBlendIndex = layerBlendIndices[currentLayerIndex]
            let nextLayerIndex = currentLayerIndex + 1
            layerBlendIndices[nextLayerIndex] = currentBlendIndex

            currentLayerIndex = nextLayerIndex
            _ = nextCandidateForCurrentLayer()
        } else {
            // All layers have selected clips; ready to render.
        }
    }

    /// M: Cycle the blend mode for the *current* layer.
    public func cycleBlendModeForCurrentLayer() {
        guard !blendModes.isEmpty else { return }

        // Disable changing on the first layer to avoid confusing "black screen" behavior.
        guard currentLayerIndex > 0 else {
            return
        }

        var idx = layerBlendIndices[currentLayerIndex]
        idx = (idx + 1) % blendModes.count
        layerBlendIndices[currentLayerIndex] = idx
    }

    /// Go back one layer and DROP the layer we were on.
    /// - The layer we are leaving is cleared (no candidate, no selected, blend reset).
    /// - `currentLayer` moves down by 1.
    /// - The new current layer gets its selected clip (if any) as candidate so you can tweak it.
    public func goBackOneLayer() {
        // Nothing to drop if we're already at the base layer.
        guard currentLayerIndex > 0 else { return }

        // The layer we are *leaving* should be killed.
        let layerToDrop = currentLayerIndex
        candidateClips[layerToDrop] = nil
        selectedClips[layerToDrop]  = nil
        layerBlendIndices[layerToDrop] = 0

        // Move the cursor down.
        currentLayerIndex -= 1

        // For the new current layer, show its selected clip (if any) as the candidate.
        if let selected = selectedClips[currentLayerIndex] {
            candidateClips[currentLayerIndex] = selected
        }
    }

    /// Fill the first `activeLayerCount` layers with random clips + random blend modes,
    /// clear the rest, and position the cursor on the top-most active layer.
    ///
    /// This is deliberately dumb and stateless: callers decide *when* and *how many*.
    public func primeRandomLayers(activeLayerCount: Int) {
        let totalLayers = maxLayers
        guard totalLayers > 0 else {
            currentLayerIndex = 0
            return
        }

        let clampedCount = max(1, min(activeLayerCount, totalLayers))

        // Clear everything so we don't leak old selections.
        candidateClips    = Array(repeating: nil, count: totalLayers)
        selectedClips     = Array(repeating: nil, count: totalLayers)
        layerBlendIndices = Array(repeating: 0,  count: totalLayers)

        // Fill first clampedCount layers with random clips + random blend modes.
        for i in 0..<clampedCount {
            if let clip = library.randomClip(clipLength: settings.outputDuration.seconds) {
                candidateClips[i] = clip
                selectedClips[i]  = clip
            }

            if !blendModes.isEmpty {
                layerBlendIndices[i] = (Double.random(in: 0...1) < 0.8)
                    ? 0
                    : Int.random(in: 1..<blendModes.count)
            }
        }

        // Cursor on the top-most active layer so M/randomize etc. are meaningful.
        currentLayerIndex = clampedCount - 1
    }

    // MARK: - Settings reload

    private func applySettings(_ newSettings: Settings) {
        settings = newSettings
        library  = VideoSourcesLibrary(sourceFolders: newSettings.sourceFolders)
        blendModes = newSettings.blendModes.map { BlendMode(key: $0) }

        let layersCount = max(1, newSettings.maxLayers)
        candidateClips    = Array(repeating: nil, count: layersCount)
        selectedClips     = Array(repeating: nil, count: layersCount)
        layerBlendIndices = Array(repeating: 0,  count: layersCount)
        currentLayerIndex = 0
        currentCandidateStartOverride = nil

        _ = nextCandidateForCurrentLayer()

        autoPrimeTimer?.invalidate()
        autoPrimeTimer = nil
        if newSettings.autoPrime {
            autoPrimeNow()
            scheduleAutoPrimeTimer()
        }
    }

    // MARK: - Auto-prime timer

    private func noteUserInteraction() {
        scheduleAutoPrimeTimer()
    }

    private func autoPrimeNow() {
        guard settings.maxLayers > 0 else { return }

        let total = settings.maxLayers
        // 2..maxLayers normally; fall back to 1 if maxLayers == 1.
        let minLayers = min(2, total)
        let activeCount = Int.random(in: minLayers...total)

        primeRandomLayers(activeLayerCount: activeCount)
        currentCandidateStartOverride = nil
    }

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
