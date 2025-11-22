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
final class HypnogramState: ObservableObject {
    // MARK: - Core configuration

    private(set) var settings: Settings

    /// Which named source library is currently active (e.g. "default", "renders", "photos").
    @Published private(set) var currentLibraryKey: String
    @Published private(set) var activeLibraryKeys: Set<String>

    private(set) var library: VideoSourcesLibrary
    var blendModes: [BlendMode]

    // MARK: - Mode management

    /// Current mode type (Montage, Sequence, Divine)
    @Published var currentModeType: ModeType = .montage

    // MARK: - Layer state

    /// Index of the source currently being chosen
    @Published private(set) var currentSourceIndex: Int = 0

    /// For each source, the accepted / current clip.
    @Published private(set) var selectedClips: [VideoClip?]

    /// For each source, index into `blendModes` determining its mode.
    @Published private(set) var sourceBlendIndices: [Int]

    // MARK: - UI-ish state

    /// Offset from the current clip's start time, based on the current playhead.
    @Published var currentClipTimeOffset: CMTime?

    /// HUD visibility flag (for the overlay in ContentView).
    @Published var isHUDVisible: Bool = true

    /// Render hooks
    let renderHooks = RenderHookManager()
    // optional: a baseline params object to reuse
    var baseRenderParams = RenderParams()

    // MARK: - Auto-prime timer

    private var autoPrimeTimer: Timer?

    // MARK: - Init

    init(settings: Settings) {
        // 1) Store raw settings
        self.settings = settings

        // 2) Compute initial library selection without touching `self`
        let defaultKey = settings.defaultSourceLibraryKey
        let initialKeys: Set<String> = [defaultKey]
        let initialFolders = settings.folders(forLibraries: initialKeys)

        // 3) Initialize all stored properties that *don’t* have inline defaults

        // Core configuration
        self.currentLibraryKey = defaultKey
        self.activeLibraryKeys = initialKeys
        self.library = VideoSourcesLibrary(sourceFolders: initialFolders)
        self.blendModes = settings.blendModes.map { BlendMode(key: $0) }

        // Mode management
        self.currentModeType = .montage

        // Layer state
        self.currentSourceIndex = 0
        let sources = max(1, settings.maxSources)
        self.selectedClips      = Array(repeating: nil, count: sources)
        self.sourceBlendIndices = Array(repeating: 0,  count: sources)

        // UI-ish state
        self.currentClipTimeOffset = nil
        self.isHUDVisible = true

        // Auto-prime timer
        self.autoPrimeTimer = nil

        // 4) Now it's safe to call methods that use `self`
        _ = nextCandidateForCurrentSource()

        if settings.autoPrime {
            autoPrimeNow()
            scheduleAutoPrimeTimer()
        }
    }

    // MARK: - Derived properties

    var maxSources: Int {
        selectedClips.count
    }

    /// Number of sources that currently have a clip (no empties)
    var activeSourceCount: Int {
        sources.count
    }

    /// The blend mode currently selected for the active source.
    var currentBlendMode: BlendMode {
        let idx = sourceBlendIndices[currentSourceIndex]
        return blendModes[idx]
    }

    var currentBlendModeName: String {
        currentBlendMode.name
    }

    /// Current clip for the active source, if any.
    var currentCandidateClip: VideoClip? {
        guard currentSourceIndex >= 0 && currentSourceIndex < selectedClips.count else { return nil }
        return selectedClips[currentSourceIndex]
    }

    /// All sources with a clip.
    var sources: [HypnogramSource] {
        var result: [HypnogramSource] = []

        for sourceIndex in 0..<maxSources {
            let modeIndex = sourceBlendIndices[sourceIndex]
            let mode = blendModes[modeIndex]

            if let clip = selectedClips[sourceIndex] {
                result.append(HypnogramSource(clip: clip, blendMode: mode))
            }
        }

        return result
    }

    /// Build a HypnogramRecipe for rendering.
    func sourcesForRender() -> HypnogramRecipe? {
        guard !sources.isEmpty else { return nil }

        return HypnogramRecipe(
            sources: sources,
            targetDuration: self.settings.outputDuration
        )
    }

    // MARK: - High-level “intent” API (what the UI calls)

