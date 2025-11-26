//
//  DreamMode.swift
//  Hypnograph
//

import Foundation
import CoreGraphics
import CoreMedia
import Combine
import SwiftUI
import AVFoundation
import AppKit

enum DreamStyle: String, Codable {
    case montage
    case sequence
}

final class DreamMode: HypnographMode {
    let state: HypnographState
    let renderQueue: RenderQueue

    @Published var style: DreamStyle = .montage

    /// Blend modes for montage style, indexed by source index
    @Published private var blendModes: [Int: String] = [:]

    private let montageRenderer: UnifiedRenderer
    private let sequenceRenderer: UnifiedRenderer

    private let availableBlendModes: [String] = [
        "CIScreenBlendMode",
        "CIOverlayBlendMode",
        "CISoftLightBlendMode",
        "CIMultiplyBlendMode",
        "CIDarkenBlendMode",
        "CILightenBlendMode",
    ]

    private let maxSequenceSources: Int = 20
    private let initialSequenceSourceCount: Int = 5

    // MARK: - Init

    init(state: HypnographState, renderQueue: RenderQueue) {
        self.state = state
        self.renderQueue = renderQueue

        self.montageRenderer = UnifiedRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize,
            strategy: .montage(targetDuration: CMTime(seconds: 30, preferredTimescale: 600))
        )

