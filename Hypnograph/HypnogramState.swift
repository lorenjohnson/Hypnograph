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

    /// Index of the source currently being chosen [0 ..< maxSources]
    @Published public private(set) var currentSourceIndex: Int = 0

    /// For each source, the current candidate clip (Space cycles this).
    @Published public private(set) var candidateClips: [VideoClip?]

    /// For each source, the accepted clip (after Return is pressed).
    @Published public private(set) var selectedClips: [VideoClip?]

    /// For each source, index into `blendModes` determining its mode.
    @Published public private(set) var sourceBlendIndices: [Int]

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
        
        let sources = max(1, settings.maxSources)
        self.candidateClips    = Array(repeating: nil, count: sources)
        self.selectedClips     = Array(repeating: nil, count: sources)
        self.sourceBlendIndices = Array(repeating: 0,  count: sources)

        _ = nextCandidateForCurrentSource()

        if settings.autoPrime {
            autoPrimeNow()
            scheduleAutoPrimeTimer()
        }
    }

    // MARK: - Derived properties

    public var maxSources: Int {
        candidateClips.count
    }

    /// Number of sources that currently have a clip (no empties)
    public var activeSourceCount: Int {
        sources.count
    }

    /// The blend mode currently selected for the active source.
    public var currentBlendMode: BlendMode {
        let idx = sourceBlendIndices[currentSourceIndex]
        return blendModes[idx]
    }

    public var currentBlendModeName: String {
        currentBlendMode.name
    }

    /// Current candidate clip for the active source, if any.
    public var currentCandidateClip: VideoClip? {
        guard currentSourceIndex >= 0 && currentSourceIndex < candidateClips.count else { return nil }
        return candidateClips[currentSourceIndex]
    }

    /// All sources, using candidate if present, else selected.
    public var sources: [HypnogramSource] {
        var result: [HypnogramSource] = []

        for sourceIndex in 0..<maxSources {
            let modeIndex = sourceBlendIndices[sourceIndex]
            let mode = blendModes[modeIndex]

            if let clip = candidateClips[sourceIndex] ?? selectedClips[sourceIndex] {
                result.append(HypnogramSource(clip: clip, blendMode: mode))
            }
        }

        return result
    }
    /// Build a HypnogramRecipe for rendering.
    public func sourcesForRender() -> HypnogramRecipe? {
        guard !sources.isEmpty else { return nil }

        return HypnogramRecipe(
            sources: sources,
            targetDuration: self.settings.outputDuration
        )
    }

    // MARK: - High-level “intent” API (what the UI calls)

    public func nextCandidate() {
        noteUserInteraction()
        currentCandidateStartOverride = nil
        _ = nextCandidateForCurrentSource()
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

    public func prevSource() {
        noteUserInteraction()
        currentSourceIndex = max(0, currentSourceIndex - 1)
    }

    public func nextSource() {
        noteUserInteraction()
        currentSourceIndex = min(maxSources - 1, currentSourceIndex + 1)
    }

    public func selectSource(index: Int) {
        noteUserInteraction()
        let clamped = max(0, min(maxSources - 1, index))
        currentSourceIndex = clamped
    }

    public func cycleBlendMode() {
        noteUserInteraction()
        cycleBlendModeForCurrentSource()
    }

    public func toggleHUD() {
        isHUDVisible.toggle()
    }

    /// Step back a source if possible.
    public func handleEscape() {
        noteUserInteraction()

        deleteCurrentSource()
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
        let sourcesCount = maxSources

        selectedClips     = Array(repeating: nil, count: sourcesCount)
        candidateClips    = Array(repeating: nil, count: sourcesCount)
        sourceBlendIndices = Array(repeating: 0,  count: sourcesCount)
        currentSourceIndex = 0
        currentCandidateStartOverride = nil

        _ = nextCandidateForCurrentSource()
    }

    // MARK: - Core actions (lower-level, used internally)

    /// Get a new random candidate for the current source.
    @discardableResult
    public func nextCandidateForCurrentSource() -> VideoClip? {
        guard let clip = library.randomClip(clipLength: settings.outputDuration.seconds) else {
            return nil
        }
        candidateClips[currentSourceIndex] = clip
        return clip
    }

    /// Get a new random candidate for the current source with a custom length.
    @discardableResult
    public func setRandomCandidateForCurrentSource(clipLength: Double) -> VideoClip? {
        guard let clip = library.randomClip(clipLength: clipLength) else { return nil }
        candidateClips[currentSourceIndex] = clip
        selectedClips[currentSourceIndex] = clip
        return clip
    }

    /// Explicitly set the candidate (and selected) clip for a given source index.
    public func setCandidate(_ clip: VideoClip, forSource index: Int? = nil) {
        let idx = index ?? currentSourceIndex
        guard idx >= 0 && idx < candidateClips.count else { return }
        candidateClips[idx] = clip
        selectedClips[idx] = clip
    }

    /// Accept the current candidate for this source,
    /// optionally overriding its start time with a custom playhead time,
    /// and move to the next source if there is one.
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

        if currentSourceIndex + 1 < maxSources {
            // Inherit blend mode from this source to the next.
            let currentBlendIndex = sourceBlendIndices[currentSourceIndex]
            let nextSourceIndex = currentSourceIndex + 1
            sourceBlendIndices[nextSourceIndex] = currentBlendIndex

            currentSourceIndex = nextSourceIndex
            _ = nextCandidateForCurrentSource()
        } else {
            // All sources have selected clips; ready to render.
        }
    }

    /// M: Cycle the blend mode for the *current* source.
    public func cycleBlendModeForCurrentSource() {
        guard !blendModes.isEmpty else { return }

        // Disable changing on the first source to avoid confusing "black screen" behavior.
        guard currentSourceIndex > 0 else {
            return
        }

        var idx = sourceBlendIndices[currentSourceIndex]
        idx = (idx + 1) % blendModes.count
        sourceBlendIndices[currentSourceIndex] = idx
    }

    /// Go back one source and DROP the source we were on.
    /// - The source we are leaving is cleared (no candidate, no selected, blend reset).
    /// - `currentSource` moves down by 1.
    /// - The new current source gets its selected clip (if any) as candidate so you can tweak it.
    public func goBackOneSource() {
        // Nothing to drop if we're already at the base source.
        guard currentSourceIndex > 0 else { return }
        deleteLayer(at: currentSourceIndex)
    }

    /// Fill the first `activeSourceCount` sources with random clips + random blend modes,
    /// clear the rest, and position the cursor on the top-most active source.
    ///
    /// This is deliberately dumb and stateless: callers decide *when* and *how many*.
    public func primeRandomSources(activeSourceCount: Int) {
        let totalLayers = maxSources
        guard totalLayers > 0 else {
            currentSourceIndex = 0
            return
        }

        let clampedCount = max(1, min(activeSourceCount, totalLayers))

        // Clear everything so we don't leak old selections.
        candidateClips    = Array(repeating: nil, count: totalLayers)
        selectedClips     = Array(repeating: nil, count: totalLayers)
        sourceBlendIndices = Array(repeating: 0,  count: totalLayers)

        // Fill first clampedCount sources with random clips + random blend modes.
        for i in 0..<clampedCount {
            if let clip = library.randomClip(clipLength: settings.outputDuration.seconds) {
                candidateClips[i] = clip
                selectedClips[i]  = clip
            }

            if !blendModes.isEmpty {
                sourceBlendIndices[i] = (Double.random(in: 0...1) < 0.8)
                    ? 0
                    : Int.random(in: 1..<blendModes.count)
            }
        }

        // Cursor on the top-most active source so M/randomize etc. are meaningful.
        currentSourceIndex = clampedCount - 1
    }

    // MARK: - Layer deletion helpers

    /// Delete the current source, keeping arrays dense (no empty slots).
    public func deleteCurrentSource() {
        deleteLayer(at: currentSourceIndex)
    }

    /// Remove a source at the given index and keep indices contiguous.
    private func deleteLayer(at index: Int) {
        guard index >= 0, index < candidateClips.count else { return }

        candidateClips.remove(at: index)
        selectedClips.remove(at: index)
        sourceBlendIndices.remove(at: index)

        if candidateClips.isEmpty {
            // Always maintain at least one source
            candidateClips = [nil]
            selectedClips = [nil]
            sourceBlendIndices = [0]
            currentSourceIndex = 0
            _ = nextCandidateForCurrentSource()
            return
        }

        // Clamp current source to valid range
        currentSourceIndex = min(currentSourceIndex, candidateClips.count - 1)

        // If the new current source has a selected clip, show it as candidate
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

        let sourcesCount = max(1, newSettings.maxSources)
        candidateClips    = Array(repeating: nil, count: sourcesCount)
        selectedClips     = Array(repeating: nil, count: sourcesCount)
        sourceBlendIndices = Array(repeating: 0,  count: sourcesCount)
        currentSourceIndex = 0
        currentCandidateStartOverride = nil

        _ = nextCandidateForCurrentSource()

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
        guard settings.maxSources > 0 else { return }

        let total = settings.maxSources
        // 2..maxSources normally; fall back to 1 if maxSources == 1.
        let minLayers = min(2, total)
        let activeCount = Int.random(in: minLayers...total)

        primeRandomSources(activeSourceCount: activeCount)
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
