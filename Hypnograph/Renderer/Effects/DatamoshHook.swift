//
//  DatamoshHook.swift
//  Hypnograph
//
//  Created by Loren Johnson on 20.11.25.
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Datamosh-style glitch effect that creates motion artifacts by blending
/// current frame with previous frames based on motion/difference.
/// Simulates I-frame/P-frame corruption from video codecs.
struct DatamoshHook: RenderHook {
    var name: String { "Datamosh" }

    /// Intensity of the effect (0.0 = subtle, 1.0 = extreme)
    let intensity: Float

    /// Maximum frame offset to look back (simulates variable I-frame distance)
    let maxFrameOffset: Int

    init(intensity: Float = 0.7, maxFrameOffset: Int = 60) {
        self.intensity = intensity
        self.maxFrameOffset = maxFrameOffset
    }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        // Wait until buffer has enough frames before applying heavy effects
        // This prevents artifacts during initial buffering
        guard context.frameBuffer.isFilled else {
            return image
        }

        // Determine if we're in a "smear phase" or "normal phase"
        let t = CMTimeGetSeconds(context.time)

        // Slow wave that creates occasional smear phases
        // sin(t * 0.2) oscillates slowly - full cycle every ~30 seconds
        let smearPhase = sin(t * 0.2)

        // Only apply effect during smear phases (when wave is high)
        // This means effect is active ~30% of the time, in bursts of ~5 seconds
        guard smearPhase > 0.5 else {
            // Normal phase - pass through unmodified
            return image
        }

        // We're in a smear phase! Apply the datamosh effect
        let availableFrames = context.frameBuffer.frameCount

        // Use very old frames for long, dramatic smears
        let maxSmearOffset = min(50, availableFrames - 1)

        guard maxSmearOffset >= 10 else {
            // Not enough buffer yet - pass through
            return image
        }

        // Use a consistent old frame during this smear phase (not random every frame)
        // This creates smoother, more stable smears
        let phaseOffset = Int((smearPhase - 0.5) * 100.0) // Varies slowly with the phase
        let offsetRange = max(1, maxSmearOffset - 10) // Prevent divide by zero
        let offset = 10 + (phaseOffset % offsetRange)

        guard let previousFrame = context.frameBuffer.previousFrame(offset: offset) else {
            return image
        }

        // Apply the effect with MUCH higher intensity for visibility
        // Ramp from 0.0 to 3.0 (instead of 1.0) for dramatic effect
        let smearIntensity = Float((smearPhase - 0.5) / 0.5) * 3.0
        return applyDatamoshEffect(current: image, previous: previousFrame, context: context, intensity: smearIntensity)
    }

    /// Apply the actual datamosh effect to the current frame using a previous frame
    private func applyDatamoshEffect(current: CIImage, previous: CIImage, context: RenderContext, intensity: Float = 1.0) -> CIImage {
        // Ensure both images have valid extents
        guard !current.extent.isEmpty, !previous.extent.isEmpty else {
            print("DatamoshHook: Invalid extents - current: \(current.extent), previous: \(previous.extent)")
            return current
        }

        // Crop both images to the same size to avoid extent issues
        let targetRect = CGRect(origin: .zero, size: context.outputSize)
        let croppedCurrent = current.cropped(to: targetRect)
        let croppedPrevious = previous.cropped(to: targetRect)

        // Safety check: ensure cropped images are valid
        guard !croppedCurrent.extent.isEmpty, !croppedPrevious.extent.isEmpty else {
            print("DatamoshHook: Invalid cropped extents")
            return current
        }

        // Step 1: Calculate difference/motion between frames
        guard let differenceFilter = CIFilter(name: "CIDifferenceBlendMode") else {
            return current
        }

        differenceFilter.setValue(croppedCurrent, forKey: kCIInputImageKey)
        differenceFilter.setValue(croppedPrevious, forKey: kCIInputBackgroundImageKey)

        guard let difference = differenceFilter.outputImage?.cropped(to: targetRect) else {
            return current
        }

        // Step 2: Convert difference to grayscale - keep it subtle for smooth smears
        guard let grayscaleFilter = CIFilter(name: "CIColorControls") else {
            return current
        }

        grayscaleFilter.setValue(difference, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(0.0, forKey: kCIInputSaturationKey) // Desaturate
        grayscaleFilter.setValue(2.0 + CGFloat(intensity), forKey: kCIInputContrastKey) // Higher contrast for more visible effect
        grayscaleFilter.setValue(0.3 * CGFloat(intensity), forKey: kCIInputBrightnessKey) // More brightness for stronger mask

        guard let motionMask = grayscaleFilter.outputImage?.cropped(to: targetRect) else {
            return current
        }

        // Step 2.5: Blur the motion mask to make smears smoother and less jittery
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return current
        }

        blurFilter.setValue(motionMask, forKey: kCIInputImageKey)
        blurFilter.setValue(5.0, forKey: kCIInputRadiusKey) // Moderate blur for smooth but visible transitions

        guard let blurredMask = blurFilter.outputImage?.cropped(to: targetRect) else {
            return current
        }

        // Step 3: Use blurred motion mask to blend previous frame ONLY in motion areas
        // This creates the "sticky" datamosh effect where moving objects trail
        guard let blendWithMask = CIFilter(name: "CIBlendWithMask") else {
            return current
        }

        // Previous frame shows through in motion areas (white in mask)
        // Current frame shows through in static areas (black in mask)
        blendWithMask.setValue(croppedPrevious, forKey: kCIInputImageKey)
        blendWithMask.setValue(croppedCurrent, forKey: kCIInputBackgroundImageKey)
        blendWithMask.setValue(blurredMask, forKey: kCIInputMaskImageKey) // Use blurred mask for smooth transitions

        guard let maskedBlend = blendWithMask.outputImage?.cropped(to: targetRect) else {
            return current
        }

        // Step 4: Add subtle displacement in motion areas (reduced for less jitter)
        guard let displacementFilter = CIFilter(name: "CIDisplacementDistortion") else {
            return maskedBlend
        }

        displacementFilter.setValue(maskedBlend, forKey: kCIInputImageKey)
        displacementFilter.setValue(blurredMask, forKey: "inputDisplacementImage")
        displacementFilter.setValue(CGFloat(intensity) * 20.0, forKey: kCIInputScaleKey) // Dramatic displacement for visible effect

        guard let displaced = displacementFilter.outputImage?.cropped(to: targetRect) else {
            return maskedBlend
        }

        return displaced
    }
}
