//
//  TransitionManager.swift
//  Hypnograph
//
//  Manages smooth crossfade transitions between hypnograms.
//  Uses a child NSWindow overlay to ensure the transition appears above AVPlayerView.
//

import Foundation
import CoreImage
import AppKit
import QuartzCore

/// Manages crossfade transitions between hypnograms using a native window overlay
@MainActor
final class TransitionManager: ObservableObject {

    /// Duration of the crossfade in seconds
    var transitionDuration: TimeInterval = 0.8

    /// Whether a transition is currently in progress
    @Published private(set) var isTransitioning: Bool = false

    // For SwiftUI compatibility (not used but needed to avoid breaking changes)
    @Published private(set) var transitionImage: CGImage?
    @Published private(set) var transitionOpacity: Double = 0.0

    private var overlayWindow: NSWindow?
    private var overlayImageView: NSImageView?
    private var fadeStartTime: CFTimeInterval = 0
    private var displayLink: CVDisplayLink?

    // MARK: - Public API

    /// Capture the current screen content and begin a crossfade transition
    /// Call this BEFORE changing the hypnogram
    init() {}

    func beginTransitionFromWindow() {
        guard let window = NSApplication.shared.mainWindow,
              let contentView = window.contentView else {
            print("⚠️ TransitionManager: No window to capture")
            return
        }

        // Force layer-backed rendering to capture video content
        let wasLayerBacked = contentView.wantsLayer
        contentView.wantsLayer = true

        // Create a bitmap by rendering the layer tree
        let size = contentView.bounds.size
        guard size.width > 0, size.height > 0 else {
            print("⚠️ TransitionManager: Invalid view size")
            return
        }

        // Use layer rendering which captures AVPlayerLayer content
        if let layer = contentView.layer {
            let scale = window.backingScaleFactor
            let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

            guard let context = CGContext(
                data: nil,
                width: Int(pixelSize.width),
                height: Int(pixelSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else {
                print("⚠️ TransitionManager: Failed to create CGContext")
                return
            }

            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)

            if let cgImage = context.makeImage() {
                let image = NSImage(cgImage: cgImage, size: size)
                print("🔄 TransitionManager: Beginning \(transitionDuration)s crossfade, image size: \(size)")
                startTransition(with: image, in: window)
            } else {
                print("⚠️ TransitionManager: Failed to create CGImage from context")
            }
        }

        contentView.wantsLayer = wasLayerBacked
    }

    /// Cancel any in-progress transition
    func cancelTransition() {
        stopDisplayLink()

        if let overlay = overlayWindow {
            overlay.parent?.removeChildWindow(overlay)
            overlay.orderOut(nil)
        }
        overlayWindow = nil
        overlayImageView = nil
        isTransitioning = false
        transitionOpacity = 0.0
    }

    // MARK: - Private

    private func startTransition(with image: NSImage, in parentWindow: NSWindow) {
        // Cancel any existing transition
        cancelTransition()

        // Create overlay window
        let overlay = NSWindow(
            contentRect: parentWindow.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.ignoresMouseEvents = true
        overlay.level = .floating
        overlay.hasShadow = false

        // Create image view filling the window
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: parentWindow.frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspectFill
        overlay.contentView = imageView

        // Add as child window (follows parent)
        parentWindow.addChildWindow(overlay, ordered: .above)
        overlay.setFrame(parentWindow.frame, display: true)

        overlayWindow = overlay
        overlayImageView = imageView
        isTransitioning = true
        transitionOpacity = 1.0
        fadeStartTime = CACurrentMediaTime()

        // Start display link for smooth animation
        startDisplayLink()
    }

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let displayLink = link else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
            let manager = Unmanaged<TransitionManager>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.updateFade()
            }
            return kCVReturnSuccess
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, userInfo)
        CVDisplayLinkStart(displayLink)
        self.displayLink = displayLink
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    private func updateFade() {
        guard isTransitioning else { return }

        let elapsed = CACurrentMediaTime() - fadeStartTime
        let progress = min(1.0, elapsed / transitionDuration)

        // Ease-out curve for smoother fade
        let easedProgress = 1.0 - pow(1.0 - progress, 2)
        let opacity = 1.0 - easedProgress
        transitionOpacity = opacity

        // Update window opacity
        overlayWindow?.alphaValue = opacity

        if progress >= 1.0 {
            // Transition complete
            cancelTransition()
            print("✅ TransitionManager: Crossfade complete")
        }
    }
}
