//
//  ClipHistoryAndLayerActions.swift
//  Hypnograph
//

import Foundation
import CoreMedia
import Combine
import AVFoundation
import AppKit
import HypnoCore
import HypnoUI

@MainActor
extension Main {
    // MARK: - Clip History Persistence

    func setupClipHistoryPersistence() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveClipHistory(synchronous: true)
                self?.state.settingsStore.save(synchronous: true)
            }
        }

        player.$sessionRevision
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleClipHistorySave()
            }
            .store(in: &clipHistorySaveCancellables)

        player.$currentHypnogramIndex
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleClipHistorySave()
            }
            .store(in: &clipHistorySaveCancellables)
    }

    private func scheduleClipHistorySave() {
        clipHistorySaveTimer?.invalidate()
        clipHistorySaveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveClipHistory(synchronous: false)
            }
        }
    }

    func saveClipHistory(synchronous: Bool) {
        let url = Environment.clipHistoryURL
        let history = ClipHistoryFile(
            hypnograms: player.session.hypnograms,
            currentHypnogramIndex: player.currentHypnogramIndex
        )
        clipHistoryPersistenceService.save(
            history,
            url: url,
            historyLimit: state.settings.historyLimit,
            synchronous: synchronous
        )
    }

    /// Restore persisted clip history (preview deck).
    func restoreClipHistory() {
        if let history = clipHistoryPersistenceService.load(
            url: Environment.clipHistoryURL,
            historyLimit: state.settings.historyLimit
        ),
           !history.hypnograms.isEmpty {
            let session = HypnographSession(hypnograms: history.hypnograms)
            player.session = session
            player.currentHypnogramIndex = history.currentHypnogramIndex
            player.notifySessionMutated()
            player.currentSourceIndex = -1
            player.effectManager.clearFrameBuffer()
            player.notifySessionChanged()
            print("📼 Restored clip history (\(history.hypnograms.count) hypnograms)")
            return
        }

        // Default: start a fresh history with one generated clip.
        replaceHistoryWithNewClip()
    }

    /// Build export settings on-demand with current player config
    func exportSettings() -> CGSize {
        let outputSize = renderSize(
            aspectRatio: activePlayer.config.aspectRatio,
            maxDimension: activePlayer.config.playerResolution.maxDimension
        )
        return outputSize
    }

    // MARK: - Shared helpers

    private var sourceCount: Int { activePlayer.activeLayerCount }

    private var currentDisplayIndex: Int {
        sourceCount > 0 ? activePlayer.currentSourceIndex + 1 : 0
    }

    var currentClipIndicatorText: String {
        let clips = player.session.hypnograms
        guard !clips.isEmpty else { return "Clip --" }
        let displayIndex = max(0, min(player.currentHypnogramIndex, clips.count - 1)) + 1
        return "Clip \(displayIndex)"
    }

    var isLoopCurrentClipEnabled: Bool {
        state.settings.playbackEndBehavior == .loopCurrentClip
    }

    var timelinePlaybackRate: Double {
        get { Self.normalizedTimelinePlaybackRate(state.settings.timelinePlaybackRate) }
        set {
            let normalized = Self.normalizedTimelinePlaybackRate(newValue)
            if abs(normalized - state.settings.timelinePlaybackRate) < 0.0001 {
                return
            }
            state.settingsStore.update { $0.timelinePlaybackRate = normalized }
        }
    }

    /// UI value for a forward-only range control where 0 = normal (1x), 20 = 20x.
    var timelinePlaybackControlValue: Double {
        get { Self.timelineControlValue(fromRate: timelinePlaybackRate) }
        set { timelinePlaybackRate = Self.timelineRate(fromControlValue: newValue, reverse: isTimelinePlaybackReverse) }
    }

    var isTimelinePlaybackReverse: Bool {
        get { timelinePlaybackRate < 0 }
        set {
            let magnitude = abs(timelinePlaybackRate)
            let direction = newValue ? -1.0 : 1.0
            timelinePlaybackRate = direction * magnitude
        }
    }

    private var timelinePlaybackDirection: Int {
        timelinePlaybackRate < 0 ? -1 : 1
    }

    private static func normalizedTimelinePlaybackRate(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        let direction = value < 0 ? -1.0 : 1.0
        let magnitude = min(max(abs(value), 1.0), 20.0)
        return direction * magnitude
    }

    private static func timelineControlValue(fromRate rate: Double) -> Double {
        let normalized = normalizedTimelinePlaybackRate(rate)
        let magnitude = abs(normalized)
        let position = ((magnitude - 1.0) / 19.0) * 20.0
        return min(max(position, 0.0), 20.0)
    }

    private static func timelineRate(fromControlValue value: Double, reverse: Bool) -> Double {
        let clamped = min(max(value, 0.0), 20.0)
        let magnitude = 1.0 + (clamped / 20.0) * 19.0
        return (reverse ? -1.0 : 1.0) * magnitude
    }

    // MARK: - Clip History

    private func makeRandomClip(preservingGlobalEffectFrom previous: Hypnogram?) -> Hypnogram {
        let clipLengthMin = max(0.1, state.settings.clipLengthMinSeconds)
        let clipLengthMax = max(clipLengthMin, state.settings.clipLengthMaxSeconds)
        let clipLengthSeconds = Double.random(in: clipLengthMin...clipLengthMax)
        let targetDuration = CMTime(seconds: clipLengthSeconds, preferredTimescale: 600)
        let playRateBounds: ClosedRange<Double> = 0.2...2.0
        let configuredPlayRateMin = min(max(state.settings.clipPlayRateMin, playRateBounds.lowerBound), playRateBounds.upperBound)
        let configuredPlayRateMax = min(max(state.settings.clipPlayRateMax, playRateBounds.lowerBound), playRateBounds.upperBound)
        let playRateMin = min(configuredPlayRateMin, configuredPlayRateMax)
        let playRateMax = max(configuredPlayRateMin, configuredPlayRateMax)
        let selectedPlayRate: Float = {
            guard playRateMax > playRateMin else { return Float(playRateMin) }
            let randomRate = Double.random(in: playRateMin...playRateMax)
            let steppedRate = (randomRate * 10).rounded() / 10
            return Float(min(max(steppedRate, playRateBounds.lowerBound), playRateBounds.upperBound))
        }()

        let maxLayers = max(1, player.config.maxLayers)
        let layerCount = Int.random(in: 1...maxLayers)
        let randomTemplates = effectsLibrarySession.chains.filter { $0.hasEnabledEffects }

        func shouldApplyRandomizedEffect(enabled: Bool, frequency: Double) -> Bool {
            guard enabled else { return false }
            let chance = min(max(frequency, 0), 1)
            guard chance > 0 else { return false }
            return Double.random(in: 0...1) < chance
        }

        func randomTemplateChain() -> EffectChain? {
            guard let template = randomTemplates.randomElement() else { return nil }
            return EffectChain(duplicating: template, sourceTemplateId: template.id)
        }

        var globalEffectChain = previous?.effectChain.clone()
        if shouldApplyRandomizedEffect(
            enabled: state.settings.randomGlobalEffect,
            frequency: state.settings.randomGlobalEffectFrequency
        ) {
            globalEffectChain = randomTemplateChain() ?? globalEffectChain
        }

        var layers: [HypnogramLayer] = []
        layers.reserveCapacity(layerCount)

        for i in 0..<layerCount {
            guard let mediaClip = state.library.randomClip(clipLength: targetDuration.seconds) else { continue }
            let blendMode = (i == 0) ? BlendMode.sourceOver : BlendMode.defaultMontage
            let layerEffectChain: EffectChain
            if shouldApplyRandomizedEffect(
                enabled: state.settings.randomLayerEffect,
                frequency: state.settings.randomLayerEffectFrequency
            ) {
                layerEffectChain = randomTemplateChain() ?? EffectChain()
            } else {
                layerEffectChain = EffectChain()
            }

            layers.append(
                HypnogramLayer(
                    mediaClip: mediaClip,
                    blendMode: blendMode,
                    effectChain: layerEffectChain
                )
            )
        }

        return Hypnogram(
            layers: layers,
            targetDuration: targetDuration,
            playRate: selectedPlayRate,
            effectChain: globalEffectChain,
            createdAt: Date()
        )
    }

    func enforceHistoryLimit() {
        let limit = max(1, state.settings.historyLimit)
        let overflow = max(0, player.session.hypnograms.count - limit)
        guard overflow > 0 else { return }

        player.session.hypnograms.removeFirst(overflow)
        player.currentHypnogramIndex = max(0, player.currentHypnogramIndex - overflow)
        player.notifySessionMutated()
    }

    func applyClipSelectionChanged(manual: Bool) {
        player.clampCurrentSourceIndex()
        player.currentClipTimeOffset = nil
        player.effectManager.clearFrameBuffer()
        player.effectManager.invalidateBlendAnalysis()
        player.notifySessionChanged()

        if manual {
            flashClipHistoryIndicator()
        }
    }

    func replaceHistoryWithNewClip() {
        let hypnogram = makeRandomClip(preservingGlobalEffectFrom: nil)
        player.session = HypnographSession(hypnograms: [hypnogram])
        player.currentHypnogramIndex = 0
        player.currentSourceIndex = -1
        player.notifySessionMutated()
        applyClipSelectionChanged(manual: false)
    }

    func replaceCurrentClipWithNewClip(manual: Bool = false) {
        let hypnogram = makeRandomClip(preservingGlobalEffectFrom: player.currentHypnogram)
        player.currentHypnogram = hypnogram
        player.currentSourceIndex = -1
        applyClipSelectionChanged(manual: manual)
    }

    func appendNewClipAndSelect(manual: Bool) {
        let hypnogram = makeRandomClip(preservingGlobalEffectFrom: player.currentHypnogram)
        player.session.hypnograms.append(hypnogram)
        player.currentHypnogramIndex = player.session.hypnograms.count - 1
        player.currentSourceIndex = -1
        player.notifySessionMutated()
        enforceHistoryLimit()
        applyClipSelectionChanged(manual: manual)
    }

    @discardableResult
    func advanceOrGenerateOnClipEnded() -> Bool {
        guard state.settings.playbackEndBehavior == .autoAdvance else { return false }

        if timelinePlaybackDirection < 0 {
            let previousIndex = player.currentHypnogramIndex - 1
            guard previousIndex >= 0 else { return false }
            player.currentHypnogramIndex = previousIndex
            applyClipSelectionChanged(manual: false)
            return true
        }

        let nextIndex = player.currentHypnogramIndex + 1
        if nextIndex < player.session.hypnograms.count {
            player.currentHypnogramIndex = nextIndex
            applyClipSelectionChanged(manual: false)
        } else {
            appendNewClipAndSelect(manual: false)
        }
        return true
    }

    func previousClip() {
        guard player.currentHypnogramIndex > 0 else { return }
        player.currentHypnogramIndex -= 1
        applyClipSelectionChanged(manual: true)
    }

    func nextClip() {
        let nextIndex = player.currentHypnogramIndex + 1
        if nextIndex < player.session.hypnograms.count {
            player.currentHypnogramIndex = nextIndex
            applyClipSelectionChanged(manual: true)
        } else {
            // At end of history: treat "next" as "new hypnogram"
            new()
        }
    }

    func deleteCurrentClip() {
        guard !player.session.hypnograms.isEmpty else { return }

        if player.session.hypnograms.count == 1 {
            replaceHistoryWithNewClip()
            applyClipSelectionChanged(manual: true)
            return
        }

        let index = player.currentHypnogramIndex
        player.session.hypnograms.remove(at: index)
        if player.currentHypnogramIndex >= player.session.hypnograms.count {
            player.currentHypnogramIndex = max(0, player.session.hypnograms.count - 1)
        }
        player.notifySessionMutated()
        applyClipSelectionChanged(manual: true)
    }

    func clearClipHistory() {
        let hypnogram = player.currentHypnogram
        player.session = HypnographSession(hypnograms: [hypnogram])
        player.currentHypnogramIndex = 0
        player.notifySessionMutated()
        applyClipSelectionChanged(manual: true)
    }

    private func flashClipHistoryIndicator() {
        guard !player.session.hypnograms.isEmpty else { return }
        clipHistoryIndicatorText = "\(player.currentHypnogramIndex + 1)/\(player.session.hypnograms.count)"

        clipHistoryIndicatorClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.clipHistoryIndicatorText = nil
        }
        clipHistoryIndicatorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    /// Add a source to the given player
    func addSourceToPlayer(_ player: PlayerState, length: Double? = nil) {
        // Use default clip length if not provided
        let clipLength = length ?? player.targetDuration.seconds
        guard let mediaClip = state.library.randomClip(clipLength: clipLength) else { return }
        addSourceToPlayer(player, mediaClip: mediaClip)
    }

    /// Add a specific clip as a new source layer.
    func addSourceToPlayer(_ player: PlayerState, mediaClip: MediaClip) {
        let blendMode = player.layers.isEmpty ? BlendMode.sourceOver : BlendMode.defaultMontage
        let layer = HypnogramLayer(mediaClip: mediaClip, blendMode: blendMode)
        player.layers.append(layer)
        player.currentSourceIndex = player.layers.count - 1
    }

    /// Build a clip from a local file URL (image or video).
    func makeClip(forFileURL url: URL, preferredLength: Double) -> MediaClip? {
        let targetLength = max(0.1, preferredLength)

        let videoAsset = AVURLAsset(url: url)
        let totalVideoSeconds = videoAsset.duration.seconds
        let hasVideoTrack = videoAsset.tracks(withMediaType: .video).first != nil
        if hasVideoTrack, totalVideoSeconds.isFinite, totalVideoSeconds > 0, videoAsset.isPlayable {
            let clipLength = min(targetLength, totalVideoSeconds)
            let source = MediaSource.url(url)
            let file = MediaFile(
                source: source,
                mediaKind: .video,
                duration: CMTime(seconds: totalVideoSeconds, preferredTimescale: 600)
            )
            return MediaClip(
                file: file,
                startTime: .zero,
                duration: CMTime(seconds: clipLength, preferredTimescale: 600)
            )
        }

        guard let image = StillImageCache.ciImage(for: url), !image.extent.isEmpty else {
            return nil
        }

        let source = MediaSource.url(url)
        let imageDuration = CMTime(seconds: targetLength, preferredTimescale: 600)
        let file = MediaFile(source: source, mediaKind: .image, duration: imageDuration)
        return MediaClip(file: file, startTime: .zero, duration: imageDuration)
    }

    /// Build a clip from a Photos asset identifier (image or video).
    func makeClip(forPhotosAssetIdentifier identifier: String, preferredLength: Double) -> MediaClip? {
        guard ApplePhotos.shared.status.canRead else { return nil }
        guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else { return nil }

        let targetLength = max(0.1, preferredLength)
        let source = MediaSource.external(identifier: identifier)

        switch asset.mediaType {
        case .video:
            let totalVideoSeconds = asset.duration
            guard totalVideoSeconds.isFinite, totalVideoSeconds > 0 else { return nil }
            let clipLength = min(targetLength, totalVideoSeconds)
            let file = MediaFile(
                source: source,
                mediaKind: .video,
                duration: CMTime(seconds: totalVideoSeconds, preferredTimescale: 600)
            )
            return MediaClip(
                file: file,
                startTime: .zero,
                duration: CMTime(seconds: clipLength, preferredTimescale: 600)
            )

        case .image:
            let imageDuration = CMTime(seconds: targetLength, preferredTimescale: 600)
            let file = MediaFile(source: source, mediaKind: .image, duration: imageDuration)
            return MediaClip(file: file, startTime: .zero, duration: imageDuration)

        default:
            return nil
        }
    }

    // MARK: - Layer Navigation
    // Note: Flash solo is handled by NSEvent key hold detection in HypnographAppDelegate

    func nextSource() {
        activePlayer.nextSource()
    }

    func previousSource() {
        activePlayer.previousSource()
    }

    func selectSource(index: Int) {
        activePlayer.selectSource(index)
    }

    // MARK: - Layer Trim

    /// Update a specific layer's clip range (video only).
    /// `startSeconds...endSeconds` are absolute offsets within the source media file.
    func setLayerClipRange(
        sourceIndex: Int,
        startSeconds: Double,
        endSeconds: Double,
        maxDurationSeconds: Double? = nil
    ) {
        guard sourceIndex >= 0, sourceIndex < activePlayer.layers.count else { return }

        var layers = activePlayer.layers
        var layer = layers[sourceIndex]
        guard layer.mediaClip.file.mediaKind == .video else { return }

        let totalSeconds = max(0.1, layer.mediaClip.file.duration.seconds)
        let minimumDuration = min(0.1, totalSeconds)
        let maxWindow = max(
            minimumDuration,
            min(totalSeconds, maxDurationSeconds ?? totalSeconds)
        )

        var clampedStart = max(0, min(startSeconds, totalSeconds - minimumDuration))
        var clampedEnd = max(clampedStart + minimumDuration, min(endSeconds, totalSeconds))

        if (clampedEnd - clampedStart) > maxWindow {
            clampedEnd = clampedStart + maxWindow
            if clampedEnd > totalSeconds {
                clampedEnd = totalSeconds
                clampedStart = max(0, clampedEnd - maxWindow)
            }
        }

        let newDuration = min(maxWindow, max(minimumDuration, clampedEnd - clampedStart))

        layer.mediaClip = MediaClip(
            file: layer.mediaClip.file,
            startTime: CMTime(seconds: clampedStart, preferredTimescale: 600),
            duration: CMTime(seconds: newDuration, preferredTimescale: 600)
        )

        layers[sourceIndex] = layer
        activePlayer.layers = layers
        activePlayer.currentClipTimeOffset = nil
    }

    /// Update the currently selected layer's clip range (video only).
    /// `startSeconds...endSeconds` are absolute offsets within the source media file.
    func setCurrentLayerClipRange(
        startSeconds: Double,
        endSeconds: Double,
        maxDurationSeconds: Double? = nil
    ) {
        setLayerClipRange(
            sourceIndex: activePlayer.currentSourceIndex,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            maxDurationSeconds: maxDurationSeconds
        )
    }

    // MARK: - Effects

    /// Cycle effect for current layer (global when -1, source when 0+)
    func cycleEffect(direction: Int = 1) {
        activeEffectManager.cycleEffect(for: activePlayer.currentSourceIndex, direction: direction)

        let effectName = activeEffectManager.effectName(for: activePlayer.currentSourceIndex)
        let layerLabel = activePlayer.currentSourceIndex == -1 ? "Global" : "Source \(activePlayer.currentSourceIndex + 1)"
        AppNotifications.show("\(layerLabel): \(effectName)", flash: true, duration: 1.5)
    }

    /// Clear effect for current layer only
    func clearCurrentLayerEffect() {
        activeEffectManager.clearEffect(for: activePlayer.currentSourceIndex)

        let layerLabel = activePlayer.currentSourceIndex == -1 ? "Global" : "Source \(activePlayer.currentSourceIndex + 1)"
        AppNotifications.show("\(layerLabel): None", flash: true, duration: 1.5)
    }

    // MARK: - MainSettings helpers

    func setAspectRatio(_ ratio: AspectRatio) {
        activePlayer.config.aspectRatio = ratio
        // Config changes are auto-saved via $config subscription
        // Notify Main to update menus
        objectWillChange.send()
    }

    func setOutputResolution(_ resolution: OutputResolution) {
        activePlayer.config.playerResolution = resolution
        // Also update in settings for persistence
        state.settingsStore.update { $0.outputResolution = resolution }
        // Notify Main to update menus
        objectWillChange.send()
    }
}
