//
//  HypnographState.swift
//  Hypnograph
//
//  Clean unified state: no “candidate” concept, no mirrors,
//  one authoritative list of HypnogramSource objects.
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import Combine
import CoreMedia
import CoreGraphics

/// Manages the current in-progress hypnogram.
final class HypnographState: ObservableObject {

    // MARK: - Core configuration

    private(set) var settings: Settings

    @Published private(set) var currentLibraryKey: String
    @Published private(set) var activeLibraryKeys: Set<String>

    private(set) var library: VideoSourcesLibrary

    // MARK: - Mode management

    @Published var currentModeType: ModeType = .montage

    // MARK: - Source list

    /// Dense, ordered list of all sources.
    @Published var sources: [HypnogramSource]

    /// Current selection index
    @Published private(set) var currentSourceIndex: Int = 0

    /// Optional playhead offset for scrubbing, applies only on explicit user action.
    @Published var currentClipTimeOffset: CMTime?

    @Published var isHUDVisible: Bool = true

    /// If set, this source is globally solo'd.
    @Published var soloSourceIndex: Int? = nil

    /// Watch mode is not yet implemented but is intended as the sit-back and watch random Hypnograms (perhaps across modes)
    // generate like watching TV. IF it crosses modes it would only randomly select between modes that have a watchable flag set.
    @Published var watchMode: Bool = false

    // Render hooks
    let renderHooks = RenderHookManager()
    var baseRenderParams = RenderParams()

    // Auto-prime timer
    private var watchTimer: Timer?

    // MARK: - Init

    init(settings: Settings) {
        self.settings = settings

        let defaultKey = settings.defaultSourceLibraryKey
        let initialKeys: Set<String> = [defaultKey]
        let initialFolders = settings.folders(forLibraries: initialKeys)

        self.currentLibraryKey = defaultKey
        self.activeLibraryKeys = initialKeys
        self.library = VideoSourcesLibrary(sourceFolders: initialFolders)

        self.sources = []
        self.currentSourceIndex = 0
        self.currentClipTimeOffset = nil

        _ = addSource()    // seed initial source

        if settings.watch {
            newRandomHypnogram()
            scheduleWatchTimer()
        }
    }

    // MARK: - Convenience

    var activeSourceCount: Int { sources.count }

    var currentSource: HypnogramSource? {
        guard currentSourceIndex >= 0, currentSourceIndex < sources.count else { return nil }
        return sources[currentSourceIndex]
    }

    var currentClip: VideoClip? {
        currentSource?.clip
    }


    // MARK: - Rendering

    func sourcesForRender() -> HypnogramRecipe? {
        guard !sources.isEmpty else { return nil }
        return HypnogramRecipe(
            sources: sources,
            targetDuration: settings.outputDuration
        )
    }

    // MARK: - High-level API (for modes)

    /// Add a new source with a random clip.
    @discardableResult
    func addSource(length: Double? = nil) -> HypnogramSource? {
        guard let clip = library.randomClip(clipLength: length ?? settings.outputDuration.seconds)
        else { return nil }

        let newSource = HypnogramSource(clip: clip)

        sources.append(newSource)
        currentSourceIndex = sources.count - 1
        return newSource
    }

    /// Replace the clip for an existing source.
    @discardableResult
    func replaceClip(at index: Int, length: Double? = nil) -> VideoClip? {
        guard index >= 0, index < sources.count else { return nil }
        let duration = length ?? settings.outputDuration.seconds

        guard let newClip = library.randomClip(clipLength: duration) else { return nil }

        var src = sources[index]
        src.clip = newClip
        sources[index] = src
        return newClip
    }

    func replaceClipForCurrentSource() {
        replaceClip(at: currentSourceIndex)
    }

    /// Adjust only the start time of the clip for a source.
    func adjustStartTime(at index: Int, to newStart: CMTime) {
        guard index >= 0, index < sources.count else { return }
        var src = sources[index]
        let clip = src.clip

        let fileDuration = clip.file.duration
        let start = min(newStart.seconds, fileDuration.seconds)
        let remaining = max(0.0, fileDuration.seconds - start)
        guard remaining > 0 else { return }

        let newDuration = min(clip.duration.seconds, remaining)

        src.clip = VideoClip(
            file: clip.file,
            startTime: CMTime(seconds: start, preferredTimescale: clip.startTime.timescale),
            duration: CMTime(seconds: newDuration, preferredTimescale: clip.duration.timescale)
        )
        sources[index] = src
    }

    func selectSource(_ index: Int) {
        guard !sources.isEmpty else { return }
        let clamped = max(0, min(index, sources.count - 1))
        currentSourceIndex = clamped
    }

    func nextSource() {
        guard !sources.isEmpty else { return }
        let next = min(sources.count - 1, currentSourceIndex + 1)
        currentSourceIndex = next
    }

