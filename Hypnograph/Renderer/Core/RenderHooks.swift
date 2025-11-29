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

// MARK: - Render Parameters

/// Parameters hooks can influence and the renderer can read.
struct RenderParams {
    var seed: UInt64
    var glitchAmount: Float
    var hueShift: Float

    init(
        seed: UInt64 = 0,
        glitchAmount: Float = 0,
        hueShift: Float = 0
    ) {
        self.seed = seed
        self.glitchAmount = glitchAmount
        self.hueShift = hueShift
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

    /// Hook-tunable parameters
    var params: RenderParams

    /// Index of the source currently being processed (if any).
    /// - `nil` when rendering the final composed frame or when no specific source is in scope.
    var sourceIndex: Int?

    init(
        frameIndex: Int,
        time: CMTime,
        isPreview: Bool,
        outputSize: CGSize,
        frameBuffer: FrameBuffer,
        params: RenderParams,
        sourceIndex: Int? = nil
    ) {
        self.frameIndex = frameIndex
        self.time = time
        self.isPreview = isPreview
        self.outputSize = outputSize
        self.frameBuffer = frameBuffer
        self.params = params
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

// MARK: - Effect Registry

/// Registry of all available effects
final class EffectRegistry {
    static let shared = EffectRegistry()

    private init() {}

    /// All available effects (None is implicit, not in this list)
    func allEffects() -> [RenderHook] {
        return [
            BlackAndWhiteLowHook(),
            BlackAndWhiteHighHook(),
            HueWobbleHook(),
            RGBSplitSimpleHook(offsetAmount: 15.0, animated: true),
            ScanlinesHook(lineWidth: 6.0, intensity: 0.8),
            PixelSortHook(intensity: 10.0),
            DatamoshHook(intensity: 20.0),
            DatamoshHook2(intensity: 0.6, blurAmount: 4.0, timeScale: 0.02)
        ]
    }

    /// Get effect by name, or nil for "None"
    func effect(named: String) -> RenderHook? {
        if named == "None" {
            return nil
        }
        return allEffects().first { $0.name == named }
    }

    /// All effect names including "None"
    func allEffectNames() -> [String] {
        return ["None"] + allEffects().map { $0.name }
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
        let names = EffectRegistry.shared.allEffectNames()
        let currentIndex = names.firstIndex(of: globalEffectName) ?? 0
        let nextIndex = (currentIndex + 1) % names.count
        let nextName = names[nextIndex]
        let effect = EffectRegistry.shared.effect(named: nextName)
        setGlobalEffect(effect)
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
        let names = EffectRegistry.shared.allEffectNames()
        let currentName = sourceEffectName(for: sourceIndex)
        let currentIndex = names.firstIndex(of: currentName) ?? 0
        let nextIndex = (currentIndex + 1) % names.count
        let nextName = names[nextIndex]
        let effect = EffectRegistry.shared.effect(named: nextName)
        setSourceEffect(effect, for: sourceIndex)
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
            return kBlendModeSourceOver
        }
        // Read from the recipe (single source of truth)
        guard let recipe = recipeProvider?(),
              sourceIndex >= 0,
              sourceIndex < recipe.sources.count else {
            return kBlendModeDefaultMontage
        }
        return recipe.sources[sourceIndex].blendMode ?? kBlendModeDefaultMontage
    }

    func setBlendMode(_ mode: String, for sourceIndex: Int, silent: Bool = false) {
        blendModeSetter?(sourceIndex, mode)
        if !silent {
            onEffectChanged?()
        }
    }

    func cycleBlendMode(for sourceIndex: Int) {
        // Don't cycle source 0 - it's always source-over
        guard sourceIndex > 0 else { return }

        let modes = [
            "CIScreenBlendMode",
            "CIOverlayBlendMode",
            "CISoftLightBlendMode",
            "CIMultiplyBlendMode",
            "CIDarkenBlendMode",
            "CILightenBlendMode",
        ]
        let currentMode = blendMode(for: sourceIndex)
        let currentIndex = modes.firstIndex(of: currentMode) ?? 0
        let nextIndex = (currentIndex + 1) % modes.count
        setBlendMode(modes[nextIndex], for: sourceIndex)
    }

    // MARK: - Flash Solo

    /// Set flash solo to show only the specified source index
    func setFlashSolo(_ sourceIndex: Int?) {
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
