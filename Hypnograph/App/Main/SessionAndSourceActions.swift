//
//  SessionAndSourceActions.swift
//  Hypnograph
//

import Foundation
import CoreGraphics
import CoreImage
import AppKit
import HypnoCore
import HypnoUI

@MainActor
extension Main {
    private func currentFrameSnapshot() -> CGImage? {
        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            return nil
        }

        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace)
    }

    /// Save a JPEG snapshot of the current frame to the snapshots folder.
    /// This is a quick image export action (plain S).
    func saveSnapshotImage() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Main: no current frame available for snapshot")
            AppNotifications.show("No frame available", flash: true)
            return
        }

        let fileManager = FileManager.default
        let outputDirectory = state.settings.snapshotsURL

        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Main: failed to create snapshots directory: \(error)")
            AppNotifications.show("Failed to save snapshot", flash: true)
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let timestamp = formatter.string(from: Date())
        var outputURL = outputDirectory.appendingPathComponent("snapshot-\(timestamp)").appendingPathExtension("jpg")
        var collisionIndex = 2
        while fileManager.fileExists(atPath: outputURL.path) {
            outputURL = outputDirectory.appendingPathComponent("snapshot-\(timestamp)-\(collisionIndex)").appendingPathExtension("jpg")
            collisionIndex += 1
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
            print("Main: failed to encode snapshot as JPEG")
            AppNotifications.show("Failed to save snapshot", flash: true)
            return
        }

        do {
            try jpegData.write(to: outputURL, options: .atomic)
            print("✅ Main: Snapshot saved to \(outputURL.path)")
            AppNotifications.show("Snapshot saved", flash: true)
        } catch {
            print("Main: failed to write snapshot: \(error)")
            AppNotifications.show("Failed to save snapshot", flash: true)
        }
    }

    /// Save current hypnogram: snapshot with embedded recipe (.hypno file)
    /// This is the main save action (Cmd-S)
    func save() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Main: no current frame available for save")
            return
        }

        print("Main: saving hypnogram...")

        // Get the current session with effects library snapshot
        let session = makeDisplaySession().copyForExport()

        // Save as .hypno and record in HypnogramStore (powers Favorites/Recents panel).
        if let entry = HypnogramStore.shared.add(session: session, snapshot: cgImage, isFavorite: false) {
            print("✅ Main: Hypnogram saved to \(entry.sessionURL.path)")
            AppNotifications.show("Hypnogram saved", flash: true)

            // Also save to Apple Photos if write access is available
            if photosIntegrationService.canWrite {
                Task {
                    let success = await photosIntegrationService.saveImage(at: entry.sessionURL)
                    if success {
                        print("✅ Main: Hypnogram added to Apple Photos")
                    }
                }
            }
        } else {
            print("Main: failed to save hypnogram")
            AppNotifications.show("Failed to save", flash: true)
        }
    }

    /// Render and save the hypnogram as a video file (enqueue to render queue)
    /// Available from the menu without a dedicated hotkey.
    func renderAndSaveVideo() {
        guard !activePlayer.layers.isEmpty else {
            print("Main: no sources to render.")
            return
        }

        // Deep copy clip with fresh effect instances to avoid sharing state with preview
        let renderHypnogram = activePlayer.currentHypnogram.copyForExport()

        // Create renderer with current settings (aspect ratio + resolution)
        let outputSize = exportSettings()

        print("Main: enqueueing clip with \(renderHypnogram.layers.count) layer(s), duration: \(renderHypnogram.targetDuration.seconds)s")

        // Enqueue immediately (don't defer - the renderer handles async internally)
        // RenderEngine.ExportQueue provides status messages via onStatusMessage callback
        renderQueue.enqueue(
            clip: renderHypnogram,
            outputFolder: state.settings.outputURL,
            outputSize: outputSize,
            sourceFraming: state.settings.sourceFraming,
            notifyExternalDestinationHooks: false,
            completion: { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleRenderedVideoDestination(result: result)
                }
            }
        )

        // Reset for next hypnogram
        // Defer this to avoid modifying @Published during button action
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.new()
        }
    }

    private func handleRenderedVideoDestination(result: Result<URL, RenderError>) async {
        guard case .success(let outputURL) = result else { return }

        switch state.settings.renderVideoSaveDestination {
        case .diskOnly:
            return

        case .diskAndPhotosIfAvailable:
            guard photosIntegrationService.canWrite else { return }
            let saved = await photosIntegrationService.saveVideo(at: outputURL)
            if !saved {
                AppNotifications.show("Saved to disk (Photos save failed)", flash: true, duration: 2.0)
            }

        case .photosIfAvailableOtherwiseDisk:
            guard photosIntegrationService.canWrite else { return }
            let saved = await photosIntegrationService.saveVideo(at: outputURL)
            guard saved else {
                AppNotifications.show("Saved to disk (Photos save failed)", flash: true, duration: 2.0)
                return
            }

            do {
                try FileManager.default.removeItem(at: outputURL)
                AppNotifications.show("Saved to Apple Photos", flash: true, duration: 1.5)
            } catch {
                print("Main: failed to remove local render after Photos save: \(error)")
                AppNotifications.show("Saved to Photos and disk", flash: true, duration: 1.75)
            }
        }
    }

    /// Save hypnogram to a specific location (with file picker)
    func saveAs() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Main: no current frame available for save")
            return
        }

        let session = makeDisplaySession().copyForExport()
        SessionFileActions.saveAs(session: session, snapshot: cgImage) {
            AppNotifications.show("Hypnogram saved", flash: true)
        }
    }

    /// Open a .hypno or .hypnogram recipe file
    func openRecipe() {
        SessionFileActions.openSession(
            onLoaded: { [weak self] session in
                self?.appendSessionToHistory(session)
                AppNotifications.show("Recipe loaded", flash: true)
            },
            onFailure: {
                AppNotifications.show("Failed to load recipe", flash: true)
            }
        )
    }

    private func appendLoadedHypnograms(_ hypnograms: [Hypnogram]) {
        let oldCount = activePlayer.session.hypnograms.count
        activePlayer.session.hypnograms.append(contentsOf: hypnograms)
        activePlayer.currentHypnogramIndex = oldCount
        activePlayer.currentSourceIndex = -1
        activePlayer.notifySessionMutated()
        enforceHistoryLimit()
        applyClipSelectionChanged(manual: true)
    }

    /// Load a recipe into the current player.
    /// Loaded clips are always appended to history.
    func appendSessionToHistory(_ session: HypnographSession) {
        // Ensure effect chains have names (required for library matching)
        var mutableSession = session
        mutableSession.ensureEffectChainNames()

        // Ensure we're editing the preview deck
        liveMode = .edit

        let loadedHypnograms = mutableSession.hypnograms
        guard !loadedHypnograms.isEmpty else { return }

        // Import effect chains used in the recipe into the session
        // (adds missing chains, replaces same-named chains with recipe versions)
        EffectChainLibraryActions.importChainsFromSession(mutableSession, into: effectsSession)

        appendLoadedHypnograms(loadedHypnograms)
    }

    /// Favorite the current hypnogram (save to store as favorite)
    func favoriteCurrentHypnogram() {
        guard !activePlayer.layers.isEmpty else {
            print("Main: no sources to favorite")
            return
        }

        // Grab current frame for snapshot
        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            print("Main: no current frame available for favorite")
            return
        }

        // Convert CIImage to CGImage
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace) else {
            print("Main: failed to convert CIImage to CGImage for favorite")
            return
        }

        if let entry = HypnogramStore.shared.add(
            session: makeDisplaySession(),
            snapshot: cgImage,
            isFavorite: true
        ) {
            AppNotifications.show("Added to favorites: \(entry.name)", flash: true)
        }
    }

    // MARK: - Effects

    /// Clear all effects AND reset blend modes to Screen (default)
    func clearAllEffects() {
        activeEffectManager.clearEffect(for: -1)  // Global

        // Get source count from appropriate context
        let sourceCount = isLiveMode
            ? livePlayer.activeLayerCount
            : activePlayer.activeLayerCount

        for i in 0..<sourceCount {
            activeEffectManager.clearEffect(for: i)
            // Reset blend mode on source (keep first one as SourceOver) - only in Edit mode
            if !isLiveMode && i > 0 && i < activePlayer.layers.count {
                activePlayer.layers[i].blendMode = BlendMode.defaultMontage
            }
        }
    }

    // MARK: - Source Management Helpers

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
        if activePlayer.currentSourceIndex == -1 {
            if activePlayer.layers.count == 1 {
                return 0
            }
            return nil
        }
        return activePlayer.currentSourceIndex
    }

    private func curateCurrentSource(_ action: SourceCurationAction) {
        guard let idx = resolveSelectedSourceIndexForCuration() else {
            if activePlayer.layers.isEmpty {
                AppNotifications.show("No layers selected", flash: true, duration: 1.25)
            } else {
                AppNotifications.show("Select a layer (1-9)", flash: true, duration: 1.25)
            }
            return
        }

        guard idx >= 0, idx < activePlayer.layers.count else {
            AppNotifications.show("No layer selected", flash: true, duration: 1.25)
            return
        }

        let file = activePlayer.layers[idx].mediaClip.file

        switch file.source {
        case .url:
            switch action {
            case .excluded:
                state.library.exclude(file: file)
                replaceClip(forSourceIndex: idx)
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
                    replaceClip(forSourceIndex: idx)
                    state.library.removeFromIndex(source: file.source)
                    AppNotifications.show("Photos permission required", flash: true, duration: 1.25)
                }
                return
            }

            if action == .excluded {
                replaceClip(forSourceIndex: idx)
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
