//
//  SourceLayerActions.swift
//  Hypnograph
//

import Foundation
import CoreMedia
import AVFoundation
import HypnoCore
import HypnoUI

@MainActor
extension Studio {
    func addSourceFromRandom() {
        addSource()
    }

    func addSourceFromFilesPanel() {
        guard let selectedURL = panelHostService.chooseSingleMediaFile() else { return }
        _ = addSource(fromFileURL: selectedURL)
    }

    func addSourceFromPhotosPicker() {
        state.showPhotosPickerForAddLayer = true
    }

    /// Create a new composition and add each incoming file as a layer.
    /// Files that cannot be decoded as image/video are skipped.
    @discardableResult
    func addSourcesAsNewComposition(fromFileURLs urls: [URL]) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }

        let preferredLength = targetDuration.seconds
        var layers: [Layer] = []
        var failedCount = 0

        for url in fileURLs {
            guard let mediaClip = makeClip(forFileURL: url, preferredLength: preferredLength) else {
                failedCount += 1
                continue
            }

            let blendMode = layers.isEmpty ? BlendMode.sourceOver : BlendMode.defaultMontage
            layers.append(Layer(mediaClip: mediaClip, blendMode: blendMode))
        }

        guard !layers.isEmpty else {
            AppNotifications.show("Couldn't import selected files", flash: true, duration: 1.5)
            return false
        }

        let compositionEffect = hypnogram.compositions.isEmpty
            ? EffectChain()
            : currentComposition.effectChain.clone()

        var importedComposition = Composition(
            layers: layers,
            targetDuration: targetDuration,
            playRate: playRate,
            effectChain: compositionEffect,
            createdAt: Date()
        )
        importedComposition.syncTargetDurationToLayers()

        hypnogram.compositions.append(importedComposition)
        currentCompositionIndex = hypnogram.compositions.count - 1
        activePlayer.currentLayerIndex = currentLayers.count - 1
        notifyHypnogramMutated()
        enforceDefaultHypnogramCompositionLimit()
        pruneSaveTargetsToCurrentHypnogram()
        applyCompositionSelectionChanged(manual: true)

        let importedCount = currentLayers.count
        if failedCount == 0 {
            AppNotifications.show("Imported \(importedCount) layer\(importedCount == 1 ? "" : "s")", flash: true, duration: 1.5)
        } else {
            AppNotifications.show(
                "Imported \(importedCount), skipped \(failedCount)",
                flash: true,
                duration: 1.75
            )
        }

        return true
    }

    /// Add a source layer from an explicit local file.
    @discardableResult
    func addSource(fromFileURL url: URL) -> Bool {
        guard let mediaClip = makeClip(forFileURL: url, preferredLength: targetDuration.seconds) else {
            AppNotifications.show("Couldn't add source from file", flash: true, duration: 1.5)
            return false
        }
        addSource(mediaClip: mediaClip)
        return true
    }

    /// Add a source layer from an explicit Photos asset identifier.
    @discardableResult
    func addSource(fromPhotosAssetIdentifier identifier: String) -> Bool {
        guard let mediaClip = makeClip(forPhotosAssetIdentifier: identifier, preferredLength: targetDuration.seconds) else {
            AppNotifications.show("Couldn't add source from Photos", flash: true, duration: 1.5)
            return false
        }
        addSource(mediaClip: mediaClip)
        return true
    }

    func randomizeCurrentSource() {
        replaceSourceForCurrentLayer()
    }

    func removeCurrentLayer() {
        let idx = activePlayer.currentLayerIndex
        guard idx >= 0, idx < currentLayers.count else { return }

        if currentLayers.count == 1 {
            replaceSource(atLayerIndex: idx)
            return
        }

        currentLayers.remove(at: idx)

        if idx >= currentLayers.count {
            activePlayer.currentLayerIndex = currentLayers.count - 1
        }
    }

    func duplicateCurrentLayer() {
        let idx = activePlayer.currentLayerIndex
        guard idx >= 0, idx < currentLayers.count else { return }

        let duplicatedLayer = duplicatedLayerWithNewFileID(from: currentLayers[idx])
        let insertIndex = idx + 1
        currentLayers.insert(duplicatedLayer, at: insertIndex)
        activePlayer.currentLayerIndex = insertIndex
    }

    func moveLayer(sourceID: UUID, targetID: UUID) {
        guard sourceID != targetID else { return }

        var layers = currentLayers
        guard let fromIndex = layers.firstIndex(where: { $0.mediaClip.file.id == sourceID }) else { return }
        guard let toIndex = layers.firstIndex(where: { $0.mediaClip.file.id == targetID }) else { return }
        guard fromIndex != toIndex else { return }

        let selectedID: UUID? = {
            let selectedIndex = activePlayer.currentLayerIndex
            guard selectedIndex >= 0, selectedIndex < layers.count else { return nil }
            return layers[selectedIndex].mediaClip.file.id
        }()

        let movedLayer = layers.remove(at: fromIndex)
        var destination = toIndex
        if fromIndex < toIndex {
            destination -= 1
        }
        layers.insert(movedLayer, at: max(0, min(destination, layers.count)))
        currentLayers = layers

        if let selectedID, let newIndex = layers.firstIndex(where: { $0.mediaClip.file.id == selectedID }) {
            selectSource(newIndex)
        }

        notifyHypnogramChanged()
    }

    func moveLayerUp(at index: Int) {
        guard index > 0, index < currentLayers.count else { return }
        moveLayer(from: index, to: index - 1)
    }

    func moveLayerDown(at index: Int) {
        guard index >= 0, index < currentLayers.count - 1 else { return }
        moveLayer(from: index, to: index + 1)
    }

    func deleteLayer(at index: Int) {
        guard index >= 0, index < currentLayers.count else { return }
        activePlayer.currentLayerIndex = index
        removeCurrentLayer()
        notifyHypnogramMutated()
        objectWillChange.send()
    }

    func setLayerBlendMode(at index: Int, blendMode: String) {
        guard index > 0, index < currentLayers.count else { return }
        currentLayers[index].blendMode = blendMode
        notifyHypnogramMutated()
        objectWillChange.send()
    }

    func setLayerOpacity(at index: Int, opacity: Double) {
        guard index >= 0, index < currentLayers.count else { return }
        currentLayers[index].opacity = opacity.clamped(to: 0...1)
        notifyHypnogramMutated()
        objectWillChange.send()
    }

    private func moveLayer(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex else { return }

        var layers = currentLayers
        guard fromIndex >= 0, fromIndex < layers.count else { return }
        guard toIndex >= 0, toIndex < layers.count else { return }

        let movedLayer = layers.remove(at: fromIndex)
        layers.insert(movedLayer, at: toIndex)
        currentLayers = layers
        selectSource(toIndex)
        notifyHypnogramChanged()
    }

    private func duplicatedLayerWithNewFileID(from layer: Layer) -> Layer {
        let sourceFile = layer.mediaClip.file
        let duplicatedFile = MediaFile(
            source: sourceFile.source,
            mediaKind: sourceFile.mediaKind,
            duration: sourceFile.duration
        )
        let duplicatedClip = MediaClip(
            file: duplicatedFile,
            startTime: layer.mediaClip.startTime,
            duration: layer.mediaClip.duration
        )

        var duplicatedLayer = layer
        duplicatedLayer.mediaClip = duplicatedClip
        return duplicatedLayer
    }

    private func replaceSourceForCurrentLayer() {
        let idx = activePlayer.currentLayerIndex
        replaceSource(atLayerIndex: idx)
    }

    func replaceSource(atLayerIndex idx: Int) {
        guard idx >= 0, idx < currentLayers.count else { return }
        guard let mediaClip = state.library.randomClip(clipLength: targetDuration.seconds) else { return }
        currentLayers[idx].mediaClip = mediaClip
    }

    func addSource(length: Double? = nil) {
        let clipLength = length ?? targetDuration.seconds
        guard let mediaClip = state.library.randomClip(clipLength: clipLength) else { return }
        addSource(mediaClip: mediaClip)
    }

    /// Add a specific clip as a new source layer.
    func addSource(mediaClip: MediaClip) {
        let blendMode = currentLayers.isEmpty ? BlendMode.sourceOver : BlendMode.defaultMontage
        let layer = Layer(mediaClip: mediaClip, blendMode: blendMode)
        currentLayers.append(layer)
        activePlayer.currentLayerIndex = currentLayers.count - 1
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
        ApplePhotos.shared.refreshStatus()
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

    func setLayerRange(
        sourceIndex: Int,
        startSeconds: Double,
        endSeconds: Double,
        maxDurationSeconds: Double? = nil
    ) {
        guard sourceIndex >= 0, sourceIndex < currentLayers.count else { return }

        var currentLayers = self.currentLayers
        var layer = currentLayers[sourceIndex]
        let isVideo = layer.mediaClip.file.mediaKind == .video

        let totalSeconds = isVideo
            ? max(0.1, layer.mediaClip.file.duration.seconds)
            : max(
                0.1,
                maxDurationSeconds ?? max(layer.mediaClip.duration.seconds, max(targetDuration.seconds, 20))
            )
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

        if isVideo {
            layer.mediaClip = MediaClip(
                file: layer.mediaClip.file,
                startTime: CMTime(seconds: clampedStart, preferredTimescale: 600),
                duration: CMTime(seconds: newDuration, preferredTimescale: 600)
            )
        } else {
            let updatedFile = MediaFile(
                id: layer.mediaClip.file.id,
                source: layer.mediaClip.file.source,
                mediaKind: .image,
                duration: CMTime(seconds: newDuration, preferredTimescale: 600)
            )
            layer.mediaClip = MediaClip(
                file: updatedFile,
                startTime: .zero,
                duration: CMTime(seconds: newDuration, preferredTimescale: 600)
            )
        }

        currentLayers[sourceIndex] = layer
        self.currentLayers = currentLayers
        activePlayer.currentLayerTimeOffset = nil
    }

    func setCurrentLayerRange(
        startSeconds: Double,
        endSeconds: Double,
        maxDurationSeconds: Double? = nil
    ) {
        setLayerRange(
            sourceIndex: activePlayer.currentLayerIndex,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            maxDurationSeconds: maxDurationSeconds
        )
    }

    func cycleCompositionEffect(direction: Int = 1) {
        activeEffectManager.cycleEffect(for: .composition, direction: direction)

        let effectName = activeEffectManager.effectName(for: .composition)
        AppNotifications.show("Composition: \(effectName)", flash: true, duration: 1.5)
    }

    func cycleCurrentLayerEffect(direction: Int = 1) {
        guard activePlayer.currentLayerIndex >= 0, activePlayer.currentLayerIndex < currentLayers.count else { return }

        activeEffectManager.cycleEffect(for: activePlayer.currentLayerIndex, direction: direction)

        let effectName = activeEffectManager.effectName(for: activePlayer.currentLayerIndex)
        let layerLabel = "Layer \(activePlayer.currentLayerIndex + 1)"
        AppNotifications.show("\(layerLabel): \(effectName)", flash: true, duration: 1.5)
    }

    func clearCompositionEffect() {
        activeEffectManager.clearEffect(for: .composition)
        AppNotifications.show("Composition: None", flash: true, duration: 1.5)
    }

    func clearCurrentLayerEffect() {
        guard activePlayer.currentLayerIndex >= 0, activePlayer.currentLayerIndex < currentLayers.count else { return }

        activeEffectManager.clearEffect(for: activePlayer.currentLayerIndex)

        let layerLabel = "Layer \(activePlayer.currentLayerIndex + 1)"
        AppNotifications.show("\(layerLabel): None", flash: true, duration: 1.5)
    }

    private func blendModeForSourceIndex(_ idx: Int) -> String {
        guard idx >= 0, idx < currentLayers.count else { return BlendMode.sourceOver }
        return currentLayers[idx].blendMode ?? (idx == 0 ? BlendMode.sourceOver : BlendMode.defaultMontage)
    }

    func currentBlendModeDisplayName() -> String {
        blendModeForSourceIndex(activePlayer.currentLayerIndex)
            .replacingOccurrences(of: "CI", with: "")
            .replacingOccurrences(of: "BlendMode", with: "")
    }

    func cycleBlendMode(at index: Int? = nil) {
        let idx = index ?? activePlayer.currentLayerIndex
        guard idx > 0, idx < currentLayers.count else { return }
        activePlayer.effectManager.cycleBlendMode(for: idx)
    }

    func setAspectRatio(_ ratio: AspectRatio) {
        updateHypnogramDocumentSettings { $0.aspectRatio = ratio }
        applyCurrentHypnogramDocumentContextToRuntime()
        notifyHypnogramMutated()
        objectWillChange.send()
    }

    func setOutputResolution(_ resolution: OutputResolution) {
        updateHypnogramDocumentSettings { $0.outputResolution = resolution }
        applyCurrentHypnogramDocumentContextToRuntime()
        notifyHypnogramMutated()
        objectWillChange.send()
    }

    func setSourceFraming(_ framing: SourceFraming) {
        updateHypnogramDocumentSettings { $0.sourceFraming = framing }
        livePlayer.setSourceFraming(framing)
        notifyHypnogramMutated()
        objectWillChange.send()
    }

    func setTransitionStyle(_ style: TransitionRenderer.TransitionType) {
        updateHypnogramDocumentSettings { $0.transitionStyle = style }
        livePlayer.transitionType = currentCompositionTransitionStyle
        notifyHypnogramMutated()
        objectWillChange.send()
    }

    func setTransitionDuration(_ duration: Double) {
        let clampedDuration = min(max(duration, 0.1), 3.0)
        updateHypnogramDocumentSettings { $0.transitionDuration = clampedDuration }
        livePlayer.crossfadeDuration = currentCompositionTransitionDuration
        notifyHypnogramMutated()
        objectWillChange.send()
    }

    func setCurrentCompositionTransitionStyle(_ style: TransitionRenderer.TransitionType?) {
        updateCurrentComposition { $0.transitionStyle = style }
        livePlayer.transitionType = currentCompositionTransitionStyle
        objectWillChange.send()
    }

    func setCurrentCompositionTransitionDuration(_ duration: Double) {
        let clampedDuration = min(max(duration, 0.1), 3.0)
        updateCurrentComposition { $0.transitionDuration = clampedDuration }
        livePlayer.crossfadeDuration = currentCompositionTransitionDuration
        objectWillChange.send()
    }

    func clearCurrentCompositionTransitionDurationOverride() {
        updateCurrentComposition { $0.transitionDuration = nil }
        livePlayer.crossfadeDuration = currentCompositionTransitionDuration
        objectWillChange.send()
    }

    func toggleLayerMute(at index: Int) {
        guard index >= 0, index < currentLayers.count else { return }
        currentLayers[index].isMuted.toggle()
        notifyHypnogramMutated()
    }

    func toggleLayerSolo(at index: Int) {
        if activePlayer.effectManager.flashSoloIndex == index {
            activePlayer.effectManager.setFlashSolo(nil)
        } else {
            activePlayer.effectManager.setFlashSolo(index)
        }
        objectWillChange.send()
    }

    func toggleLayerVisibility(at index: Int) {
        guard index >= 0, index < currentLayers.count else { return }
        let currentOpacity = currentLayers[index].opacity
        currentLayers[index].opacity = currentOpacity <= 0.001 ? 1.0 : 0
        notifyHypnogramMutated()
    }

    /// Exclude current source from library
    func excludeCurrentSource() {
        curateCurrentSource(.excluded)
    }

    func favoriteCurrentSource() {
        curateCurrentSource(.favorited)
    }

    private enum SourceCurationAction {
        case excluded
        case favorited

        var notification: String {
            switch self {
            case .excluded: return "Source excluded"
            case .favorited: return "Favorite added"
            }
        }

        var failureNotification: String {
            switch self {
            case .excluded: return "Failed to exclude source"
            case .favorited: return "Failed to add favorite"
            }
        }
    }

    private func resolveSelectedSourceIndexForCuration() -> Int? {
        return activePlayer.currentLayerIndex
    }

    private func curateCurrentSource(_ action: SourceCurationAction) {
        guard let idx = resolveSelectedSourceIndexForCuration() else {
            if currentLayers.isEmpty {
                AppNotifications.show("No layers selected", flash: true, duration: 1.25)
            } else {
                AppNotifications.show("Select a layer (1-9)", flash: true, duration: 1.25)
            }
            return
        }

        guard idx >= 0, idx < currentLayers.count else {
            AppNotifications.show("No layer selected", flash: true, duration: 1.25)
            return
        }

        let file = currentLayers[idx].mediaClip.file

        switch file.source {
        case .url:
            switch action {
            case .excluded:
                state.library.exclude(file: file)
                replaceSource(atLayerIndex: idx)
            case .favorited:
                state.sourceFavoritesStore.add(file.source)
            }

            AppNotifications.show(action.notification, flash: true)

        case .external(let identifier):
            ApplePhotos.shared.refreshStatus()
            guard ApplePhotos.shared.status.canWrite else {
                if action == .favorited {
                    AppNotifications.show("Photos permission required", flash: true, duration: 1.25)
                } else {
                    replaceSource(atLayerIndex: idx)
                    state.library.removeFromIndex(source: file.source)
                    AppNotifications.show("Photos permission required", flash: true, duration: 1.25)
                }
                return
            }

            if action == .excluded {
                replaceSource(atLayerIndex: idx)
                state.library.removeFromIndex(source: file.source)
            }

            Task {
                let success: Bool
                switch action {
                case .excluded:
                    success = await ApplePhotos.shared.addAssetToExcludedAlbumInHypnographFolder(localIdentifier: identifier)
                case .favorited:
                    success = await ApplePhotos.shared.addAssetToFavoritesAlbumInHypnographFolder(localIdentifier: identifier)
                }

                AppNotifications.show(success ? action.notification : action.failureNotification, flash: true, duration: 1.25)
            }
        }
    }
}
