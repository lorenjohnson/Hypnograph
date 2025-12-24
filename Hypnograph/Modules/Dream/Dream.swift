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

    // MARK: - Source Navigation (with flash solo in montage mode, sequence sync)

    private var flashSoloTimer: Timer?

    func nextSource() {
        state.nextSource()
        triggerFlashSoloIfNeeded()
        syncPerformanceDisplayIfSequence()
    }

    func previousSource() {
        state.previousSource()
        triggerFlashSoloIfNeeded()
        syncPerformanceDisplayIfSequence()
    }

    func selectSource(index: Int) {
        state.selectSource(index)
        triggerFlashSoloIfNeeded()
        syncPerformanceDisplayIfSequence()
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

    /// Sync Performance Display to current source when in sequence mode
    private func syncPerformanceDisplayIfSequence() {
        guard mode == .sequence else { return }
        state.performanceDisplay.seekToSource(index: state.currentSourceIndex)
    }

    // MARK: - Effects

    /// Get the appropriate renderHooks based on current mode (Edit vs Live)
    private var activeRenderHooks: RenderHookManager {
        state.isLiveMode ? state.performanceDisplay.renderHooks : state.renderHooks
    }

    /// Cycle effect for current layer (global when -1, source when 0+)
    func cycleEffect(direction: Int = 1) {
        state.noteUserInteraction()
        activeRenderHooks.cycleEffect(for: state.currentSourceIndex, direction: direction)
    }

    /// Clear effect for current layer only
    func clearCurrentLayerEffect() {
        state.noteUserInteraction()
        activeRenderHooks.clearEffect(for: state.currentSourceIndex)
    }

    // MARK: - HUD

    func hudItems() -> [HUDItem] {
        var items: [HUDItem] = []

        // Header
        items.append(.text("Hypnograph", order: 10, font: .headline))
        let modeLabel = (mode == .montage ? "Montage" : "Sequence")
        items.append(.text("Dream: \(modeLabel)", order: 11, font: .subheadline))
        items.append(.padding(8, order: 15))

        // Queue status
        if renderQueue.activeJobs > 0 {
            items.append(.text("Queue: \(renderQueue.activeJobs)", order: 20, font: .subheadline))
        } else {
            items.append(.text("Queue: 0", order: 20, font: .caption))
        }
        items.append(.padding(8, order: 21))

        // Layer info (Global or Source X of Y)
        items.append(.text(state.editingLayerDisplay, order: 22))
        items.append(.text("Effect (E): \(activeRenderHooks.effectName(for: state.currentSourceIndex))", order: 23))

        // Source-specific info (only when on a source layer, not global)
        if !state.isOnGlobalLayer {
            switch mode {
            case .montage:
                items.append(.text("Blend mode (M): \(currentBlendModeDisplayName())", order: 26))
            case .sequence:
                let totalSecs = sequenceTotalDuration().seconds
                items.append(.text(String(format: "Duration: %.1fs", totalSecs), order: 26))
                if let clip = state.currentClip {
                    items.append(.text("Clip: \(String(format: "%.1fs", clip.duration.seconds))", order: 27))
                }
            }

            // Favorite status
            if let source = state.currentSource?.clip.file.source,
               FavoriteStore.shared.isFavorited(source) {
                items.append(.text("★ Favorite", order: 29))
            }
        }

        items.append(.padding(16, order: 39))

        // Keyboard hints
        items.append(.text("Shortcuts", order: 40, font: .subheadline))
        items.append(.text("R = Rotate | . = New clip | M = Blend", order: 41))
        items.append(.text("E = Effects | 0 = Global | 1-9 = Source", order: 42))
        items.append(.text("←/→ = Navigate | C = Clear | ⌃⇧C = Clear all", order: 43))
        items.append(.text("N = New | ⇧N = Add source | S = Snapshot", order: 44))
        items.append(.text("` = Toggle Montage/Sequence", order: 45))
        items.append(.text("⇧F/X/D = Favorite/Exclude/Delete", order: 46))

        return items
    }

    // MARK: - Menus

    @ViewBuilder
    func compositionMenu() -> some View {
        Button("Toggle Mode (Montage/Sequence)") { [self] in
            toggleMode()
        }
        .keyboardShortcut("`", modifiers: [])

        Divider()

        Button("Cycle Effect Forward") { [self] in
            cycleEffect(direction: 1)
        }
        .keyboardShortcut("e", modifiers: [.command])

        Button("Cycle Effect Backward") { [self] in
            cycleEffect(direction: -1)
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Add Source") { [self] in
            addSource()
        }
        .keyboardShortcut("n", modifiers: [.shift])

        // Only use arrow shortcuts when effects editor is closed (otherwise they adjust params)
        if !state.isEffectsEditorVisible {
            Button("> Next Source") { [self] in
                nextSource()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("< Previous Source") { [self] in
                previousSource()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
        } else {
            Button("> Next Source") { [self] in
                nextSource()
            }

            Button("< Previous Source") { [self] in
                previousSource()
            }
        }

        ForEach(0..<9, id: \.self) { idx in
            Button("Select Source \(idx + 1)") { [self] in
                selectSource(index: idx)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
        }

        Button("Select Global Layer") { [self] in
            state.selectGlobalLayer()
        }
        .keyboardShortcut("0", modifiers: [])

        Divider()

        Button("Clear Current Layer Effect") { [self] in
            clearCurrentLayerEffect()
        }
        .keyboardShortcut("c", modifiers: [])

        Button("Clear All Effects") { [self] in
            clearAllEffects()
        }
        .keyboardShortcut("c", modifiers: [.control, .shift])

        Divider()

        Button("New Hypnogram") { [self] in
            new()
        }
        .keyboardShortcut("n", modifiers: [])

        Divider()

        Button("Save") { [self] in
            save()
        }
        .keyboardShortcut("s", modifiers: [.command])

        Button("Save Snapshot") { [self] in
            saveSnapshot()
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Divider()

        // Aspect Ratio
        Section("Aspect Ratio") {
            ForEach(AspectRatio.menuPresets, id: \.displayString) { ratio in
                Toggle(ratio.menuLabel, isOn: Binding(
                    get: { [self] in state.aspectRatio == ratio },
                    set: { [self] in if $0 { state.setAspectRatio(ratio) } }
                ))
            }
        }

        // Output Resolution
        Section("Output Resolution") {
            ForEach(OutputResolution.allCases, id: \.self) { resolution in
                Toggle(resolution.displayName, isOn: Binding(
                    get: { [self] in state.outputResolution == resolution },
                    set: { [self] in if $0 { state.setOutputResolution(resolution) } }
                ))
            }
        }
    }

    @ViewBuilder
    func sourceMenu() -> some View {
        Button("Cycle Blend Mode") { [self] in
            cycleBlendMode()
        }
        .keyboardShortcut("m", modifiers: [])

        Divider()

        Button("Rotate 90° Clockwise") { [self] in
            rotateCurrentSource()
        }
        .keyboardShortcut("r", modifiers: [])

        Button("New Random Clip") { [self] in
            newRandomClip()
        }
        .keyboardShortcut(".", modifiers: [])

        Divider()

        Button("Delete") { [self] in
            deleteCurrentSource()
        }
        .keyboardShortcut(.delete, modifiers: [])

        Button("Add to Exclude List") { [self] in
            state.excludeCurrentSource()
        }
        .keyboardShortcut("x", modifiers: [.shift])

        Button("Mark for Deletion") { [self] in
            state.markCurrentSourceForDeletion()
        }
        .keyboardShortcut("d", modifiers: [.shift])

        Button("Toggle Favorite") { [self] in
            state.toggleCurrentSourceFavorite()
        }
        .keyboardShortcut("f", modifiers: [.shift])
    }

    // MARK: - Display

    func makeDisplayView() -> AnyView {
        // In Live mode, mirror the Performance Display player instead of local preview
        if state.isLiveMode {
            return AnyView(
                LiveModePlayerView(performanceDisplay: state.performanceDisplay)
            )
        }

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
                    effectsChangeCounter: state.effectsChangeCounter,
                    renderHooks: state.renderHooks
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
                    playRate: 0.8,
                    renderHooks: state.renderHooks,
                    onSourceIndexChanged: { [weak state] newIndex in
                        // Sync Performance Display when auto-advancing in sequence mode
                        state?.performanceDisplay.seekToSource(index: newIndex)
                    }
                )
                .id("dream-sequence-\(state.sources.count)-\(state.aspectRatio.displayString)-\(state.outputResolution.rawValue)")
            )
        }
    }

    /// Get the current recipe for display (with proper duration set)
    var currentRecipe: HypnogramRecipe {
        makeDisplayRecipe()
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
        // In Live mode, generate directly for performance display without changing edit state
        if state.isLiveMode {
            newForPerformanceDisplay()
            return
        }

        // Clear frame buffer to prevent memory bloat from stored CIImages
        state.renderHooks.clearFrameBuffer()

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

    /// Generate a new random recipe and send directly to performance display
    /// Does NOT modify the edit state
    private func newForPerformanceDisplay() {
        // Clear performance display's frame buffer
        state.performanceDisplay.renderHooks.clearFrameBuffer()

        // Generate a standalone recipe
        let recipe = generateRandomRecipe()

        // Send directly to performance display
        state.performanceDisplay.send(
            recipe: recipe,
            aspectRatio: state.aspectRatio,
            resolution: state.outputResolution,
            mode: mode
        )
    }

    /// Generate a random recipe without modifying state
    private func generateRandomRecipe() -> HypnogramRecipe {
        var sources: [HypnogramSource] = []
        let total = max(1, state.settings.maxSourcesForNew)
        let minCount = min(2, total)
        let count = Int.random(in: minCount...total)

        for i in 0..<max(1, count) {
            guard let clip = state.library.randomClip(clipLength: state.settings.outputDuration.seconds) else {
                continue
            }
            // First source uses SourceOver, rest get random blend modes
            let blendMode = (i == 0) ? BlendMode.sourceOver : BlendMode.random()
            let source = HypnogramSource(clip: clip, blendMode: blendMode)
            sources.append(source)
        }

        return HypnogramRecipe(
            sources: sources,
            targetDuration: state.settings.outputDuration,
            effects: []  // Performance display can have its own effects
        )
    }

    /// Send current hypnogram to performance display
    func sendToPerformanceDisplay() {
        state.performanceDisplay.send(
            recipe: state.recipe,
            aspectRatio: state.aspectRatio,
            resolution: state.outputResolution,
            mode: mode
        )
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
        guard let currentFrame = state.renderHooks.frameBuffer.currentFrame else {
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
            AppNotifications.show("Snapshot saved", flash: true)

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

        // Deep copy recipe with fresh effect instances to avoid sharing state with preview
        var renderRecipe = state.recipe.copyForExport()
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
        let noEffect: RenderHook? = nil
        activeRenderHooks.setGlobalEffect(noEffect)

        // Get source count from appropriate context
        let sourceCount = state.isLiveMode
            ? state.performanceDisplay.activeSourceCount
            : state.activeSourceCount

        for i in 0..<sourceCount {
            activeRenderHooks.setSourceEffect(noEffect, for: i)
            // Reset blend mode on source (keep first one as SourceOver) - only in Edit mode
            if !state.isLiveMode && i > 0 && i < state.sources.count {
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
