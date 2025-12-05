//
//  RenderHooks.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//

import CoreGraphics
import CoreMedia
import CoreImage

// MARK: - Frame Buffer

/// Holds a circular buffer of recent frames for motion-based effects.
final class FrameBuffer {
    private var frames: [CIImage] = []
    private let maxFrames: Int
    private var lastTime: CMTime?
    private let queue = DispatchQueue(label: "FrameBuffer.queue")

    init(maxFrames: Int = 5) {
        self.maxFrames = maxFrames
    }

    func addFrame(_ image: CIImage, at time: CMTime) {
        queue.sync {
            // Detect discontinuity (seek/loop) - clear buffer if time jumps backwards
            if let last = lastTime, time < last {
                // Time went backwards - video looped or seeked
                frames.removeAll()
            }

            lastTime = time
            frames.append(image)
            if frames.count > maxFrames {
                frames.removeFirst()
            }
        }
    }

    /// Get previous frame (offset: 1 = previous, 2 = two frames ago, etc.)
    func previousFrame(offset: Int = 1) -> CIImage? {
        queue.sync {
            let index = frames.count - 1 - offset
            guard index >= 0, index < frames.count else { return nil }
            return frames[index]
        }
    }

    var currentFrame: CIImage? {
        queue.sync {
            frames.last
        }
    }

    /// Check if buffer is filled to minimum capacity
    var isFilled: Bool {
        queue.sync {
            frames.count >= min(3, maxFrames) // Need at least 3 frames for good temporal effects
        }
    }

    /// Number of frames currently in the buffer
    var frameCount: Int {
        queue.sync {
            frames.count
        }
    }

    func clear() {
        queue.sync {
            frames.removeAll()
            lastTime = nil
        }
    }
}

// MARK: - Render Context

/// Per-frame context, used by BOTH preview and export.
struct RenderContext {
    let frameIndex: Int
    let time: CMTime
    let isPreview: Bool
    let outputSize: CGSize

    /// Access to previous frames for motion-based effects
    let frameBuffer: FrameBuffer

    /// Index of the source currently being processed (if any).
    /// - `nil` when rendering the final composed frame or when no specific source is in scope.
    var sourceIndex: Int?

    init(
        frameIndex: Int,
        time: CMTime,
        isPreview: Bool,
        outputSize: CGSize,
        frameBuffer: FrameBuffer,
        sourceIndex: Int? = nil
    ) {
        self.frameIndex = frameIndex
        self.time = time
        self.isPreview = isPreview
        self.outputSize = outputSize
        self.frameBuffer = frameBuffer
        self.sourceIndex = sourceIndex
    }

    /// Convenience for creating a copy with a specific source index.
    func withSourceIndex(_ index: Int?) -> RenderContext {
        var copy = self
        copy.sourceIndex = index
        return copy
    }
}

// MARK: - Render Hook Protocol

/// Hooks: pure functions over (context, image) → image.
protocol RenderHook {
    /// Display name for UI
    var name: String { get }

    /// Apply effect to the current frame
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage
}

extension RenderHook {
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        image
    }
}

// MARK: - Available Effects

/// Namespace for available render effects
enum Effect {
    /// All available effects (None is implicit, represented by nil)
    static let all: [RenderHook] = [
        // Classics
        BlackAndWhiteLowHook(),
        BlackAndWhiteHighHook(),
        HueWobbleHook(),
        RGBSplitSimpleHook(offsetAmount: 15.0, animated: true),
        // VHSDecayHook(intensity: 0.6),

        // New temporal/destructive effects
        // DatamoshHook3(intensity: 0.5, historyDepth: 8),
        GhostBlurHook(intensity: 0.5, trailLength: 6, blurAmount: 8.0),
        LuminanceRemovalHook(mode: .removeDark, threshold: 0.25, softness: 0.15),
        LuminanceRemovalHook(mode: .removeLight, threshold: 0.75, softness: 0.15),
        FrameDifferenceHook(originalBlend: 0.4, boost: 1.5),
        // TemporalSmearHook(intensity: 0.5, lookback: 4),
        ColorEchoHook(channelOffset: 3),
        // EdgeDecayHook(intensity: 0.5),
        // PosterizeDecayHook(levels: 6.0, decayAmount: 0.3),
        // FeedbackLoopHook(scale: 0.96, rotation: 0.01, intensity: 0.4),
        // SolarizeGlitchHook(intensity: 0.6, speed: 0.25)

        // Disabled for now:
        // ScanlinesHook(lineWidth: 6.0, intensity: 0.8),
        // PixelSortHook(intensity: 10.0),
        // DatamoshHook(intensity: 20.0),
        // DatamoshHook2(intensity: 0.6, blurAmount: 4.0, timeScale: 0.02)
    ]

