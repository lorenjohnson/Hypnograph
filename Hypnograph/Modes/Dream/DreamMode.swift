//
//  DreamMode.swift
//  Hypnograph
//

import Foundation
import CoreGraphics
import CoreMedia
import Combine
import SwiftUI

enum DreamStyle: String, Codable {
    case montage
    case sequence
}

final class DreamMode: ObservableObject, HypnographMode {
    let state: HypnographState
    let renderQueue: RenderQueue

    @Published var style: DreamStyle = .montage
    @Published var montageRecipe: HypnogramRecipe

    private let montageRenderer: MontageRenderer
    private let sequenceRenderer: SequenceRenderer

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

        self.montageRecipe = HypnogramRecipe(
            sources: [],
            targetDuration: state.settings.outputDuration,
            mode: HypnogramMode(name: .dream)
        )

        self.montageRenderer = MontageRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize
        )

        self.sequenceRenderer = SequenceRenderer(
            outputURL: state.settings.outputURL,
            outputSize: state.settings.outputSize
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
        items.append(.text("Style: \(styleLabel)", order: 23))

        switch style {
        case .montage:
            items.append(.text("Source \(currentDisplayIndex) of \(sourceCount)", order: 25))
            items.append(.text("Blend mode (M): \(currentBlendModeDisplayName())", order: 26))
            items.append(.text("Source Effect (F): \(sourceEffectName)", order: 27))
            items.append(.text("M = Cycle Blend Mode", order: 46))

        case .sequence:
            let totalSecs = sequenceTotalDuration().seconds
            let idx = state.currentSourceIndex
            items.append(.text("Sources: \(sourceCount)", order: 25))
            items.append(.text("Current: \(sourceCount == 0 ? 0 : idx + 1)/\(max(sourceCount, 1))", order: 26))
            items.append(.text(String(format: "Duration: %.1fs", totalSecs), order: 27))
            items.append(.text("Press N for new clip", order: 28))

            if let clip = state.currentClip {
                items.append(.padding(8, order: 29))
                items.append(.text("Source \(idx + 1): \(clip.duration.seconds)s", order: 30))
                items.append(.text("Source Effect: \(state.renderHooks.sourceEffectName(for: idx))", order: 31))
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
            Group {
                switch style {
                case .montage:
                    MontageView(
                        recipe: recipe,
                        outputSize: state.settings.outputSize,
                        currentSourceTime: Binding(
                            get: { state.currentClipTimeOffset },
                            set: { state.currentClipTimeOffset = $0 }
                        )
                    )
                case .sequence:
                    SequenceView(
                        recipe: recipe,
                        outputSize: state.settings.outputSize,
                        currentIndex: state.currentSourceIndex,
                        soloIndex: state.soloSourceIndex
                    )
                }
            }
            .id(style == .montage ? "dream-montage" : "dream-sequence")
        )
    }

    private func makeDisplayRecipe(state: HypnographState) -> HypnogramRecipe {
        switch style {
        case .sequence:
            let total = sequenceTotalDuration()
            let duration = total.seconds > 0 ? total : state.settings.outputDuration
            return HypnogramRecipe(
                sources: state.sources,
                targetDuration: duration,
                mode: HypnogramMode(name: .dream, sourceData: [])
            )

        case .montage:
            var full = montageRecipe
            full.sources = state.sources
            full.targetDuration = state.settings.outputDuration

            guard let soloIdx = state.soloSourceIndex,
                  soloIdx >= 0,
                  soloIdx < full.sources.count
            else {
                return full
            }

            var display = full
            display.sources = [full.sources[soloIdx]]

            if var mode = display.mode {
                if soloIdx < mode.sourceData.count {
                    mode.sourceData = [mode.sourceData[soloIdx]]
                } else {
                    mode.sourceData = [[:]]
                }
                display.mode = mode
            }

            return display
        }
    }

    // MARK: - Lifecycle

    func new() {
        switch style {
        case .montage:
            state.clearSolo()
            state.newRandomHypnogram()
            montageRecipe = HypnogramRecipe(
                sources: [],
                targetDuration: state.settings.outputDuration,
                mode: HypnogramMode(name: .dream)
            )
        case .sequence:
            newRandomSequence()
        }
    }

    func save() {
        switch style {
        case .montage:
            guard var renderRecipe = state.sourcesForRender() else {
                print("DreamMode[montage]: no renderable hypnogram.")
                return
            }

            if var modePayload = montageRecipe.mode {
                modePayload.sourceData.ensureCount(renderRecipe.sources.count)
                modePayload.sourceData = Array(modePayload.sourceData.prefix(renderRecipe.sources.count))
                renderRecipe.mode = modePayload
            } else {
                renderRecipe.mode = HypnogramMode(name: .dream, sourceData: [])
            }

            print("DreamMode[montage]: enqueueing recipe with \(renderRecipe.sources.count) source(s).")
            renderQueue.enqueue(renderer: montageRenderer, recipe: renderRecipe)

            DispatchQueue.main.async {
                self.state.resetForNextHypnogram()
                self.montageRecipe = HypnogramRecipe(
                    sources: [],
                    targetDuration: self.state.settings.outputDuration,
                    mode: HypnogramMode(name: .dream)
                )

                if self.state.settings.watch {
                    self.state.newRandomHypnogram()
                }
            }

        case .sequence:
            guard !state.sources.isEmpty else {
                print("DreamMode[sequence]: no sources to save")
                return
            }

            let total = sequenceTotalDuration()
            let duration = total.seconds > 0 ? total : state.settings.outputDuration

            let recipe = HypnogramRecipe(
                sources: state.sources,
                targetDuration: duration,
                mode: HypnogramMode(name: .dream, sourceData: [])
            )

            print("DreamMode[sequence]: enqueueing sequence with \(state.sources.count) source(s), total duration: \(duration.seconds)s")
            renderQueue.enqueue(renderer: sequenceRenderer, recipe: recipe)

            newRandomSequence()
        }
    }

    // MARK: - Settings

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        state.clearSolo()
        montageRecipe.targetDuration = state.settings.outputDuration

        if style == .sequence {
            newRandomSequence()
        }
    }

    // MARK: - Montage blend modes

    private func blendModeForSourceIndex(_ idx: Int) -> String {
        if idx == 0 { return kBlendModeSourceOver }
        return montageRecipe.modeValue(for: .blendMode, sourceIndex: idx) ?? kBlendModeDefaultMontage
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

        let current = montageRecipe.modeValue(for: .blendMode, sourceIndex: idx)
            ?? kBlendModeDefaultMontage

        let currentIndex = availableBlendModes.firstIndex(of: current) ?? -1
        let next = positiveMod(currentIndex + 1, availableBlendModes.count)

        montageRecipe.setModeValue(
            availableBlendModes[next],
            key: .blendMode,
            sourceIndex: idx,
            modeName: .dream
        )
    }

    // MARK: - Sequence helpers

    private func newRandomSequence() {
        state.resetForNextHypnogram()
        state.clearSolo()

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
