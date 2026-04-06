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
    func currentFrameSnapshot() -> CGImage? {
        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            return nil
        }

        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace)
    }

    /// Build export settings on-demand with current player config
    func exportSettings() -> CGSize {
        renderSize(
            aspectRatio: currentDocumentAspectRatio,
            maxDimension: currentDocumentOutputResolution.maxDimension
        )
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

    func save() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Studio: no current frame available for save")
            return
        }

        let hypnogram = makeDisplayHypnogram().copyForExport()
        let compositionID = activePlayer.currentComposition.id

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
        guard !activePlayer.layers.isEmpty else {
            print("Studio: no sources to render.")
            return
        }

        let renderHypnogram = activePlayer.currentComposition.copyForExport()
        let outputSize = exportSettings()

        print("Studio: enqueueing clip with \(renderHypnogram.layers.count) layer(s), duration: \(renderHypnogram.effectiveDuration.seconds)s")

        renderQueue.enqueue(
            composition: renderHypnogram,
            outputFolder: state.settings.outputURL,
            outputSize: outputSize,
            sourceFraming: currentDocumentSourceFraming,
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
                print("Studio: failed to remove local render after Photos save: \(error)")
                AppNotifications.show("Saved to Photos and disk", flash: true, duration: 1.75)
            }
        }
    }

    func saveAs() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Studio: no current frame available for save")
            return
        }

        let hypnogram = makeDisplayHypnogram().copyForExport()
        let compositionID = activePlayer.currentComposition.id
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

    func favoriteCurrentHypnogram() {
        guard !activePlayer.layers.isEmpty else {
            print("Studio: no sources to favorite")
            return
        }

        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            print("Studio: no current frame available for favorite")
            return
        }

        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace) else {
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
