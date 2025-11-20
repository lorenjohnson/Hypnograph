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

    init(maxFrames: Int = 5) {
        self.maxFrames = maxFrames
    }

    func addFrame(_ image: CIImage) {
        frames.append(image)
        if frames.count > maxFrames {
            frames.removeFirst()
        }
    }

    /// Get previous frame (offset: 1 = previous, 2 = two frames ago, etc.)
    func previousFrame(offset: Int = 1) -> CIImage? {
        let index = frames.count - 1 - offset
        guard index >= 0, index < frames.count else { return nil }
        return frames[index]
    }

    var currentFrame: CIImage? {
        frames.last
    }

    func clear() {
        frames.removeAll()
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

    var params: RenderParams
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
            HueWobbleHook()
            // Add more effects here as they're created
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
/// Manages global effect and per-source effects.
final class RenderHookManager {
    private let frameBuffer = FrameBuffer(maxFrames: 5)

    /// Global effect applied to the final composed image
    private var globalEffect: RenderHook?

    /// Per-source effects (indexed by layer/source index)
    private var sourceEffects: [Int: RenderHook] = [:]

    // MARK: - Global Effect

    var globalEffectName: String {
        globalEffect?.name ?? "None"
    }

    func setGlobalEffect(_ effect: RenderHook?) {
        globalEffect = effect
    }

    func cycleGlobalEffect() {
        let names = EffectRegistry.shared.allEffectNames()
        let currentIndex = names.firstIndex(of: globalEffectName) ?? 0
        let nextIndex = (currentIndex + 1) % names.count
        let nextName = names[nextIndex]
        globalEffect = EffectRegistry.shared.effect(named: nextName)
    }

    // MARK: - Per-Source Effects

    func sourceEffectName(for sourceIndex: Int) -> String {
        sourceEffects[sourceIndex]?.name ?? "None"
    }

    func setSourceEffect(_ effect: RenderHook?, for sourceIndex: Int) {
        sourceEffects[sourceIndex] = effect
    }

    func cycleSourceEffect(for sourceIndex: Int) {
        let names = EffectRegistry.shared.allEffectNames()
        let currentName = sourceEffectName(for: sourceIndex)
        let currentIndex = names.firstIndex(of: currentName) ?? 0
        let nextIndex = (currentIndex + 1) % names.count
        let nextName = names[nextIndex]
        sourceEffects[sourceIndex] = EffectRegistry.shared.effect(named: nextName)
    }

    // MARK: - Application

    /// Apply global effect to the final composed image
    func applyGlobal(to context: inout RenderContext, image: CIImage) -> CIImage {
        // Update frame buffer
        frameBuffer.addFrame(image)

        // Apply global effect if set
        guard let effect = globalEffect else {
            return image
        }

        return effect.willRenderFrame(&context, image: image)
    }

    /// Apply per-source effect to a single source image (before compositing)
    func applyToSource(sourceIndex: Int, context: inout RenderContext, image: CIImage) -> CIImage {
        guard let effect = sourceEffects[sourceIndex] else {
            return image
        }

        return effect.willRenderFrame(&context, image: image)
    }

    func clearFrameBuffer() {
        frameBuffer.clear()
    }
}

// MARK: - Global Registry

/// Global registry so code that can't be directly injected (e.g. AVVideoCompositing)
/// can still see the current hook manager for this session.
enum GlobalRenderHooks {
    static var manager: RenderHookManager?
}
