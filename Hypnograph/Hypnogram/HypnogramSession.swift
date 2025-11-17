//
//  HypnogramSession.swift
//  Hypnograph
//
//  Created by Loren Johnson on 15.11.25.
//


import Foundation
import Combine
import CoreMedia

/// Manages the current in-progress hypnogram:
/// - which layer we're on
/// - candidate clips per layer
/// - accepted clips per layer
/// - blend mode per layer
///
/// This is the logic your UI will drive with:
/// - Space: nextCandidateForCurrentLayer()
/// - Return: acceptCandidateForCurrentLayer()
/// - M: cycleBlendModeForCurrentLayer()
/// - R: currentRecipe() + resetForNextHypnogram()
final class HypnogramSession: ObservableObject {
    let settings: Settings
    let library: ClipLibrary
    let blendModes: [BlendMode]
    
    /// Index of the layer currently being chosen [0 ..< maxLayers]
    @Published private(set) var currentLayer: Int = 0

    /// For each layer, the current candidate clip (Space cycles this).
    @Published private(set) var candidateClips: [VideoClip?]

    /// For each layer, the accepted clip (after Return is pressed).
    @Published private(set) var selectedClips: [VideoClip?]
    
    /// For each layer, index into `blendModes` determining its mode.
    @Published private(set) var layerBlendIndices: [Int]

    init(settings: Settings) {
        self.settings = settings
        self.library = FolderMediaLibrary(settings: settings)
        self.blendModes = settings.blendModes.map { BlendMode(name: $0) }
        self.currentLayer = 0

        let layers = max(1, settings.maxLayers)
        self.candidateClips = Array(repeating: nil, count: layers)
        self.selectedClips  = Array(repeating: nil, count: layers)
        self.layerBlendIndices = Array(repeating: 0, count: layers)

        _ = nextCandidateForCurrentLayer()
    }

    var maxLayers: Int {
        candidateClips.count
    }
    
    /// The blend mode currently selected for the active layer.
    var currentBlendMode: BlendMode {
        let idx = layerBlendIndices[currentLayer]
        return blendModes[idx]
    }
    
    // MARK: - Actions (to drive from UI)
    
    /// SPACE: Get a new random candidate for the current layer.
    @discardableResult
    func nextCandidateForCurrentLayer() -> VideoClip? {
        guard let clip = library.randomClip(clipLength: settings.outputSeconds) else {
            return nil
        }
        candidateClips[currentLayer] = clip
        return clip
    }
    
    /// RETURN: Accept the current candidate for this layer,
    /// optionally overriding its start time with a custom playhead time,
    /// and move to the next layer if there is one.
    func acceptCandidateForCurrentLayer(usingStartTime customStart: CMTime? = nil) {
        guard let candidate = candidateClips[currentLayer] else { return }

        let finalClip: VideoClip

        if let customStart = customStart {
            let fileDuration = candidate.file.duration

            // Ensure customStart isn't beyond the end of the file.
            let startSeconds = min(customStart.seconds, fileDuration.seconds)
            let remaining = max(0.0, fileDuration.seconds - startSeconds)
            guard remaining > 0 else { return }

            // Keep original requested duration, but don't exceed remaining.
            let newLength = min(candidate.duration.seconds, remaining)

            let newStartTime = CMTime(seconds: startSeconds, preferredTimescale: candidate.startTime.timescale)
            let newDuration = CMTime(seconds: newLength, preferredTimescale: candidate.duration.timescale)

            finalClip = VideoClip(
                file: candidate.file,
                startTime: newStartTime,
                duration: newDuration
            )
        } else {
            finalClip = candidate
        }

        selectedClips[currentLayer] = finalClip
        candidateClips[currentLayer] = finalClip

        if currentLayer + 1 < maxLayers {
            // Inherit blend mode from this layer to the next.
            let currentBlendIndex = layerBlendIndices[currentLayer]
            let nextLayer = currentLayer + 1
            layerBlendIndices[nextLayer] = currentBlendIndex

            currentLayer = nextLayer
            _ = nextCandidateForCurrentLayer()
        } else {
            // All layers have selected clips; ready to render.
        }
    }
    
    /// Randomize the clip (and optionally blend) for a specific layer.
    /// Used by keys 1, 2, 3 etc.
    func randomizeLayer(_ index: Int, randomizeBlend: Bool = false) {
        guard index >= 0 && index < maxLayers else { return }

        currentLayer = index
        _ = nextCandidateForCurrentLayer()

        if randomizeBlend, !blendModes.isEmpty {
            layerBlendIndices[index] = Int.random(in: 0..<blendModes.count)
        }
    }
    
