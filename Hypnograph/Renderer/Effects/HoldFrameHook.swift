//
//  HoldFrameHook.swift
//  Hypnograph
//
//  Pseudo-datamosh effect: freezes a frame and accumulates ghostly motion trails
//  over it, creating a smeared/melted look as the video continues playing.
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Pseudo-datamosh effect - freezes a frame and shows ghostly motion trails
/// Combines the best of FrameDifference (visible motion) with temporal accumulation
final class HoldFrameHook: RenderHook {
    var name: String { "Hold Frame" }

    // MARK: - Configuration

    /// Base interval between freezes (seconds)
    let freezeIntervalBase: Double

    /// How long to hold on average (seconds)
    let holdDurationBase: Double

    /// Boost for the motion trails
    let trailBoost: Double

    // MARK: - State

    private var holdFrame: CIImage?
    private var accumulatedTrails: CIImage?
    private var holdStartFrame: Int = -1000
    private var nextFreezeFrame: Int = 90
    private var holdDurationFrames: Int = 0
    private var isHolding: Bool = false
    private var lastFrameIndex: Int = -1
    private var framesSinceFreeze: Int = 0

    private var rng = SystemRandomNumberGenerator()

    // MARK: - Init

    init(
        freezeInterval: Double = 8.0,
        holdDuration: Double = 4.0,
        trailBoost: Double = 1.5
    ) {
        self.freezeIntervalBase = freezeInterval
        self.holdDurationBase = holdDuration
        self.trailBoost = trailBoost
    }

    // MARK: - RenderHook

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        let frameCount = context.frameIndex
        let outputRect = CGRect(origin: .zero, size: context.outputSize)

        // Detect frame counter reset - reset state
        if frameCount < lastFrameIndex {
            print("🔄 HoldFrame: Frame counter reset detected (\(lastFrameIndex) -> \(frameCount))")
            resetState()
        }
        lastFrameIndex = frameCount

