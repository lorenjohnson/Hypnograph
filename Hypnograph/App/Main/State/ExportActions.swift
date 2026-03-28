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
extension Main {
    private func currentFrameSnapshot() -> CGImage? {
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
            aspectRatio: activePlayer.config.aspectRatio,
            maxDimension: activePlayer.config.playerResolution.maxDimension
        )
    }

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

    func save() {
        guard let cgImage = currentFrameSnapshot() else {
            print("Main: no current frame available for save")
            return
        }

        print("Main: saving hypnogram...")

        let session = makeDisplaySession().copyForExport()

        if let entry = HypnogramStore.shared.add(session: session, snapshot: cgImage, isFavorite: false) {
            print("✅ Main: Hypnogram saved to \(entry.sessionURL.path)")
            AppNotifications.show("Hypnogram saved", flash: true)

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

    func renderAndSaveVideo() {
        guard !activePlayer.layers.isEmpty else {
            print("Main: no sources to render.")
            return
        }

        let renderHypnogram = activePlayer.currentHypnogram.copyForExport()
        let outputSize = exportSettings()

        print("Main: enqueueing clip with \(renderHypnogram.layers.count) layer(s), duration: \(renderHypnogram.targetDuration.seconds)s")

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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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

    func favoriteCurrentHypnogram() {
        guard !activePlayer.layers.isEmpty else {
            print("Main: no sources to favorite")
            return
        }

        guard let currentFrame = activePlayer.effectManager.currentFrame else {
            print("Main: no current frame available for favorite")
            return
        }

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
}