    /// M: Cycle the blend mode for the *current* layer.
    /// On layer 0, do nothing (base layer has no meaningful blend visually).
    func cycleBlendModeForCurrentLayer() {
        guard !blendModes.isEmpty else { return }

        // Disable changing on the first layer to avoid confusing "black screen" behavior.
        guard currentLayer > 0 else {
            return
        }

        var idx = layerBlendIndices[currentLayer]
        idx = (idx + 1) % blendModes.count
        layerBlendIndices[currentLayer] = idx
    }

    /// ESC / Delete: Go back one layer and DROP the layer we were on.
    /// - The layer we are leaving is cleared (no candidate, no selected, blend reset).
    /// - `currentLayer` moves down by 1.
    /// - The new current layer gets its selected clip (if any) as candidate so you can tweak it.
    func goBackOneLayer() {
        // Nothing to drop if we're already at the base layer.
        guard currentLayer > 0 else { return }

        // The layer we are *leaving* should be killed.
        let layerToDrop = currentLayer
        candidateClips[layerToDrop] = nil
        selectedClips[layerToDrop]  = nil
        layerBlendIndices[layerToDrop] = 0

        // Move the cursor down.
        currentLayer -= 1

        // For the new current layer, show its selected clip (if any) as the candidate.
        if let selected = selectedClips[currentLayer] {
            candidateClips[currentLayer] = selected
        }
    }

    /// Build a HypnogramRecipe from:
    /// - all *selected* layers below the current one
    /// - the *current* layer’s candidate (or selected if no candidate)
    /// Layers above the current one are ignored.
    ///
    /// Returns nil only if *no* clips are present at all.
    func currentRecipe() -> HypnogramRecipe? {
        var layers: [HypnogramLayer] = []

        for layerIndex in 0..<maxLayers {
            // Prefer candidate, fall back to selected.
            guard let clip = candidateClips[layerIndex] ?? selectedClips[layerIndex] else {
                continue
            }
            let modeIndex = layerBlendIndices[layerIndex]
            let mode = blendModes[modeIndex]
            layers.append(HypnogramLayer(clip: clip, blendMode: mode))
        }

        guard !layers.isEmpty else { return nil }

        let duration = CMTime(
            seconds: settings.outputSeconds,
            preferredTimescale: 600
        )

        return HypnogramRecipe(layers: layers, targetDuration: duration)
    }

    /// Fill the first `activeLayerCount` layers with random clips + random blend modes,
    /// clear the rest, and position the cursor on the top-most active layer.
    ///
    /// This is deliberately dumb and stateless: callers decide *when* and *how many*.
    func primeRandomLayers(activeLayerCount: Int) {
        let totalLayers = maxLayers
        guard totalLayers > 0 else {
            currentLayer = 0
            return
        }

        let clampedCount = max(1, min(activeLayerCount, totalLayers))

        // Clear everything so we don't leak old selections.
        candidateClips    = Array(repeating: nil, count: totalLayers)
        selectedClips     = Array(repeating: nil, count: totalLayers)
        layerBlendIndices = Array(repeating: 0,  count: totalLayers)

        // Fill first clampedCount layers with random clips + random blend modes.
        for i in 0..<clampedCount {
            if let clip = library.randomClip(clipLength: settings.outputSeconds) {
                candidateClips[i] = clip
                selectedClips[i]  = clip
            }

            if !blendModes.isEmpty {
                // layerBlendIndices[i] = 0
                // layerBlendIndices[i] = Int.random(in: 0..<2)
                layerBlendIndices[i] = (Double.random(in: 0...1) < 0.8)
                    ? 0
                    : Int.random(in: 1..<blendModes.count)
            }
        }

        // Cursor on the top-most active layer so M/randomize etc. are meaningful.
        currentLayer = clampedCount - 1
    }

    /// After enqueuing a recipe for render, call this to start a fresh one.
    /// This does *not* auto-prime; higher layers (ViewModel) decide that.
    func resetForNextHypnogram() {
        let layers = maxLayers

        selectedClips     = Array(repeating: nil, count: layers)
        candidateClips    = Array(repeating: nil, count: layers)
        layerBlendIndices = Array(repeating: 0,  count: layers)
        currentLayer      = 0

        _ = nextCandidateForCurrentLayer()
    }

    /// Build a list of layers for live preview:
    /// - For every layer, use candidate if present, otherwise selected.
    /// - Ignore layers that have neither.
    func previewLayers() -> [HypnogramLayer] {
        var result: [HypnogramLayer] = []

        for index in 0..<maxLayers {
            let modeIndex = layerBlendIndices[index]
            let mode = blendModes[modeIndex]

            if let clip = candidateClips[index] ?? selectedClips[index] {
                result.append(HypnogramLayer(clip: clip, blendMode: mode))
            }
        }

        return result
    }}
