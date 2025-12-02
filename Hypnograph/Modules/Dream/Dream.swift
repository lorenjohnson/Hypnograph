//
//  Dream.swift
//  Hypnograph
//
//  Dream feature: video/image composition with montage and sequence modes.
//

import Foundation
import CoreGraphics
import CoreMedia
import Combine
import SwiftUI
import AVFoundation
import AppKit

enum DreamMode: String, Codable {
    case montage
    case sequence
}

@MainActor
final class Dream: ObservableObject {
    let state: HypnographState
    let renderQueue: RenderQueue

    @Published var mode: DreamMode = .montage

    private let maxSequenceSources: Int = 20
    private let initialSequenceSourceCount: Int = 5

    // MARK: - Init

    init(state: HypnographState, renderQueue: RenderQueue) {
        self.state = state
        self.renderQueue = renderQueue

        // Set up watch timer callback to respect current mode
        state.onWatchTimerFired = { [weak self] in
            self?.new()
        }
    }

    /// Create a renderer on-demand with current settings (aspect ratio + resolution)
    private func makeRenderer(for mode: DreamMode) -> HypnogramRenderer {
        let outputSize = renderSize(
            aspectRatio: state.aspectRatio,
            maxDimension: state.outputResolution.maxDimension
        )
        let strategy: CompositionBuilder.TimelineStrategy = (mode == .montage)
            ? .montage(targetDuration: state.settings.outputDuration)
            : .sequence
        return HypnogramRenderer(
            outputURL: state.settings.outputURL,
            outputSize: outputSize,
            strategy: strategy
        )
    }

    // MARK: - Shared helpers

    private var sourceCount: Int { state.activeSourceCount }

    private var currentDisplayIndex: Int {
        sourceCount > 0 ? state.currentSourceIndex + 1 : 0
    }

    private func sequenceTotalDuration() -> CMTime {
        state.sources.map { $0.clip.duration }.reduce(.zero, +)
    }

    private func preferredClipLength() -> Double? {
        switch mode {
        case .montage:
            return nil
        case .sequence:
            return Double.random(in: 2.0...15.0)
        }
    }

    // MARK: - Mode

    func toggleMode() {
        state.noteUserInteraction()
        mode = (mode == .montage) ? .sequence : .montage
    }

    // MARK: - Source Navigation (with flash solo in montage mode)

    private var flashSoloTimer: Timer?

    func nextSource() {
        state.nextSource()
        triggerFlashSoloIfNeeded()
    }

    func previousSource() {
        state.previousSource()
        triggerFlashSoloIfNeeded()
    }

    func selectSource(index: Int) {
        state.selectSource(index)
        triggerFlashSoloIfNeeded()
    }