        if isHolding {
            framesSinceFreeze += 1

            // Check if hold should end
            if framesSinceFreeze >= holdDurationFrames {
                print("🔓 HoldFrame: Releasing hold at frame \(frameCount) after \(framesSinceFreeze) frames")
                endHold(atFrame: frameCount)
                return image
            }

            guard let frozen = holdFrame else { return image }

            // Compute the accumulated result
            let result = accumulateMotion(frozen: frozen, live: image, outputRect: outputRect)
            return result

        } else {
            // Not holding - check if should freeze
            if frameCount >= nextFreezeFrame {
                startHold(image: image, outputRect: outputRect, atFrame: frameCount)
                print("🔒 HoldFrame: Starting hold at frame \(frameCount), duration = \(holdDurationFrames) frames")
                return holdFrame ?? image
            }

            return image
        }
    }

    // MARK: - State Management

    /// Public reset for RenderHook protocol - clears all state when switching montages
    func reset() {
        resetState()
        lastFrameIndex = -1
        print("🔄 HoldFrame: reset() called - state cleared")
    }

    private func resetState() {
        isHolding = false
        holdFrame = nil
        accumulatedTrails = nil
        holdStartFrame = -1000
        nextFreezeFrame = 60
        framesSinceFreeze = 0
    }

    private func startHold(image: CIImage, outputRect: CGRect, atFrame frame: Int) {
        isHolding = true
        let cropped = image.cropped(to: outputRect)
        holdFrame = cropped
        accumulatedTrails = nil  // Start fresh
        holdStartFrame = frame
        framesSinceFreeze = 0

        // Randomize hold duration (±50%)
        let baseFrames = Int(holdDurationBase * 30)
        let variation = Double.random(in: 0.5...1.5, using: &rng)
        holdDurationFrames = max(30, Int(Double(baseFrames) * variation))
    }

    private func endHold(atFrame frame: Int) {
        isHolding = false
        holdFrame = nil
        accumulatedTrails = nil
        framesSinceFreeze = 0

        // Randomize next freeze interval (±60%)
        let baseFrames = Int(freezeIntervalBase * 30)
        let variation = Double.random(in: 0.4...1.6, using: &rng)
        nextFreezeFrame = frame + max(60, Int(Double(baseFrames) * variation))
    }

    // MARK: - Motion Accumulation

    /// Accumulate motion trails over the frozen frame
    private func accumulateMotion(frozen: CIImage, live: CIImage, outputRect: CGRect) -> CIImage {
        // 1. Compute difference between frozen and current live
        guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else {
            return frozen
        }
        diffFilter.setValue(live, forKey: kCIInputImageKey)
        diffFilter.setValue(frozen, forKey: kCIInputBackgroundImageKey)

        guard let difference = diffFilter.outputImage else {
            return frozen
        }

        // 2. Boost the difference to make it visible
        guard let exposure = CIFilter(name: "CIExposureAdjust") else {
            return frozen
        }
        exposure.setValue(difference, forKey: kCIInputImageKey)
        exposure.setValue(trailBoost, forKey: kCIInputEVKey)

        guard let boostedDiff = exposure.outputImage else {
            return frozen
        }

        // 3. Accumulate trails: blend new difference with previous trails
        let currentTrails: CIImage
        if let previousTrails = accumulatedTrails {
            // Lighten blend: keeps the brighter of previous trails or new motion
            guard let lighten = CIFilter(name: "CILightenBlendMode") else {
                currentTrails = boostedDiff
                accumulatedTrails = currentTrails
                return applyTrailsToFrozen(frozen: frozen, trails: currentTrails, live: live, outputRect: outputRect)
            }
            lighten.setValue(boostedDiff, forKey: kCIInputImageKey)
            lighten.setValue(previousTrails, forKey: kCIInputBackgroundImageKey)

            if let blended = lighten.outputImage {
                // Slight fade on accumulated trails to prevent total blowout
                if let fade = CIFilter(name: "CIExposureAdjust") {
                    fade.setValue(blended, forKey: kCIInputImageKey)
                    fade.setValue(-0.05, forKey: kCIInputEVKey)  // Very slight darkening
                    currentTrails = fade.outputImage ?? blended
                } else {
                    currentTrails = blended
                }
            } else {
                currentTrails = boostedDiff
            }
        } else {
            currentTrails = boostedDiff
        }

        accumulatedTrails = currentTrails.cropped(to: outputRect)

        // 4. Apply trails over frozen frame, progressively blending in live
        return applyTrailsToFrozen(frozen: frozen, trails: currentTrails, live: live, outputRect: outputRect)
    }

    /// Blend the accumulated trails over the frozen frame, with progressive live blend
    private func applyTrailsToFrozen(frozen: CIImage, trails: CIImage, live: CIImage, outputRect: CGRect) -> CIImage {
        // Screen blend: trails appear as bright ghostly additions over frozen
        guard let screen = CIFilter(name: "CIScreenBlendMode") else {
            return frozen
        }
        screen.setValue(trails, forKey: kCIInputImageKey)
        screen.setValue(frozen, forKey: kCIInputBackgroundImageKey)

        guard let frozenWithTrails = screen.outputImage else {
            return frozen
        }

        // Progressive blend toward live - starts at 0%, ends near 60%
        // This ensures the output actually changes over time (for chained effects like ColorEcho)
        let progress = Double(framesSinceFreeze) / Double(max(1, holdDurationFrames))
        let liveBlend = progress * 0.6  // Max 60% live at the end

        guard let dissolve = CIFilter(name: "CIDissolveTransition") else {
            return frozenWithTrails.cropped(to: outputRect)
        }
        dissolve.setValue(frozenWithTrails, forKey: kCIInputImageKey)
        dissolve.setValue(live, forKey: kCIInputTargetImageKey)
        dissolve.setValue(liveBlend, forKey: kCIInputTimeKey)

        guard let result = dissolve.outputImage else {
            return frozenWithTrails.cropped(to: outputRect)
        }

        return result.cropped(to: outputRect)
    }
}