        self.sequenceRenderer = UnifiedRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize,
            strategy: .sequence
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
        switch style {
        case .montage:
            return nil
        case .sequence:
            return Double.random(in: 2.0...15.0)
        }
    }

    // MARK: - Style

    func toggleStyle() {
        style = (style == .montage) ? .sequence : .montage
    }

    // MARK: - HUD

    func hudItems(
        state: HypnographState,
        renderQueue: RenderQueue
    ) -> [HUDItem] {
        var items: [HUDItem] = []

        let styleLabel = (style == .montage ? "Montage" : "Sequence")
        items.append(.text("Style: \(styleLabel)", order: 12, font: .subheadline))
        items.append(.text("Source \(currentDisplayIndex) of \(sourceCount)", order: 25))

        switch style {
        case .montage:
            items.append(.text("Blend mode (M): \(currentBlendModeDisplayName())", order: 41))

        case .sequence:
            let totalSecs = sequenceTotalDuration().seconds
            let idx = state.currentSourceIndex
            items.append(.text("Current: \(sourceCount == 0 ? 0 : idx + 1)/\(max(sourceCount, 1))", order: 26))
            items.append(.text(String(format: "Duration: %.1fs", totalSecs), order: 27))

            if let clip = state.currentClip {
                items.append(.padding(8, order: 29))
                items.append(.text("Source \(idx + 1): \(clip.duration.seconds)s", order: 41))
                items.append(.text("Source Effect: \(state.renderHooks.sourceEffectName(for: idx))", order: 42))
            }

            items.append(.text("←/→ = Navigate sources", order: 46))
        }

        items.append(.text("S = Toggle Montage/Sequence", order: 47))
        return items
    }

    // MARK: - Commands

    func compositionCommands() -> [ModeCommand] {
        [
            ModeCommand(title: "Cycle Blend Mode", key: "m") { [weak self] in
                self?.cycleBlendMode()
            },
            ModeCommand(title: "Toggle Style (Montage/Sequence)", key: "s") { [weak self] in
                self?.toggleStyle()
            }
        ]
    }

    func sourceCommands() -> [ModeCommand] { [] }

    // MARK: - Display

    func makeDisplayView(
        state: HypnographState,
        renderQueue: RenderQueue
    ) -> AnyView {
        if style == .sequence, state.sources.isEmpty {
            newRandomSequence()
        }

        let recipe = makeDisplayRecipe(state: state)

        return AnyView(
            DreamView(
                recipe: recipe,
                style: style,
                outputSize: state.settings.outputSize,
                currentSourceIndex: state.currentSourceIndex,
                currentSourceTime: Binding(
                    get: { state.currentClipTimeOffset },
                    set: { state.currentClipTimeOffset = $0 }
                )
            )
            .id("dream-\(style.rawValue)")
        )
    }

    private func makeDisplayRecipe(state: HypnographState) -> HypnogramRecipe {
        // Both styles use the same recipe structure, just different target durations
        let targetDuration: CMTime
        switch style {
        case .montage:
            targetDuration = state.settings.outputDuration
        case .sequence:
            let total = sequenceTotalDuration()
            targetDuration = total.seconds > 0 ? total : state.settings.outputDuration
        }

        // Build mode payload with blend modes
        let modeData = buildModeData(for: state.sources)

        return HypnogramRecipe(
            sources: state.sources,
            targetDuration: targetDuration,
            mode: HypnogramMode(name: .dream, sourceData: modeData)
        )
    }

    /// Build mode-specific data (blend modes) for the given sources
    private func buildModeData(for sources: [HypnogramSource]) -> [[String: String]] {
        return sources.enumerated().map { index, _ in
            if index == 0 {
                return ["blendMode": kBlendModeSourceOver]
            } else {
                return ["blendMode": blendModes[index] ?? kBlendModeDefaultMontage]
            }
        }
    }

    // MARK: - Lifecycle

    func new() {
        switch style {
        case .montage:
            state.newRandomHypnogram()
            blendModes.removeAll()
        case .sequence:
            newRandomSequence()
        }
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
        } else {
            print("DreamMode: failed to save snapshot")
        }
    }

    func save() {
        // Get the renderable recipe (filters out excluded sources)
        guard var renderRecipe = state.sourcesForRender() else {
            print("DreamMode[\(style.rawValue)]: no renderable hypnogram.")
            return
        }

        // Set target duration based on style
        switch style {
        case .montage:
            renderRecipe.targetDuration = state.settings.outputDuration
        case .sequence:
            let total = sequenceTotalDuration()
            renderRecipe.targetDuration = total.seconds > 0 ? total : state.settings.outputDuration
        }

        // Attach mode-specific data (blend modes)
        let modeData = buildModeData(for: renderRecipe.sources)
        renderRecipe.mode = HypnogramMode(name: .dream, sourceData: modeData)

        // Choose renderer based on style
        let renderer: HypnogramRenderer = (style == .montage) ? montageRenderer : sequenceRenderer

        print("DreamMode[\(style.rawValue)]: enqueueing recipe with \(renderRecipe.sources.count) source(s), duration: \(renderRecipe.targetDuration.seconds)s")

        // Enqueue immediately (don't defer - the renderer handles async internally)
        renderQueue.enqueue(renderer: renderer, recipe: renderRecipe)

        // Reset for next hypnogram
        // Defer this to avoid modifying @Published during button action
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch self.style {
            case .montage:
                self.state.resetForNextHypnogram()
                self.blendModes.removeAll()
                if self.state.settings.watch {
                    self.state.newRandomHypnogram()
                }
            case .sequence:
                self.newRandomSequence()
            }
        }
    }

    // MARK: - Settings

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)

        if style == .sequence {
            newRandomSequence()
        }
    }

    // MARK: - Montage blend modes

    private func blendModeForSourceIndex(_ idx: Int) -> String {
        if idx == 0 { return kBlendModeSourceOver }
        return blendModes[idx] ?? kBlendModeDefaultMontage
    }

    private func currentBlendModeDisplayName() -> String {
        blendModeForSourceIndex(state.currentSourceIndex)
            .replacingOccurrences(of: "CI", with: "")
            .replacingOccurrences(of: "BlendMode", with: "")
    }

    func cycleBlendMode(at index: Int? = nil) {
        guard !availableBlendModes.isEmpty else { return }

        let idx = index ?? state.currentSourceIndex
        guard idx > 0 else { return } // bottom layer stays SourceOver

        let current = blendModes[idx] ?? kBlendModeDefaultMontage
        let currentIndex = availableBlendModes.firstIndex(of: current) ?? -1
        let next = positiveMod(currentIndex + 1, availableBlendModes.count)

        blendModes[idx] = availableBlendModes[next]
    }

    // MARK: - Sequence helpers

    private func newRandomSequence() {
        state.resetForNextHypnogram()

        let desiredCount = min(initialSequenceSourceCount, maxSequenceSources)
        for _ in 0..<desiredCount {
            _ = state.addSource(length: Double.random(in: 2.0...15.0))
        }

        let active = state.activeSourceCount
        let clampedIndex = max(0, min(active - 1, state.currentSourceIndex))
        state.selectSource(clampedIndex)

        print("DreamMode[sequence]: generated sequence with \(state.sources.count) sources, total duration: \(sequenceTotalDuration().seconds)s")
    }
}

// Keep indices positive when wrapping.
private func positiveMod(_ value: Int, _ modulus: Int) -> Int {
    guard modulus > 0 else { return 0 }
    let r = value % modulus
    return r >= 0 ? r : r + modulus
}