    private func triggerFlashSoloIfNeeded() {
        // Only flash solo in montage mode and if setting is enabled
        guard mode == .montage else { return }

        // Cancel any existing timer
        flashSoloTimer?.invalidate()

        // Set flash solo to current source
        state.renderHooks.setFlashSolo(state.currentSourceIndex)

        // Clear after delay
        flashSoloTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.state.renderHooks.setFlashSolo(nil)
        }
    }

    // MARK: - Effects

    func cycleGlobalEffect() {
        state.noteUserInteraction()
        state.renderHooks.cycleGlobalEffect()
    }

    func cycleSourceEffect() {
        state.noteUserInteraction()
        state.renderHooks.cycleSourceEffect(for: state.currentSourceIndex)
    }

    // MARK: - HUD

    func hudItems() -> [HUDItem] {
        var items: [HUDItem] = []

        let modeLabel = (mode == .montage ? "Montage" : "Sequence")
        items.append(.text("Mode: \(modeLabel)", order: 12, font: .subheadline))
        items.append(.text("Source \(currentDisplayIndex) of \(sourceCount)", order: 25))

        switch mode {
        case .montage:
            items.append(.text("Blend mode (M): \(currentBlendModeDisplayName())", order: 41))

        case .sequence:
            let totalSecs = sequenceTotalDuration().seconds
            items.append(.text(String(format: "Duration: %.1fs", totalSecs), order: 27))

            if let clip = state.currentClip {
                items.append(.padding(8, order: 29))
                items.append(.text("Source \(state.currentSourceIndex + 1): \(clip.duration.seconds)s", order: 41))
            }

            items.append(.text("←/→ = Navigate sources", order: 46))
        }
        items.append(.text("Source Effect (F): \(state.renderHooks.sourceEffectName(for: state.currentSourceIndex))", order: 42))

        // Favorite status
        if let source = state.currentSource?.clip.file.source,
           FavoriteStore.shared.isFavorited(source) {
            items.append(.text("★ Favorite", order: 43))
        }

        items.append(.text("Shift+F = Favorite | Shift+X = Exclude | Shift+D = Delete", order: 44))
        items.append(.text("` = Toggle Montage/Sequence Mode", order: 47))
        return items
    }

    // MARK: - Display

    func makeDisplayView() -> AnyView {
        if mode == .sequence, state.sources.isEmpty {
            newRandomSequence()
        }

        let recipe = makeDisplayRecipe()

        switch mode {
        case .montage:
            return AnyView(
                MontagePlayerView(
                    recipe: recipe,
                    aspectRatio: state.aspectRatio,
                    displayResolution: state.outputResolution,
                    currentSourceIndex: Binding(
                        get: { [state] in state.currentSourceIndex },
                        set: { [state] in state.currentSourceIndex = $0 }
                    ),
                    currentSourceTime: Binding(
                        get: { [state] in state.currentClipTimeOffset },
                        set: { [state] in state.currentClipTimeOffset = $0 }
                    ),
                    isPaused: state.isPaused,
                    effectsChangeCounter: state.effectsChangeCounter
                )
                .id("dream-montage-\(state.aspectRatio.displayString)-\(state.outputResolution.rawValue)")
            )

        case .sequence:
            return AnyView(
                SequencePlayerView(
                    recipe: recipe,
                    aspectRatio: state.aspectRatio,
                    displayResolution: state.outputResolution,
                    currentSourceIndex: Binding(
                        get: { [state] in state.currentSourceIndex },
                        set: { [state] in state.currentSourceIndex = $0 }
                    ),
                    isPaused: state.isPaused,
                    effectsChangeCounter: state.effectsChangeCounter,
                    playRate: 0.8
                )
                .id("dream-sequence-\(state.sources.count)-\(state.aspectRatio.displayString)-\(state.outputResolution.rawValue)")
            )
        }
    }

    private func makeDisplayRecipe() -> HypnogramRecipe {
        // Use the recipe directly, just adjust target duration based on mode
        var recipe = state.recipe
        switch mode {
        case .montage:
            recipe.targetDuration = state.settings.outputDuration
        case .sequence:
            let total = sequenceTotalDuration()
            recipe.targetDuration = total.seconds > 0 ? total : state.settings.outputDuration
        }
        return recipe
    }

    // MARK: - Lifecycle

    func new() {
        // Clear image cache if it's getting large to prevent memory bloat
        let cacheSize = StillImageCache.cacheSize()
        if cacheSize.ciImages > 30 || cacheSize.cgImages > 30 {
            StillImageCache.clear()
        }

        switch mode {
        case .montage:
            state.newRandomHypnogram()
        case .sequence:
            newRandomSequence()
        }
    }

    func toggleHUD() {
        state.toggleHUD()
    }

    func togglePause() {
        state.togglePause()
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        if mode == .sequence {
            newRandomSequence()
        }
    }

    // Override addSource to use appropriate length for sequence mode
    func addSource() {
        let length = preferredClipLength()
        _ = state.addSource(length: length)
    }

    func newRandomClip() {
        state.replaceClipForCurrentSource()
    }

    func deleteCurrentSource() {
        state.deleteCurrentSource()
    }

    /// Save a snapshot of the current frame from the frame buffer
    func saveSnapshot() {
        // Grab the current frame from the frame buffer (which stores the fully composited frame)
        guard let manager = GlobalRenderHooks.manager,
              let currentFrame = manager.frameBuffer.currentFrame else {
            print("DreamMode: no current frame available for snapshot")
            return
        }

        print("DreamMode: saving snapshot of current frame...")

        // Convert CIImage to CGImage with proper color space
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgImage = context.createCGImage(currentFrame, from: currentFrame.extent, format: .RGBA8, colorSpace: colorSpace) else {
            print("DreamMode: failed to convert CIImage to CGImage")
            return
        }

        // Ensure snapshots folder exists
        let snapshotsURL = state.settings.snapshotsURL
        do {
            try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("DreamMode: failed to create snapshots folder: \(error)")
            return
        }

        // Save to file in snapshots folder
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "hypnograph-snapshot-\(timestamp).png"
        let outputURL = snapshotsURL.appendingPathComponent(filename)

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, kUTTypePNG, 1, nil) else {
            print("DreamMode: failed to create image destination")
            return
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        if CGImageDestinationFinalize(destination) {
            print("✅ DreamMode: Snapshot saved to \(outputURL.path)")
            AppNotifications.show("Snapshot saved")

            // Also save to Apple Photos if write access is available
            if ApplePhotos.shared.status.canWrite {
                Task {
                    let success = await ApplePhotos.shared.saveImage(at: outputURL)
                    if success {
                        print("✅ DreamMode: Snapshot added to Apple Photos")
                    }
                }
            }
        } else {
            print("DreamMode: failed to save snapshot")
        }
    }

    func save() {
        guard !state.recipe.sources.isEmpty else {
            print("Dream[\(mode.rawValue)]: no sources to save.")
            return
        }

        // Copy recipe and set target duration based on mode
        var renderRecipe = state.recipe
        switch mode {
        case .montage:
            renderRecipe.targetDuration = state.settings.outputDuration
        case .sequence:
            let total = sequenceTotalDuration()
            renderRecipe.targetDuration = total.seconds > 0 ? total : state.settings.outputDuration
        }

        // Create renderer with current settings (aspect ratio + resolution)
        let renderer = makeRenderer(for: mode)

        print("Dream[\(mode.rawValue)]: enqueueing recipe with \(renderRecipe.sources.count) source(s), duration: \(renderRecipe.targetDuration.seconds)s")

        // Enqueue immediately (don't defer - the renderer handles async internally)
        renderQueue.enqueue(renderer: renderer, recipe: renderRecipe)

        // Reset for next hypnogram
        // Defer this to avoid modifying @Published during button action
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch self.mode {
            case .montage:
                self.state.resetForNextHypnogram()
                self.state.newRandomHypnogram()  // Always generate new hypnogram after save
            case .sequence:
                self.newRandomSequence()
            }
        }
    }

    // MARK: - Montage blend modes

    private func blendModeForSourceIndex(_ idx: Int) -> String {
        guard idx >= 0, idx < state.sources.count else { return BlendMode.sourceOver }
        return state.sources[idx].blendMode ?? (idx == 0 ? BlendMode.sourceOver : BlendMode.defaultMontage)
    }

    private func currentBlendModeDisplayName() -> String {
        blendModeForSourceIndex(state.currentSourceIndex)
            .replacingOccurrences(of: "CI", with: "")
            .replacingOccurrences(of: "BlendMode", with: "")
    }

    func cycleBlendMode(at index: Int? = nil) {
        state.noteUserInteraction()

        let idx = index ?? state.currentSourceIndex
        guard idx > 0, idx < state.sources.count else { return } // bottom layer stays SourceOver

        // Cycle blend mode - this writes directly to sources via the setter closure
        state.renderHooks.cycleBlendMode(for: idx)
    }

    // MARK: - Transform

    /// Rotate the current source by 90 degrees clockwise
    func rotateCurrentSource() {
        state.noteUserInteraction()
        let idx = state.currentSourceIndex
        guard idx >= 0, idx < state.sources.count else { return }

        // Append a 90-degree clockwise rotation to the transforms array
        let rotation90 = CGAffineTransform(rotationAngle: .pi / 2)
        state.sources[idx].transforms.append(rotation90)
    }

    // MARK: - Effects

    /// Clear all effects AND reset blend modes to Screen (default)
    func clearAllEffects() {
        state.noteUserInteraction()
        state.renderHooks.setGlobalEffect(nil)
        for i in 0..<state.activeSourceCount {
            state.renderHooks.setSourceEffect(nil, for: i)
            // Reset blend mode on source (keep first one as SourceOver)
            if i > 0 {
                state.sources[i].blendMode = BlendMode.defaultMontage
            }
        }
    }

    // MARK: - Sequence helpers

    private func newRandomSequence() {
        state.resetForNextHypnogram()
        let desiredCount = min(initialSequenceSourceCount, maxSequenceSources)
        for _ in 0..<desiredCount {
            let length = Double.random(in: 2.0...15.0)
            state.addSource(length: length)
        }
        state.currentSourceIndex = 0
        print("DreamMode[sequence]: generated sequence with \(state.sources.count) sources, total duration: \(sequenceTotalDuration().seconds)s")
    }
}

// Keep indices positive when wrapping.
private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    guard modulus > 0 else { return 0 }
    let r = value % modulus
    return r >= 0 ? r : r + modulus
}
