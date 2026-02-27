//
//  SourcePlaybackState.swift
//  Hypnograph
//

import Foundation
import CoreImage
import AVFoundation
import HypnoCore

extension EffectsStudioViewModel {
    func chooseFileSource() {
        guard let url = sourcePlaybackService.chooseFileSourceURL() else { return }
        loadFileSource(url: url, persist: true)
    }

    func useGeneratedSample() {
        clearToGeneratedSampleSource()
        persistLastSourceSample()
    }

    func loadRandomSource(from library: MediaLibrary, preferredLength: Double = 8.0) {
        guard let clip = library.randomClip(clipLength: preferredLength) else {
            compileLog = "No source available in active libraries for random pick. Using generated sample."
            useGeneratedSample()
            return
        }
        loadMediaClip(clip)
    }

    func restoreInitialSource(from library: MediaLibrary, preferredLength: Double = 8.0) {
        let persisted = settingsStore.value
        guard let kind = persisted.lastSourceKind else {
            loadRandomSource(from: library, preferredLength: preferredLength)
            return
        }

        switch kind {
        case .file:
            guard let path = persisted.lastSourceValue, !path.isEmpty else {
                loadRandomSource(from: library, preferredLength: preferredLength)
                return
            }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                loadRandomSource(from: library, preferredLength: preferredLength)
                return
            }
            loadFileSource(url: url, persist: false)

        case .photos:
            guard let identifier = persisted.lastSourceValue, !identifier.isEmpty else {
                loadRandomSource(from: library, preferredLength: preferredLength)
                return
            }
            loadPhotosSource(identifier: identifier)

        case .sample:
            useGeneratedSample()
        }
    }

    func loadMediaClip(_ clip: MediaClip) {
        Task {
            let result = await sourcePlaybackService.loadMediaClip(clip)
            await MainActor.run {
                switch result {
                case .success(let loaded):
                    switch loaded.kind {
                    case .still(let image):
                        applyLoadedStillImage(image, label: loaded.label) {
                            self.persistSource(file: clip.file)
                        }
                    case .video(let asset):
                        applyLoadedVideoAsset(asset, label: loaded.label) {
                            self.persistSource(file: clip.file)
                        }
                    }

                case .failure(let error):
                    compileLog = error.localizedDescription
                    if clip.file.mediaKind == .video {
                        clearToGeneratedSampleSource()
                    }
                }
            }
        }
    }

    func loadPhotosSource(identifier: String) {
        Task {
            let result = await sourcePlaybackService.loadPhotosSource(identifier: identifier)
            await MainActor.run {
                switch result {
                case .success(let loaded):
                    switch loaded.kind {
                    case .still(let image):
                        applyLoadedStillImage(image, label: loaded.label) {
                            self.persistLastPhotosSource(identifier: identifier)
                        }
                    case .video(let asset):
                        applyLoadedVideoAsset(asset, label: loaded.label) {
                            self.persistLastPhotosSource(identifier: identifier)
                        }
                    }

                case .failure(let error):
                    compileLog = error.localizedDescription
                    if case .photosVideoLoadFailed = error {
                        clearToGeneratedSampleSource()
                    }
                }
            }
        }
    }

    func loadFileSource(url: URL, persist: Bool) {
        switch sourcePlaybackService.loadFileSource(url: url) {
        case .success(let loaded):
            switch loaded.kind {
            case .still(let image):
                applyLoadedStillImage(image, label: loaded.label) {
                    if persist {
                        self.persistLastFileSource(url: url)
                    }
                }

            case .video(let asset):
                applyLoadedVideoAsset(asset, label: loaded.label) {
                    if persist {
                        self.persistLastFileSource(url: url)
                    }
                }
            }

        case .failure(let error):
            compileLog = error.localizedDescription
        }
    }

    func currentSourceImage(time: Double) -> CIImage {
        sourcePlaybackService.currentSourceImage(
            time: time,
            sourceStillImage: sourceStillImage,
            sourceVideoAsset: sourceVideoAsset,
            previewSize: previewSize
        )
    }

    func invalidateVideoFrameCache() {
        sourcePlaybackService.invalidateVideoFrameCache()
    }

    func updatePlaybackLoop() {
        if !isPlaying {
            playbackTask?.cancel()
            playbackTask = nil
            lastPlaybackTickUptimeNs = nil
            return
        }

        if playbackTask != nil {
            return
        }

        lastPlaybackTickUptimeNs = DispatchTime.now().uptimeNanoseconds
        playbackTask = Task { [weak self] in
            let tickDurationNs: UInt64 = 16_666_667
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickDurationNs)
                await MainActor.run {
                    guard let self else { return }
                    guard self.isPlaying else { return }

                    let now = DispatchTime.now().uptimeNanoseconds
                    let last = self.lastPlaybackTickUptimeNs ?? now
                    self.lastPlaybackTickUptimeNs = now

                    let elapsed = Double(now &- last) / 1_000_000_000.0
                    guard elapsed.isFinite, elapsed > 0 else { return }

                    let duration = max(self.timelineDuration, 0.001)
                    var nextTime = self.time + elapsed
                    if nextTime >= duration {
                        nextTime = nextTime.truncatingRemainder(dividingBy: duration)
                    }
                    if !nextTime.isFinite || nextTime < 0 {
                        nextTime = 0
                    }
                    self.time = nextTime
                }
            }
        }
    }

    func updateTimelineDurationFromCurrentSource() {
        if let asset = sourceVideoAsset {
            let duration = asset.duration.seconds
            if duration.isFinite, duration > 0 {
                timelineDuration = duration
            } else {
                timelineDuration = 12
            }
        } else {
            timelineDuration = 12
        }

        let maxTime = max(timelineDuration, 0.001)
        if time >= maxTime {
            time = time.truncatingRemainder(dividingBy: maxTime)
        }
        if !time.isFinite || time < 0 {
            time = 0
        }
    }

    private func clearToGeneratedSampleSource() {
        sourceStillImage = nil
        sourceVideoAsset = nil
        invalidateVideoFrameCache()
        resetPreviewHistory()
        inputSourceLabel = "Generated Sample"
        isPlaying = false
        updateTimelineDurationFromCurrentSource()
        renderPreview()
    }

    private func applyLoadedStillImage(
        _ image: CIImage,
        label: String,
        persist: (() -> Void)? = nil
    ) {
        sourceStillImage = image
        sourceVideoAsset = nil
        invalidateVideoFrameCache()
        resetPreviewHistory()
        inputSourceLabel = label
        persist?()
        isPlaying = false
        updateTimelineDurationFromCurrentSource()
        renderPreview()
    }

    private func applyLoadedVideoAsset(
        _ asset: AVAsset,
        label: String,
        persist: (() -> Void)? = nil
    ) {
        sourceStillImage = nil
        sourceVideoAsset = asset
        invalidateVideoFrameCache()
        resetPreviewHistory()
        inputSourceLabel = label
        persist?()
        isPlaying = true
        updateTimelineDurationFromCurrentSource()
        renderPreview()
    }

    private func persistSource(file: MediaFile) {
        switch file.source {
        case .url(let url):
            persistLastFileSource(url: url)
        case .external(let identifier):
            persistLastPhotosSource(identifier: identifier)
        }
    }

    private func persistLastFileSource(url: URL) {
        settingsStore.update { value in
            value.lastSourceKind = .file
            value.lastSourceValue = url.path
        }
    }

    private func persistLastPhotosSource(identifier: String) {
        settingsStore.update { value in
            value.lastSourceKind = .photos
            value.lastSourceValue = identifier
        }
    }

    private func persistLastSourceSample() {
        settingsStore.update { value in
            value.lastSourceKind = .sample
            value.lastSourceValue = nil
        }
    }
}