    func previousSource() {
        guard !sources.isEmpty else { return }
        let prev = max(0, currentSourceIndex - 1)
        currentSourceIndex = prev
    }

    func deleteSource(at index: Int) {
        guard index >= 0, index < sources.count else { return }
        sources.remove(at: index)
        currentSourceIndex = min(currentSourceIndex, max(0, sources.count - 1))

        if sources.isEmpty {
            _ = addSource()
        }

        // If the solo index is now out of range, clear it.
        if let solo = soloSourceIndex, solo >= sources.count {
            soloSourceIndex = nil
        }
    }

    func deleteCurrentSource() {
        deleteSource(at: currentSourceIndex)
    }

    // MARK: - Solo

    /// Toggle solo for a specific source index.
    /// If the same index is already solo'd, this clears solo.
    /// If another index is solo'd, this switches solo to the new index.
    func soloSource(index: Int) {
        guard !sources.isEmpty else {
            soloSourceIndex = nil
            return
        }
        let clamped = max(0, min(index, sources.count - 1))
        if soloSourceIndex == clamped {
            soloSourceIndex = nil
        } else {
            soloSourceIndex = clamped
        }
    }

    /// Explicitly clear solo regardless of which source was solo'd.
    func clearSolo() {
        soloSourceIndex = nil
    }

    // MARK: - Priming

    func toggleHUD() {
        isHUDVisible.toggle()
    }

    func toggleWatchMode() {
        watchMode.toggle()
    }

    func excludeCurrentSource() {
        guard let clip = currentClip else { return }
        library.exclude(file: clip.file)
        replaceClipForCurrentSource()
    }

    /// Simple reset used by modes that want a clean slate.
    func resetForNextHypnogram() {
        sources.removeAll()
        currentSourceIndex = 0
        currentClipTimeOffset = nil
        clearSolo()
    }

    func newRandomHypnogram() {
        resetForNextHypnogram()
        let total = max(1, settings.maxSources)
        let minCount = min(2, total)
        let count = Int.random(in: minCount...total)
        for _ in 0..<max(1, count) {
            _ = addSource()
        }
        currentSourceIndex = max(0, sources.count - 1)
    }

    private func noteUserInteraction() {
        scheduleWatchTimer()
    }

    private func scheduleWatchTimer() {
        guard settings.watch, settings.outputDuration.seconds > 0 else {
            watchTimer?.invalidate()
            watchTimer = nil
            return
        }

        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(
            withTimeInterval: settings.outputDuration.seconds,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.newRandomHypnogram()
            self.scheduleWatchTimer()
        }
    }

    // MARK: - Library switching

    func isLibraryActive(key: String) -> Bool {
        activeLibraryKeys.contains(key)
    }

    func toggleLibrary(key: String) {
        guard settings.sourceLibraries[key] != nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            var keys = self.activeLibraryKeys

            if keys.contains(key) {
                if keys.count > 1 { keys.remove(key) }
                else { keys = [self.settings.defaultSourceLibraryKey] }
            } else {
                keys.insert(key)
            }

            self.applyActiveLibraries(keys)
        }
    }

    func useOnlyDefaultLibrary() {
        let defaultKey = settings.defaultSourceLibraryKey
        DispatchQueue.main.async { [weak self] in
            self?.applyActiveLibraries([defaultKey])
        }
    }

    private func applyActiveLibraries(_ keys: Set<String>) {
        let folders = settings.folders(forLibraries: keys)
        activeLibraryKeys = keys
        currentLibraryKey = keys.first ?? settings.defaultSourceLibraryKey
        library = VideoSourcesLibrary(sourceFolders: folders)

        sources.removeAll()
        currentSourceIndex = 0
        currentClipTimeOffset = nil
        clearSolo()

        _ = addSource()

        watchTimer?.invalidate()
        watchTimer = nil
        if settings.watch {
            newRandomHypnogram()
            scheduleWatchTimer()
        }
    }

    /// Reload settings from disk and reapply basic configuration.
    func reloadSettings(from url: URL) {
        do {
            let newSettings = try SettingsLoader.load(from: url)
            self.settings = newSettings

            // Re-apply active libraries with the new settings
            applyActiveLibraries(activeLibraryKeys)

            // Restart auto-prime timer with new config
            watchTimer?.invalidate()
            watchTimer = nil
            if newSettings.watch {
                newRandomHypnogram()
                scheduleWatchTimer()
            }
        } catch {
            print("⚠️ Failed to reload settings from \(url.path): \(error)")
        }
    }
}

// MARK: - Small helper

private extension Int {
    func positiveMod(_ n: Int) -> Int {
        let r = self % n
        return r >= 0 ? r : r + n
    }
}
