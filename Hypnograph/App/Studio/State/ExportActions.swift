//
//  ExportActions.swift
//  Hypnograph
//

import Foundation
import CoreGraphics
import CoreImage
import AppKit
import HypnoCore
import HypnoUI

@MainActor
extension Studio {
    private static let snapshotCIContext = CIContext(
        options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()]
    )

    func currentFrameSnapshot() -> CGImage? {
        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return Self.snapshotCIContext.createCGImage(
            currentFrame,
            from: currentFrame.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    /// Build export settings on-demand with current player config
    func exportSettings() -> CGSize {
        renderSize(
            aspectRatio: currentHypnogramAspectRatio,
            maxDimension: currentHypnogramOutputResolution.maxDimension
        )
    }

    private func makeWorkingHypnogram() -> Hypnogram {
        var hypnogram = self.hypnogram
        let currentCompositionIndex = max(0, min(self.currentCompositionIndex, max(0, hypnogram.compositions.count - 1)))
        hypnogram.currentCompositionIndex = currentCompositionIndex
        return hypnogram
    }

    @discardableResult
    func saveWorkingHypnogram(to url: URL, showSuccessNotification: Bool = true) -> Bool {
        guard let cgImage = currentFrameSnapshot() else {
            print("Studio: no current frame available for sequence save")
            AppNotifications.show("Failed to save sequence", flash: true)
            return false
        }

        let hypnogram = makeWorkingHypnogram().copyForExport()
        guard let savedURL = HypnogramFileStore.save(hypnogram, snapshot: cgImage, to: url) else {
            print("Studio: failed to save sequence")
            AppNotifications.show("Failed to save sequence", flash: true)
            return false
        }

        setActiveWorkingHypnogramURL(savedURL)
        clearUnsavedWorkingHypnogramChanges()
        _ = HypnogramStore.shared.upsertSavedSession(at: savedURL, snapshot: cgImage)

        if showSuccessNotification {
            AppNotifications.show("Saved sequence \(savedURL.lastPathComponent)", flash: true)
        }

        return true
    }

    func saveSnapshotImage() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Studio: no current frame available for snapshot")
            AppNotifications.show("No frame available", flash: true)
            return
        }

        let fileManager = FileManager.default
        let outputDirectory = state.settings.snapshotsURL

        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Studio: failed to create snapshots directory: \(error)")
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
            print("Studio: failed to encode snapshot as JPEG")
            AppNotifications.show("Failed to save snapshot", flash: true)
            return
        }

        do {
            try jpegData.write(to: outputURL, options: .atomic)
            print("✅ Studio: Snapshot saved to \(outputURL.path)")
            AppNotifications.show("Snapshot saved", flash: true)
        } catch {
            print("Studio: failed to write snapshot: \(error)")
            AppNotifications.show("Failed to save snapshot", flash: true)
        }
    }

    func saveComposition() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Studio: no current frame available for save")
            return
        }

        let hypnogram = makeDisplayHypnogram().copyForExport()
        let compositionID = currentComposition.id

        guard let saveURL = currentSaveTargetURL else {
            guard let entry = HypnogramStore.shared.add(hypnogram: hypnogram, snapshot: cgImage, isFavorite: false) else {
                print("Studio: failed to create new hypnogram file")
                AppNotifications.show("Failed to save", flash: true)
                return
            }

            setSaveTargetURL(entry.sessionURL, for: compositionID)
            print("✅ Studio: Created new hypnogram at \(entry.sessionURL.path)")
            AppNotifications.show("Created new hypnogram: \(entry.sessionURL.lastPathComponent)", flash: true)

            if photosIntegrationService.canWrite {
                Task {
                    let success = await photosIntegrationService.saveImage(at: entry.sessionURL)
                    if success {
                        print("✅ Studio: Hypnogram added to Apple Photos")
                    }
                }
            }
            return
        }

        guard let savedURL = HypnogramFileStore.save(hypnogram, snapshot: cgImage, to: saveURL) else {
            print("Studio: failed to save hypnogram")
            AppNotifications.show("Failed to save", flash: true)
            return
        }

        setSaveTargetURL(savedURL, for: compositionID)
        let entry = HypnogramStore.shared.upsertSavedSession(at: savedURL, snapshot: cgImage)
        print("✅ Studio: Hypnogram saved to \(entry.sessionURL.path)")
        AppNotifications.show("Saved \(savedURL.lastPathComponent)", flash: true)

        if photosIntegrationService.canWrite {
            Task {
                let success = await photosIntegrationService.saveImage(at: entry.sessionURL)
                if success {
                    print("✅ Studio: Hypnogram added to Apple Photos")
                }
            }
        }
    }

    func renderAndSaveVideo() {
        guard !currentLayers.isEmpty else {
            print("Studio: no sources to render.")
            return
        }

        let renderHypnogram = currentComposition.copyForExport()
        let outputSize = exportSettings()

        print("Studio: enqueueing clip with \(renderHypnogram.layers.count) layer(s), duration: \(renderHypnogram.effectiveDuration.seconds)s")

        renderQueue.enqueue(
            composition: renderHypnogram,
            outputFolder: state.settings.outputURL,
            outputSize: outputSize,
            sourceFraming: currentHypnogramSourceFraming,
            hypnogramEffectChain: currentHypnogramEffectChain.clone(),
            notifyExternalDestinationHooks: false,
            completion: { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleRenderedVideoDestination(result: result)
                }
            }
        )
    }

    func renderAndSaveSequenceVideo() {
        let renderHypnogram = makeWorkingHypnogram().copyForExport()
        guard !renderHypnogram.compositions.isEmpty else {
            print("Studio: no compositions to render.")
            return
        }

        let outputSize = exportSettings()

        print("Studio: enqueueing sequence with \(renderHypnogram.compositions.count) composition(s), duration: \(renderHypnogram.makeSequenceRenderPlan().totalDuration.seconds)s")

        renderQueue.enqueue(
            hypnogram: renderHypnogram,
            outputFolder: state.settings.outputURL,
            outputSize: outputSize,
            sourceFraming: currentHypnogramSourceFraming,
            notifyExternalDestinationHooks: false,
            completion: { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleRenderedVideoDestination(result: result)
                }
            }
        )
    }

    private func handleRenderedVideoDestination(result: Result<URL, RenderError>) async {
        guard case .success(let outputURL) = result else { return }

        switch state.settings.renderVideoSaveDestination {
        case .diskOnly:
            showRenderedVideoSavedNotification(
                message: "Render complete: \(outputURL.lastPathComponent)",
                revealURL: outputURL
            )
            return

        case .diskAndPhotosIfAvailable:
            guard photosIntegrationService.canWrite else {
                showRenderedVideoSavedNotification(
                    message: "Render complete: \(outputURL.lastPathComponent)",
                    revealURL: outputURL
                )
                return
            }
            let saved = await photosIntegrationService.saveVideo(at: outputURL)
            if !saved {
                showRenderedVideoSavedNotification(
                    message: "Saved to disk (Photos save failed): \(outputURL.lastPathComponent)",
                    revealURL: outputURL
                )
            } else {
                showRenderedVideoSavedNotification(
                    message: "Render complete: \(outputURL.lastPathComponent)",
                    revealURL: outputURL
                )
            }

        case .photosIfAvailableOtherwiseDisk:
            guard photosIntegrationService.canWrite else {
                showRenderedVideoSavedNotification(
                    message: "Render complete: \(outputURL.lastPathComponent)",
                    revealURL: outputURL
                )
                return
            }
            let saved = await photosIntegrationService.saveVideo(at: outputURL)
            guard saved else {
                showRenderedVideoSavedNotification(
                    message: "Saved to disk (Photos save failed): \(outputURL.lastPathComponent)",
                    revealURL: outputURL
                )
                return
            }

            do {
                try FileManager.default.removeItem(at: outputURL)
                AppNotifications.show("Saved to Apple Photos", flash: true, duration: 1.5)
            } catch {
                print("Studio: failed to remove local render after Photos save: \(error)")
                showRenderedVideoSavedNotification(
                    message: "Saved to Photos and disk: \(outputURL.lastPathComponent)",
                    revealURL: outputURL
                )
            }
        }
    }

    private func showRenderedVideoSavedNotification(message: String, revealURL: URL) {
        AppNotifications.show(message, flash: false) {
            NSWorkspace.shared.activateFileViewerSelecting([revealURL])
        }
    }

    func saveCompositionAs() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Studio: no current frame available for save")
            return
        }

        let hypnogram = makeDisplayHypnogram().copyForExport()
        let compositionID = currentComposition.id
        HypnogramFileActions.saveAs(
            hypnogram: hypnogram,
            snapshot: cgImage,
            existingURL: currentSaveTargetURL
        ) { [weak self] savedURL in
            guard let self else { return }
            self.setSaveTargetURL(savedURL, for: compositionID)
            _ = HypnogramStore.shared.upsertSavedSession(at: savedURL, snapshot: cgImage)
            AppNotifications.show("Saved \(savedURL.lastPathComponent)", flash: true)
        }
    }

    func save() {
        if let url = activeWorkingHypnogramURL {
            _ = saveWorkingHypnogram(to: url)
            return
        }

        saveAs()
    }

    func saveAs() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Studio: no current frame available for sequence save")
            AppNotifications.show("Failed to save sequence", flash: true)
            return
        }

        let hypnogram = makeWorkingHypnogram().copyForExport()
        let wasUsingDefaultHypnogram = isUsingDefaultHypnogram
        HypnogramFileActions.saveAs(
            hypnogram: hypnogram,
            snapshot: cgImage,
            existingURL: activeWorkingHypnogramURL
        ) { [weak self] savedURL in
            guard let self else { return }
            self.setActiveWorkingHypnogramURL(savedURL)
            self.clearUnsavedWorkingHypnogramChanges()
            _ = HypnogramStore.shared.upsertSavedSession(at: savedURL, snapshot: cgImage)
            if wasUsingDefaultHypnogram {
                self.resetPersistedDefaultHypnogramToFreshComposition()
            }
            AppNotifications.show("Saved sequence \(savedURL.lastPathComponent)", flash: true)
        }
    }

    func favoriteCurrentHypnogram() {
        guard !currentLayers.isEmpty else {
            print("Studio: no sources to favorite")
            return
        }

        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            print("Studio: no current frame available for favorite")
            return
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = Self.snapshotCIContext.createCGImage(
            currentFrame,
            from: currentFrame.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            print("Studio: failed to convert CIImage to CGImage for favorite")
            return
        }

        if let entry = HypnogramStore.shared.add(
            hypnogram: makeDisplayHypnogram(),
            snapshot: cgImage,
            isFavorite: true
        ) {
            AppNotifications.show("Added to favorites: \(entry.name)", flash: true)
        }
    }
}