    func nextCandidate() {
        noteUserInteraction()
        currentClipTimeOffset = nil
        _ = nextCandidateForCurrentSource()
    }

    func acceptCandidate() {
        noteUserInteraction()

        if let offset = currentClipTimeOffset,
           let candidate = currentCandidateClip {
            // Time is relative to the clip's current startTime.
            // Convert back to an absolute time in the source file.
            let absoluteStart = CMTimeAdd(candidate.startTime, offset)
            acceptCandidateForCurrentSource(usingStartTime: absoluteStart)
        } else {
            acceptCandidateForCurrentSource(usingStartTime: nil)
        }

        currentClipTimeOffset = nil
    }

    func prevSource() {
        noteUserInteraction()
        currentSourceIndex = max(0, currentSourceIndex - 1)
    }

    func nextSource() {
        noteUserInteraction()
        currentSourceIndex = min(maxSources - 1, currentSourceIndex + 1)
    }

    func selectSource(index: Int) {
        noteUserInteraction()
        let clamped = max(0, min(maxSources - 1, index))
        currentSourceIndex = clamped
    }

    func cycleBlendMode() {
        noteUserInteraction()
        cycleBlendModeForCurrentSource()
    }

    func toggleHUD() {
        isHUDVisible.toggle()
    }

    /// Step back a source if possible.
    func handleEscape() {
        noteUserInteraction()

        deleteCurrentSource()
        currentClipTimeOffset = nil
    }

    /// Generate a completely new auto-primed set.
    func newAutoPrimeSet() {
        noteUserInteraction()
        autoPrimeNow()
    }

