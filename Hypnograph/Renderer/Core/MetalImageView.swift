//
//  MetalImageView.swift
//  Hypnograph
//
//  Metal-based view for displaying processed CIImages directly.
//  Used for still images in sequence mode, bypassing AVPlayer.
//

import MetalKit
import CoreImage
import CoreMedia
import AppKit

/// NSView wrapper for MTKView that displays CIImages with effects
final class MetalImageView: NSView {
    
    private let mtkView: MTKView
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let frameProcessor: FrameProcessor
    
    /// Current image to display (before processing)
    private var sourceImage: CIImage?

    /// Current source index (for effects)
    private var sourceIndex: Int = 0

    /// User-applied transform (rotation, scale, etc.)
    private var userTransform: CGAffineTransform = .identity

    /// Target aspect ratio for content
    private var targetAspectRatio: AspectRatio = .ratio16x9

    /// Processing configuration
    private var processingConfig: ProcessingConfig?
    
    /// Display link for animation (effects that change over time)
    private var displayLink: CVDisplayLink?
    private var isAnimating = false
    
    /// Time tracking for animated effects
    private var startTime: CFTimeInterval = 0
    
    override init(frame frameRect: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is not supported on this device")
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device, options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false
        ])
        self.frameProcessor = FrameProcessor(ciContext: ciContext)
        self.mtkView = MTKView(frame: frameRect, device: device)
        
        super.init(frame: frameRect)
        
        setupMTKView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopAnimation()
    }
    
    private func setupMTKView() {
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true  // We'll drive rendering manually
        mtkView.delegate = self
        
        addSubview(mtkView)
        
        NSLayoutConstraint.activate([
            mtkView.topAnchor.constraint(equalTo: topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: bottomAnchor),
            mtkView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    // MARK: - Public API
    
    /// Display a still image with effects
    func display(
        image: CIImage,
        sourceIndex: Int,
        aspectRatio: AspectRatio,
        transform: CGAffineTransform = .identity,
        enableEffects: Bool = true
    ) {
        self.sourceImage = image
        self.sourceIndex = sourceIndex
        self.userTransform = transform
        self.targetAspectRatio = aspectRatio
        self.processingConfig = ProcessingConfig(
            outputSize: mtkView.drawableSize,
            time: .zero,
            isPreview: true,
            enableEffects: enableEffects
        )

        // Request a redraw
        mtkView.setNeedsDisplay(mtkView.bounds)
    }
    
    /// Start animating (for time-based effects)
    func startAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        startTime = CACurrentMediaTime()
        mtkView.isPaused = false
    }
    
    /// Stop animating
    func stopAnimation() {
        guard isAnimating else { return }
        isAnimating = false
        mtkView.isPaused = true
    }
    
    /// Clear the display
    func clear() {
        sourceImage = nil
        mtkView.setNeedsDisplay(mtkView.bounds)
    }
}

// MARK: - MTKViewDelegate

extension MetalImageView: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Update processing config if needed
        if let config = processingConfig {
            processingConfig = ProcessingConfig(
                outputSize: size,
                time: config.time,
                isPreview: config.isPreview,
                enableEffects: config.enableEffects
            )
        }
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              var img = sourceImage,
              let config = processingConfig else {
            return
        }

        // Use the actual drawable size for rendering
        let drawableSize = view.drawableSize

        // Apply user transform (if not identity)
        if userTransform != .identity {
            img = img.transformed(by: userTransform)

            // After transform, translate extent back to origin for aspect-fill
            let transformedExtent = img.extent
            if transformedExtent.origin != .zero {
                img = img.transformed(by: CGAffineTransform(
                    translationX: -transformedExtent.origin.x,
                    y: -transformedExtent.origin.y
                ))
            }
        }

        // Compute content size from drawable and aspect ratio
        let contentSize = renderSize(aspectRatio: targetAspectRatio, fitting: drawableSize)

        // Update config with content size and time
        var updatedConfig = ProcessingConfig(
            outputSize: contentSize,
            time: config.time,
            isPreview: config.isPreview,
            enableEffects: config.enableEffects
        )

        if isAnimating {
            let elapsed = CACurrentMediaTime() - startTime
            updatedConfig = ProcessingConfig(
                outputSize: contentSize,
                time: CMTime(seconds: elapsed, preferredTimescale: 600),
                isPreview: config.isPreview,
                enableEffects: config.enableEffects
            )
        }

        // Process the image through the unified pipeline
        let processedImage = frameProcessor.processSingleSource(
            img,
            sourceIndex: sourceIndex,
            config: updatedConfig,
            manager: GlobalRenderHooks.manager
        )

        // Center content in drawable (letterbox/pillarbox)
        let offsetX = (drawableSize.width - contentSize.width) / 2
        let offsetY = (drawableSize.height - contentSize.height) / 2
        let centeredImage = processedImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        // Render to Metal drawable
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        ciContext.render(
            centeredImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: drawableSize),
            colorSpace: colorSpace
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