    /// Returns a random effect
    static func random() -> RenderHook? {
        all.randomElement()
    }
}

// MARK: - Render Hook Manager

/// Manager that both preview + export can share.
/// Reads effects and blend modes from the recipe (single source of truth).
/// Provides mutation methods that write back to the recipe via closures.
final class RenderHookManager {
    /// Shared frame buffer that persists across frames
    /// 60 frames at 30fps = 2 seconds of history for temporal effects
    let frameBuffer = FrameBuffer(maxFrames: 60)

    /// Flash solo: when set, only this source index is rendered (others hidden)
    /// Used for brief visual feedback when switching layers in montage mode
    private(set) var flashSoloIndex: Int?

    /// Callback invoked whenever effects or blend modes change (for triggering re-render when paused)
    var onEffectChanged: (() -> Void)?

    // MARK: - Blend Normalization

    /// Whether blend normalization is enabled (for A/B testing)
    var isNormalizationEnabled: Bool = true {
        didSet {
            if oldValue != isNormalizationEnabled {
                onEffectChanged?()
            }
        }
    }

    /// Current normalization strategy (auto-selected by default)
    private var _normalizationStrategy: NormalizationStrategy?

    /// Cached blend mode analysis (recomputed when recipe changes)
    private var cachedAnalysis: BlendModeAnalysis?

    /// Get the active normalization strategy (auto-selects if not manually set)
    /// Returns NoNormalization if normalization is disabled
    var normalizationStrategy: NormalizationStrategy {
        guard isNormalizationEnabled else {
            return NoNormalization()
        }
        if let manual = _normalizationStrategy {
            return manual
        }
        let analysis = currentBlendAnalysis
        return autoSelectNormalization(for: analysis)
    }

    /// Set a specific normalization strategy (nil = auto-select)
    func setNormalizationStrategy(_ strategy: NormalizationStrategy?) {
        _normalizationStrategy = strategy
        onEffectChanged?()
    }

    /// Get current blend mode analysis for the recipe
    var currentBlendAnalysis: BlendModeAnalysis {
        if let cached = cachedAnalysis {
            return cached
        }
        let blendModes = collectBlendModes()
        let analysis = analyzeBlendModes(blendModes)
        cachedAnalysis = analysis
        return analysis
    }

    /// Invalidate cached analysis (call when blend modes change)
    func invalidateBlendAnalysis() {
        cachedAnalysis = nil
    }

    /// Collect all blend modes from current recipe
    private func collectBlendModes() -> [String] {
        guard let recipe = recipeProvider?() else { return [] }
        return recipe.sources.enumerated().map { index, source in
            if index == 0 {
                return BlendMode.sourceOver
            }
            return source.blendMode ?? BlendMode.defaultMontage
        }
    }

    // MARK: - Recipe Access (single source of truth)

    /// Closure to get the current recipe - reads from the single source of truth
    var recipeProvider: (() -> HypnogramRecipe?)?

    /// Closure to update recipe effects
    var effectsSetter: (([RenderHook]) -> Void)?

    /// Closure to update a source's effect at a given index
    var sourceEffectSetter: ((Int, [RenderHook]) -> Void)?

    /// Closure to update a source's blend mode at a given index
    var blendModeSetter: ((Int, String) -> Void)?

    // MARK: - Recipe Effects (reads from recipe, the single source of truth)

    /// Get the current recipe's first effect name (UI currently supports one)
    var globalEffectName: String {
        recipeProvider?()?.effects.first?.name ?? "None"
    }

    func setGlobalEffect(_ effect: RenderHook?) {
        if let effect = effect {
            effectsSetter?([effect])
        } else {
            effectsSetter?([])
        }
        onEffectChanged?()
    }

    func cycleGlobalEffect() {
        // Clear frame buffer so new effect starts fresh (prevents chunkiness)
        frameBuffer.clear()

        // Find current index (-1 means None)
        let currentName = globalEffectName
        let currentIndex = Effect.all.firstIndex { $0.name == currentName } ?? -1
        // Cycle: -1 -> 0 -> 1 -> ... -> count-1 -> -1
        let nextIndex = (currentIndex + 2) % (Effect.all.count + 1) - 1
        setGlobalEffect(nextIndex >= 0 ? Effect.all[nextIndex] : nil)
    }

    // MARK: - Per-Source Effects (reads from recipe sources)

    func sourceEffectName(for sourceIndex: Int) -> String {
        guard let recipe = recipeProvider?(),
              sourceIndex >= 0,
              sourceIndex < recipe.sources.count else {
            return "None"
        }
        return recipe.sources[sourceIndex].effects.first?.name ?? "None"
    }

    func setSourceEffect(_ effect: RenderHook?, for sourceIndex: Int) {
        if let effect = effect {
            sourceEffectSetter?(sourceIndex, [effect])
        } else {
            sourceEffectSetter?(sourceIndex, [])
        }
        onEffectChanged?()
    }