    /// Reload settings from disk and reconfigure the state.
    func reloadSettings(from url: URL) {
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
    func resetForNextHypnogram() {
        let sourcesCount = maxSources

        selectedClips      = Array(repeating: nil, count: sourcesCount)
        sourceBlendIndices = Array(repeating: 0,  count: sourcesCount)
        currentSourceIndex = 0
        currentClipTimeOffset = nil

        _ = nextCandidateForCurrentSource()
    }

    // MARK: - Core actions (lower-level, used internally)

    /// Get a new random clip for the current source.
    @discardableResult
    func nextCandidateForCurrentSource() -> VideoClip? {
        guard let clip = library.randomClip(clipLength: settings.outputDuration.seconds) else {
            return nil
        }
        selectedClips[currentSourceIndex] = clip
        return clip
    }

    /// Get a new random clip for the current source with a custom length.
    @discardableResult
    func setRandomCandidateForCurrentSource(clipLength: Double) -> VideoClip? {
        guard let clip = library.randomClip(clipLength: clipLength) else { return nil }
        selectedClips[currentSourceIndex] = clip
        return clip
    }

    /// Explicitly set the clip for a given source index.
    func setCandidate(_ clip: VideoClip, forSource index: Int? = nil) {
        let idx = index ?? currentSourceIndex
        guard idx >= 0 && idx < selectedClips.count else { return }
        selectedClips[idx] = clip
    }

    /// Accept the current clip for this source,
    /// optionally overriding its start time with a custom playhead time,
    /// and move to the next source if there is one.
    func acceptCandidateForCurrentSource(usingStartTime customStart: CMTime? = nil) {
        guard let candidate = selectedClips[currentSourceIndex] else { return }

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

        if currentSourceIndex + 1 < maxSources {
            // Inherit blend mode from this source to the next.
            let currentBlendIndex = sourceBlendIndices[currentSourceIndex]
            let nextSourceIndex = currentSourceIndex + 1
            sourceBlendIndices[nextSourceIndex] = currentBlendIndex

            currentSourceIndex = nextSourceIndex
            _ = nextCandidateForCurrentSource()
        } else {
            // All sources have clips; ready to render.
        }
    }

    /// M: Cycle the blend mode for the *current* source.
    func cycleBlendModeForCurrentSource() {
        guard !blendModes.isEmpty else { return }

        var idx = sourceBlendIndices[currentSourceIndex]
        idx = (idx + 1) % blendModes.count
        sourceBlendIndices[currentSourceIndex] = idx
    }

    /// Fill the first `activeSourceCount` sources with random clips + random blend modes,
    /// clear the rest, and position the cursor on the top-most active source.
    ///
    /// This is deliberately dumb and stateless: callers decide *when* and *how many*.
    func primeRandomSources(activeSourceCount: Int) {
        let totalLayers = maxSources
        guard totalLayers > 0 else {
            currentSourceIndex = 0
            return
        }

        let clampedCount = max(1, min(activeSourceCount, totalLayers))

        // Clear everything so we don't leak old selections.
        selectedClips      = Array(repeating: nil, count: totalLayers)
        sourceBlendIndices = Array(repeating: 0,  count: totalLayers)

        // Fill first clampedCount sources with random clips + random blend modes.
        for i in 0..<clampedCount {
            if let clip = library.randomClip(clipLength: settings.outputDuration.seconds) {
                selectedClips[i] = clip
            }

            if !blendModes.isEmpty {
                // 80% chance of first blend mode, else random of the rest.
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
    func deleteCurrentSource() {
        deleteLayer(at: currentSourceIndex)
    }

    /// Remove a source at the given index and keep indices contiguous.
    private func deleteLayer(at index: Int) {
        guard index >= 0, index < selectedClips.count else { return }

        selectedClips.remove(at: index)
        sourceBlendIndices.remove(at: index)

        if selectedClips.isEmpty {
            // Always maintain at least one source
            selectedClips = [nil]
            sourceBlendIndices = [0]
            currentSourceIndex = 0
            _ = nextCandidateForCurrentSource()
            return
        }

        // Clamp current source to valid range
        currentSourceIndex = min(currentSourceIndex, selectedClips.count - 1)
    }

    // MARK: - Exclusions

    func excludeCurrentSource() {
        guard let clip = currentCandidateClip else { return }
        library.exclude(file: clip.file)
        nextCandidate()
    }

    // MARK: - Settings reload

    private func applySettings(_ newSettings: Settings) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Update settings + blend modes
            self.settings = newSettings
            self.blendModes = newSettings.blendModes.map { BlendMode(key: $0) }

            // Keep currently active keys if they still exist, else fall back to default.
            let validKeys = self.activeLibraryKeys.filter { newSettings.sourceLibraries[$0] != nil }
            let newActive: Set<String> =
                validKeys.isEmpty ? [newSettings.defaultSourceLibraryKey] : Set(validKeys)

            self.applyActiveLibraries(newActive)
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
        currentClipTimeOffset = nil
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

    // MARK: - Library switching (multi-select)

    func isLibraryActive(key: String) -> Bool {
        activeLibraryKeys.contains(key)
    }

    func toggleLibrary(key: String) {
        // Ignore unknown keys
        guard settings.sourceLibraries[key] != nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            var newKeys = self.activeLibraryKeys

            if newKeys.contains(key) {
                // Turn off, but keep at least one library active.
                if newKeys.count > 1 {
                    newKeys.remove(key)
                } else {
                    // Don't allow zero; fall back to default.
                    newKeys = [self.settings.defaultSourceLibraryKey]
                }
            } else {
                // Turn on
                newKeys.insert(key)
            }

            self.applyActiveLibraries(newKeys)
        }
    }

    func useOnlyDefaultLibrary() {
        let defaultKey = settings.defaultSourceLibraryKey
        DispatchQueue.main.async { [weak self] in
            self?.applyActiveLibraries([defaultKey])
        }
    }

    /// Internal helper to rebuild the underlying VideoSourcesLibrary and reset state.
    private func applyActiveLibraries(_ keys: Set<String>) {
        let folders = settings.folders(forLibraries: keys)

        // Update active libraries + currentLibraryKey
        activeLibraryKeys = keys
        currentLibraryKey = keys.first ?? settings.defaultSourceLibraryKey
        library = VideoSourcesLibrary(sourceFolders: folders)

        // Reset hypnogram layer state to match current settings
        let sourcesCount = max(1, settings.maxSources)
        selectedClips      = Array(repeating: nil, count: sourcesCount)
        sourceBlendIndices = Array(repeating: 0,  count: sourcesCount)
        currentSourceIndex = 0
        currentClipTimeOffset = nil

        _ = nextCandidateForCurrentSource()

        autoPrimeTimer?.invalidate()
        autoPrimeTimer = nil
        if settings.autoPrime {
            autoPrimeNow()
            scheduleAutoPrimeTimer()
        }
    }
}
