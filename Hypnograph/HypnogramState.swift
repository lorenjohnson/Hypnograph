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
    public private(set) var library: VideoSourcesLibrary
    public var blendModes: [BlendMode]

    // MARK: - Mode management

    /// Current mode type (Montage or Sequence)
    @Published public var currentModeType: ModeType = .montage

    // MARK: - Layer state

    /// Index of the layer currently being chosen [0 ..< maxLayers]
    @Published public private(set) var currentSourceIndex: Int = 0

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

    /// Render hooks
    let renderHooks = RenderHookManager()
    // optional: a baseline params object to reuse
    var baseRenderParams = RenderParams()

    // MARK: - Auto-prime timer

    private var autoPrimeTimer: Timer?

    // MARK: - Init

    public init(settings: Settings) {
        self.settings = settings
        self.library  = VideoSourcesLibrary(sourceFolders: settings.sourceFolders)
        self.blendModes = settings.blendModes.map { BlendMode(key: $0) }
        self.currentSourceIndex = 0
        
        let layers = max(1, settings.maxLayers)
        self.candidateClips    = Array(repeating: nil, count: layers)
        self.selectedClips     = Array(repeating: nil, count: layers)
        self.layerBlendIndices = Array(repeating: 0,  count: layers)

        _ = nextCandidateForcurrentSource()

        if settings.autoPrime {
            autoPrimeNow()
            scheduleAutoPrimeTimer()
        }
    }

    // MARK: - Derived properties

    public var maxLayers: Int {
        candidateClips.count
    }

    /// Number of layers that currently have a clip (no empties)
    public var activeLayerCount: Int {
        layers.count
    }

    /// The blend mode currently selected for the active layer.
    public var currentBlendMode: BlendMode {
        let idx = layerBlendIndices[currentSourceIndex]
        return blendModes[idx]
    }

    public var currentBlendModeName: String {
        currentBlendMode.name
    }

    /// Current candidate clip for the active layer, if any.
    public var currentCandidateClip: VideoClip? {
        guard currentSourceIndex >= 0 && currentSourceIndex < candidateClips.count else { return nil }
        return candidateClips[currentSourceIndex]
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
        _ = nextCandidateForcurrentSource()
    }

    public func acceptCandidate() {
        noteUserInteraction()

        if let offset = currentCandidateStartOverride,
           let candidate = currentCandidateClip {
            // Preview time is relative to the clip's current startTime.
            // Convert back to an absolute time in the source file.
            let absoluteStart = CMTimeAdd(candidate.startTime, offset)
            acceptCandidateForCurrentSource(usingStartTime: absoluteStart)
        } else {
            acceptCandidateForCurrentSource(usingStartTime: nil)
        }

        currentCandidateStartOverride = nil
    }

    public func prevLayer() {
        noteUserInteraction()
        currentSourceIndex = max(0, currentSourceIndex - 1)
    }

    public func nextLayer() {
        noteUserInteraction()
        currentSourceIndex = min(maxLayers - 1, currentSourceIndex + 1)
    }

    public func selectLayer(index: Int) {
        noteUserInteraction()
        let clamped = max(0, min(maxLayers - 1, index))
        currentSourceIndex = clamped
    }

    public func cycleBlendMode() {
        noteUserInteraction()
        cycleBlendModeForcurrentSource()
    }

    public func toggleHUD() {
        isHUDVisible.toggle()
    }

    /// Step back a layer if possible.
    public func handleEscape() {
        noteUserInteraction()

        deletecurrentSource()
        currentCandidateStartOverride = nil
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
        currentSourceIndex = 0
        currentCandidateStartOverride = nil

        _ = nextCandidateForcurrentSource()
    }

    // MARK: - Core actions (lower-level, used internally)

    /// Get a new random candidate for the current layer.
    @discardableResult
    public func nextCandidateForcurrentSource() -> VideoClip? {
        guard let clip = library.randomClip(clipLength: settings.outputDuration.seconds) else {
            return nil
        }
        candidateClips[currentSourceIndex] = clip
        return clip
    }

    /// Accept the current candidate for this layer,
    /// optionally overriding its start time with a custom playhead time,
    /// and move to the next layer if there is one.
    public func acceptCandidateForCurrentSource(usingStartTime customStart: CMTime? = nil) {
        guard let candidate = candidateClips[currentSourceIndex] else { return }

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

        selectedClips[currentSourceIndex] = finalClip
        candidateClips[currentSourceIndex] = finalClip

        if currentSourceIndex + 1 < maxLayers {
            // Inherit blend mode from this layer to the next.
            let currentBlendIndex = layerBlendIndices[currentSourceIndex]
            let nextLayerIndex = currentSourceIndex + 1
            layerBlendIndices[nextLayerIndex] = currentBlendIndex

            currentSourceIndex = nextLayerIndex
            _ = nextCandidateForcurrentSource()
        } else {
            // All layers have selected clips; ready to render.
        }
    }

    /// M: Cycle the blend mode for the *current* layer.
    public func cycleBlendModeForcurrentSource() {
        guard !blendModes.isEmpty else { return }

        // Disable changing on the first layer to avoid confusing "black screen" behavior.
        guard currentSourceIndex > 0 else {
            return
        }

        var idx = layerBlendIndices[currentSourceIndex]
        idx = (idx + 1) % blendModes.count
        layerBlendIndices[currentSourceIndex] = idx
    }

    /// Go back one layer and DROP the layer we were on.
    /// - The layer we are leaving is cleared (no candidate, no selected, blend reset).
    /// - `currentSource` moves down by 1.
    /// - The new current layer gets its selected clip (if any) as candidate so you can tweak it.
    public func goBackOneLayer() {
        // Nothing to drop if we're already at the base layer.
        guard currentSourceIndex > 0 else { return }
        deleteLayer(at: currentSourceIndex)
    }

    /// Fill the first `activeLayerCount` layers with random clips + random blend modes,
    /// clear the rest, and position the cursor on the top-most active layer.
    ///
    /// This is deliberately dumb and stateless: callers decide *when* and *how many*.
    public func primeRandomLayers(activeLayerCount: Int) {
        let totalLayers = maxLayers
        guard totalLayers > 0 else {
            currentSourceIndex = 0
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
        currentSourceIndex = clampedCount - 1
    }

    // MARK: - Layer deletion helpers

    /// Delete the current layer, keeping arrays dense (no empty slots).
    private func deletecurrentSource() {
        deleteLayer(at: currentSourceIndex)
    }

    /// Remove a layer at the given index and keep indices contiguous.
    private func deleteLayer(at index: Int) {
        guard index >= 0, index < candidateClips.count else { return }

        candidateClips.remove(at: index)
        selectedClips.remove(at: index)
        layerBlendIndices.remove(at: index)

        if candidateClips.isEmpty {
            // Always maintain at least one layer
            candidateClips = [nil]
            selectedClips = [nil]
            layerBlendIndices = [0]
            currentSourceIndex = 0
            _ = nextCandidateForcurrentSource()
            return
        }

        // Clamp current layer to valid range
        currentSourceIndex = min(currentSourceIndex, candidateClips.count - 1)

        // If the new current layer has a selected clip, show it as candidate
        if let selected = selectedClips[currentSourceIndex] {
            candidateClips[currentSourceIndex] = selected
        }
    }

    // MARK: - Exclusions

    public func excludeCurrentSource() {
        guard let clip = currentCandidateClip else { return }
        library.exclude(file: clip.file)
        nextCandidate()
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
        currentSourceIndex = 0
        currentCandidateStartOverride = nil

        _ = nextCandidateForcurrentSource()

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
