//
//  RenderParams.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//

import CoreGraphics
import CoreMedia
import CoreImage

// Parameters hooks can influence and the renderer can read.
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

// Per-frame context, used by BOTH preview and export.
struct RenderContext {
    let frameIndex: Int
    let time: CMTime
    let isPreview: Bool
    let outputSize: CGSize

    var params: RenderParams
}

// Hooks: pure functions over (context, image) → image.
protocol RenderHook {
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage
}

extension RenderHook {
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        image
    }
}

// Manager that both preview + export can share.
final class RenderHookManager {
    public private(set) var hooks: [RenderHook] = []

    func addHook(_ hook: RenderHook) {
        hooks.append(hook)
    }

    func removeAllHooks() {
        hooks.removeAll()
    }

    func apply(to context: inout RenderContext, image: CIImage) -> CIImage {
        hooks.reduce(image) { current, hook in
            hook.willRenderFrame(&context, image: current)
        }
    }
}

// Global registry so code that can't be directly injected (e.g. AVVideoCompositing)
// can still see the current hook manager for this session.
enum GlobalRenderHooks {
    static var manager: RenderHookManager?
}

// Minimal demo hook: wobble hue over time.
struct HueWobbleHook: RenderHook {
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        let t = CMTimeGetSeconds(context.time)
        let phase = Float(sin(t * 0.5))          // slow-ish oscillation
        let angle = phase * .pi                  // radians

        guard let filter = CIFilter(name: "CIHueAdjust") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(angle, forKey: kCIInputAngleKey)

        return filter.outputImage ?? image
    }
}