    func cycleSourceEffect(for sourceIndex: Int) {
        let currentName = sourceEffectName(for: sourceIndex)
        let currentIndex = Effect.all.firstIndex { $0.name == currentName } ?? -1
        let nextIndex = (currentIndex + 2) % (Effect.all.count + 1) - 1
        setSourceEffect(nextIndex >= 0 ? Effect.all[nextIndex] : nil, for: sourceIndex)
    }

    // MARK: - Application

    /// Apply recipe effects to the final composed image
    func applyGlobal(to context: inout RenderContext, image: CIImage) -> CIImage {
        // Global effect is not tied to a particular source.
        context.sourceIndex = nil

        guard let recipe = recipeProvider?(), !recipe.effects.isEmpty else {
            // Even if no effect, still update buffer for future use
            frameBuffer.addFrame(image, at: context.time)
            return image
        }

        // Apply all effects in chain (currently UI only sets one)
        var result = image
        for effect in recipe.effects {
            result = effect.willRenderFrame(&context, image: result)
        }

        // Update frame buffer AFTER applying effect
        frameBuffer.addFrame(image, at: context.time)

        return result
    }

    /// Apply per-source effects to a single source image (before compositing)
    func applyToSource(sourceIndex: Int, context: inout RenderContext, image: CIImage) -> CIImage {
        guard let recipe = recipeProvider?(),
              sourceIndex >= 0,
              sourceIndex < recipe.sources.count else {
            return image
        }

        let effects = recipe.sources[sourceIndex].effects
        guard !effects.isEmpty else { return image }

        // Mark which source is being processed so hooks can branch if they want.
        context.sourceIndex = sourceIndex

        var result = image
        for effect in effects {
            result = effect.willRenderFrame(&context, image: result)
        }
        return result
    }

    func clearFrameBuffer() {
        frameBuffer.clear()
    }

    // MARK: - Blend Modes (reads from recipe sources)

    func blendMode(for sourceIndex: Int) -> String {
        // Source 0 is always source-over (base layer)
        if sourceIndex == 0 {
            return BlendMode.sourceOver
        }
        // Read from the recipe (single source of truth)
        guard let recipe = recipeProvider?(),
              sourceIndex >= 0,
              sourceIndex < recipe.sources.count else {
            return BlendMode.defaultMontage
        }
        return recipe.sources[sourceIndex].blendMode ?? BlendMode.defaultMontage
    }

    func setBlendMode(_ mode: String, for sourceIndex: Int, silent: Bool = false) {
        blendModeSetter?(sourceIndex, mode)
        invalidateBlendAnalysis()  // Blend modes changed, recalculate analysis
        if !silent {
            onEffectChanged?()
        }
    }

    func cycleBlendMode(for sourceIndex: Int) {
        // Don't cycle source 0 - it's always source-over
        guard sourceIndex > 0 else { return }

        let currentMode = blendMode(for: sourceIndex)
        let currentIndex = BlendMode.all.firstIndex(of: currentMode) ?? 0
        let nextIndex = (currentIndex + 1) % BlendMode.all.count
        setBlendMode(BlendMode.all[nextIndex], for: sourceIndex)
    }

    // MARK: - Blend Normalization Helpers

    /// Get compensated opacity for a layer (for use during compositing)
    func compensatedOpacity(
        layerIndex: Int,
        totalLayers: Int,
        blendMode: String
    ) -> CGFloat {
        let analysis = currentBlendAnalysis
        return normalizationStrategy.opacityForLayer(
            index: layerIndex,
            totalLayers: totalLayers,
            blendMode: blendMode,
            analysis: analysis
        )
    }

    /// Apply post-composition normalization (call after all layers blended, before global effects)
    func applyNormalization(to image: CIImage) -> CIImage {
        let analysis = currentBlendAnalysis
        return normalizationStrategy.normalizeComposite(image, analysis: analysis)
    }

    // MARK: - Flash Solo

    /// Set flash solo to show only the specified source index
    func setFlashSolo(_ sourceIndex: Int?) {
        // Only trigger effect change if the value actually changed
        guard flashSoloIndex != sourceIndex else { return }
        flashSoloIndex = sourceIndex
        onEffectChanged?()
    }

    /// Check if a given source should be visible (respects flash solo)
    func shouldRenderSource(at sourceIndex: Int) -> Bool {
        guard let soloIndex = flashSoloIndex else {
            return true  // No flash solo active, render all
        }
        return sourceIndex == soloIndex
    }
}

// MARK: - Global Registry

/// Global registry so code that can't be directly injected (e.g. AVVideoCompositing)
/// can still see the current hook manager for this session.
enum GlobalRenderHooks {
    static var manager: RenderHookManager?
}
