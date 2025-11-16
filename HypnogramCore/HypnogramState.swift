//
//  HypnogramState.swift
//  Hypnogram
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
final class HypnogramState: ObservableObject {
    let config: HypnogramConfig
    let library: MediaLibrary
    let blendModes: [BlendMode]
    
    /// Index of the layer currently being chosen [0 ..< maxLayers]
    @Published private(set) var currentLayer: Int = 0
    
    /// For each layer, the current candidate clip (Space cycles this).
    @Published private(set) var candidateClips: [VideoClip?]
    
    /// For each layer, the accepted clip (after Return is pressed).
    @Published private(set) var selectedClips: [VideoClip?]
    
    /// For each layer, index into `blendModes` determining its mode.
    @Published private(set) var layerBlendIndices: [Int]
    
    init(config: HypnogramConfig) {
        self.config = config
        self.library = MediaLibrary(config: config)
        self.blendModes = config.blendModes.map { BlendMode(name: $0) }
        
        let layers = max(1, config.maxLayers)
        self.candidateClips = Array(repeating: nil, count: layers)
        self.selectedClips  = Array(repeating: nil, count: layers)
        self.layerBlendIndices = Array(repeating: 0, count: layers)
        
        // Start at layer 0 with an initial candidate
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
        guard let clip = library.randomClip(clipLength: config.clipLengthSeconds) else {
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
    
    /// M: Cycle the blend mode for the current layer.
    func cycleBlendModeForCurrentLayer() {
        guard !blendModes.isEmpty else { return }
        var idx = layerBlendIndices[currentLayer]
        idx = (idx + 1) % blendModes.count
        layerBlendIndices[currentLayer] = idx
    }
    
    /// ESC: Go back to the previous layer, preserving any selected clip.
    /// When stepping back, we set the candidate for that layer to the selected clip
    /// so you can tweak or re-accept it.
    func goBackOneLayer() {
        guard currentLayer > 0 else { return }
        currentLayer -= 1
        candidateClips[currentLayer] = selectedClips[currentLayer]
    }

    /// Build a HypnogramRecipe from all layers that have a selected clip.
    /// Returns nil only if *no* layers are selected.
    func currentRecipe() -> HypnogramRecipe? {
        var layers: [HypnogramLayer] = []

        for (index, maybeClip) in selectedClips.enumerated() {
            guard let clip = maybeClip else { continue }

            let modeIndex = layerBlendIndices[index]
            let mode = blendModes[modeIndex]

            layers.append(HypnogramLayer(clip: clip, blendMode: mode))
        }

        guard !layers.isEmpty else {
            print("currentRecipe(): no selected clips, recipe is nil")
            return nil
        }

        print("currentRecipe(): building recipe with \(layers.count) selected layers")
        return HypnogramRecipe(layers: layers)
    }
    
    /// After enqueuing a recipe for render, call this to start a fresh one.
    func resetForNextHypnogram() {
        selectedClips = Array(repeating: nil, count: maxLayers)
        candidateClips = Array(repeating: nil, count: maxLayers)
        layerBlendIndices = Array(repeating: 0, count: maxLayers)
        currentLayer = 0
        _ = nextCandidateForCurrentLayer()
    }

    /// Build a list of layers for live preview:
    /// - For layers < currentLayer: use selected clips (if any)
    /// - For currentLayer: prefer the candidate clip, or fall back to selected
    /// - For layers > currentLayer: ignore (not yet active)
    func previewLayers() -> [HypnogramLayer] {
        var result: [HypnogramLayer] = []

        for index in 0..<maxLayers {
            let modeIndex = layerBlendIndices[index]
            let mode = blendModes[modeIndex]

            if index < currentLayer {
                // Past layers: only show if selected.
                if let clip = selectedClips[index] {
                    result.append(HypnogramLayer(clip: clip, blendMode: mode))
                }
            } else if index == currentLayer {
                // Current layer: prefer candidate, fall back to selected.
                if let clip = candidateClips[index] ?? selectedClips[index] {
                    result.append(HypnogramLayer(clip: clip, blendMode: mode))
                }
            } else {
                // Future layers: nothing yet.
                continue
            }
        }

        return result
    }
}
