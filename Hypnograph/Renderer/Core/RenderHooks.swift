//
//  RenderHooks.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//

import CoreGraphics
import CoreMedia
import CoreImage
import CoreVideo
import Metal
import AVFoundation

// MARK: - Shared Renderer

/// Shared Metal device and CIContext for efficient GPU resource reuse
enum SharedRenderer {
    static let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// Shared CIContext for all rendering - Metal-backed, no intermediate caching
    static let ciContext: CIContext = {
        if let device = metalDevice {
            return CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()
}

// MARK: - Frame Buffer

/// GPU-efficient ring buffer for temporal effects.
/// Stores CVPixelBuffers backed by IOSurface for zero-copy GPU access.
/// Supports up to 120 frames (~4 seconds at 30fps) for advanced datamosh/AI effects.
final class FrameBuffer {

    // MARK: - Configuration

    /// Maximum buffer capacity (default 120 for full datamosh/AI support)
    let maxFrames: Int

    /// Current active capacity (can be reduced for lighter effects)
    private(set) var activeCapacity: Int

    /// When true, buffer wraps around for looping clips instead of clearing on time discontinuity.
    /// When requesting frames beyond what's available, wraps to end of buffer (simulating clip loop).
    /// Toggle this to test looping vs non-looping behavior for temporal effects.
    static let loopingModeEnabled: Bool = true

    // MARK: - Storage

    /// Ring buffer of pixel buffers (IOSurface-backed for GPU sharing)
    private var buffers: [CVPixelBuffer?]

    /// Write position in the ring buffer
    private var writeIndex: Int = 0

    /// Number of valid frames currently stored
    private var validCount: Int = 0

    /// Last frame time for discontinuity detection
    private var lastTime: CMTime?

    /// Thread-safe access
    private let queue = DispatchQueue(label: "FrameBuffer.queue")

    /// Pixel buffer pool for efficient allocation
    private var pixelBufferPool: CVPixelBufferPool?

    /// Current buffer dimensions
    private var bufferWidth: Int = 0
    private var bufferHeight: Int = 0

    // MARK: - Init

    /// Initialize with maximum capacity
    /// - Parameter maxFrames: Maximum frames to store (default 120 for ~4s at 30fps)
    init(maxFrames: Int = 120) {
        self.maxFrames = maxFrames
        self.activeCapacity = maxFrames
        self.buffers = Array(repeating: nil, count: maxFrames)
    }

    // MARK: - Pool Management

    /// Create or recreate the pixel buffer pool for the given dimensions
    private func ensurePool(width: Int, height: Int) {
        if bufferWidth == width && bufferHeight == height && pixelBufferPool != nil {
            return
        }

        bufferWidth = width
        bufferHeight = height

        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: maxFrames
        ]

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],  // Enable IOSurface backing
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )

        if status == kCVReturnSuccess {
            pixelBufferPool = pool
        } else {
            print("⚠️ FrameBuffer: Failed to create pixel buffer pool: \(status)")
            pixelBufferPool = nil
        }
    }

    /// Get a pixel buffer from the pool
    private func getPooledBuffer() -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)

        if status != kCVReturnSuccess {
            print("⚠️ FrameBuffer: Failed to get buffer from pool: \(status)")
            return nil
        }

        return pixelBuffer
    }

    // MARK: - Frame Operations

    /// Add a frame to the buffer
    /// - Parameters:
    ///   - image: The CIImage to store
    ///   - time: Frame timestamp (for discontinuity detection)
    func addFrame(_ image: CIImage, at time: CMTime) {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return }

        let width = Int(extent.width)
        let height = Int(extent.height)

        queue.sync {
            // Detect discontinuity (seek/loop)
            // In looping mode, preserve buffer across loops for continuous effects
            // In non-looping mode, clear buffer when time jumps backwards
            if let last = lastTime, time < last, !Self.loopingModeEnabled {
                clearInternal()
            }
            lastTime = time

            // Ensure pool is configured for current dimensions
            ensurePool(width: width, height: height)

            // Get a buffer from the pool
            guard let pixelBuffer = getPooledBuffer() else { return }

            // Render CIImage directly to the pixel buffer (GPU-efficient)
            SharedRenderer.ciContext.render(
                image,
                to: pixelBuffer,
                bounds: extent,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )

            // Store in ring buffer
            buffers[writeIndex] = pixelBuffer
            writeIndex = (writeIndex + 1) % activeCapacity
            validCount = min(validCount + 1, activeCapacity)
        }
    }

    /// Get previous frame as CIImage (offset: 1 = previous, 2 = two frames ago, etc.)
    /// In looping mode, wraps around if offset exceeds available frames.
    func previousFrame(offset: Int = 1) -> CIImage? {
        queue.sync {
            guard offset > 0, validCount > 0 else { return nil }

            // In looping mode, wrap offset to available frames
            // This simulates continuous looping where "before the start" wraps to "end of clip"
            let effectiveOffset: Int
            if Self.loopingModeEnabled && offset > validCount {
                effectiveOffset = ((offset - 1) % validCount) + 1
            } else if offset > validCount {
                return nil
            } else {
                effectiveOffset = offset
            }

            // Calculate read position (writeIndex - 1 is most recent)
            let readIndex = (writeIndex - effectiveOffset + activeCapacity) % activeCapacity

            guard let pixelBuffer = buffers[readIndex] else { return nil }

            // Wrap CVPixelBuffer in CIImage (zero-copy - shares IOSurface)
            return CIImage(cvPixelBuffer: pixelBuffer)
        }
    }

    /// Get the most recently added frame
    var currentFrame: CIImage? {
        queue.sync {
            guard validCount > 0 else { return nil }
            let readIndex = (writeIndex - 1 + activeCapacity) % activeCapacity
            guard let pixelBuffer = buffers[readIndex] else { return nil }
            return CIImage(cvPixelBuffer: pixelBuffer)
        }
    }

    /// Check if buffer has minimum frames for temporal effects
    var isFilled: Bool {
        queue.sync {
            validCount >= min(3, activeCapacity)
        }
    }

    /// Number of valid frames currently stored
    var frameCount: Int {
        queue.sync { validCount }
    }

    /// Clear all stored frames
    func clear() {
        queue.sync { clearInternal() }
    }

    private func clearInternal() {
        let previousCount = validCount
        for i in 0..<buffers.count {
            buffers[i] = nil
        }
        writeIndex = 0
        validCount = 0
        lastTime = nil
        // Flush texture cache to release any cached Metal textures from old pixel buffers
        Self.flushTextureCache()
        print("🔄 FrameBuffer: cleared \(previousCount) frames, flushed texture cache")
    }

    // MARK: - Capacity Control

    /// Set active capacity (for effects that need fewer frames)
    /// - Parameter capacity: New capacity (clamped to maxFrames)
    func setActiveCapacity(_ capacity: Int) {
        queue.sync {
            let newCapacity = min(max(1, capacity), maxFrames)
            if newCapacity != activeCapacity {
                // Clear and resize
                clearInternal()
                activeCapacity = newCapacity
            }
        }
    }

    /// Memory estimate in bytes
    var estimatedMemoryUsage: Int {
        queue.sync {
            validCount * bufferWidth * bufferHeight * 4  // 4 bytes per BGRA pixel
        }
    }

    // MARK: - Pre-roll

    /// Pre-roll the buffer by extracting frames from a video asset before playback starts.
    /// This fills the buffer so effects have full history from frame 1.
    /// - Parameters:
    ///   - asset: The video asset to extract frames from
    ///   - startTime: Where playback will begin (frames before this are extracted)
    ///   - frameCount: Number of frames to pre-roll (default: activeCapacity)
    ///   - frameRate: Frame rate for extraction (default: 30)
    /// - Returns: Number of frames successfully pre-rolled
    @discardableResult
    func preroll(from asset: AVAsset, startTime: CMTime, frameCount: Int? = nil, frameRate: Double = 30) async -> Int {
        let targetCount = min(frameCount ?? activeCapacity, activeCapacity)
        guard targetCount > 0 else { return 0 }

        // Get asset duration and video track
        guard let duration = try? await asset.load(.duration),
              let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            print("⚠️ FrameBuffer: Failed to load asset for preroll")
            return 0
        }

        // Calculate start time for extraction
        // We want to extract `targetCount` frames ending at `startTime`
        let frameDuration = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
        let prerollDuration = CMTimeMultiply(frameDuration, multiplier: Int32(targetCount))
        var extractionStart = startTime - prerollDuration

        // Handle wrapping for looping mode
        if Self.loopingModeEnabled && extractionStart < .zero {
            // Wrap to end of clip
            let wrappedSeconds = duration.seconds + extractionStart.seconds.truncatingRemainder(dividingBy: duration.seconds)
            extractionStart = CMTime(seconds: max(0, wrappedSeconds), preferredTimescale: 600)
        } else if extractionStart < .zero {
            extractionStart = .zero
        }

        // Set up AVAssetReader for fast sequential reading
        guard let reader = try? AVAssetReader(asset: asset) else {
            print("⚠️ FrameBuffer: Failed to create AVAssetReader")
            return 0
        }

        // Configure output for BGRA pixel buffers (compatible with CIImage)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false  // Zero-copy when possible

        guard reader.canAdd(readerOutput) else {
            print("⚠️ FrameBuffer: Cannot add reader output")
            return 0
        }
        reader.add(readerOutput)

        // Set time range for extraction
        let timeRange = CMTimeRange(start: extractionStart, duration: prerollDuration)
        reader.timeRange = timeRange

        // Clear buffer before pre-roll
        clear()

        // Start reading
        guard reader.startReading() else {
            print("⚠️ FrameBuffer: Failed to start reading: \(reader.error?.localizedDescription ?? "unknown")")
            return 0
        }

        var prerolledCount = 0
        let startTimestamp = CACurrentMediaTime()

        // Read frames sequentially (much faster than AVAssetImageGenerator)
        while prerolledCount < targetCount {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                break  // No more samples
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            addFrame(ciImage, at: presentationTime)
            prerolledCount += 1
        }

        reader.cancelReading()  // Clean up

        let elapsed = CACurrentMediaTime() - startTimestamp
        print("🎬 FrameBuffer: Pre-rolled \(prerolledCount)/\(targetCount) frames in \(String(format: "%.2f", elapsed))s")
        return prerolledCount
    }

    /// Pre-fill the buffer with copies of a still image.
    /// Used for still images so effects have full history from frame 1.
    /// - Parameters:
    ///   - image: The still image to fill with
    ///   - frameCount: Number of frames to fill (default: activeCapacity)
    /// - Returns: Number of frames filled
    @discardableResult
    func prefill(with image: CIImage, frameCount: Int? = nil) -> Int {
        let targetCount = min(frameCount ?? activeCapacity, activeCapacity)
        guard targetCount > 0 else { return 0 }

        // Clear buffer before pre-fill
        clear()

        // Add the same image multiple times with incrementing fake timestamps
        for i in 0..<targetCount {
            let fakeTime = CMTime(value: CMTimeValue(i), timescale: 30)
            addFrame(image, at: fakeTime)
        }

        print("🖼️ FrameBuffer: Pre-filled \(targetCount) frames with still image")
        return targetCount
    }

    // MARK: - Metal Texture Access

    /// Texture cache for CVPixelBuffer -> MTLTexture conversion
    private static var textureCache: CVMetalTextureCache? = {
        guard let device = SharedRenderer.metalDevice else { return nil }
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        return cache
    }()

    /// Flush the texture cache (call when clearing buffer to release old textures)
    static func flushTextureCache() {
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }

    /// Get previous frame as MTLTexture for Metal compute shaders
    /// - Parameter offset: History offset (1 = previous frame, 2 = two frames ago, etc.)
    /// - Returns: MTLTexture backed by the same IOSurface (zero-copy)
    /// In looping mode, wraps around if offset exceeds available frames.
    func previousTexture(offset: Int = 1) -> MTLTexture? {
        queue.sync {
            guard offset > 0, validCount > 0 else { return nil }

            // In looping mode, wrap offset to available frames
            let effectiveOffset: Int
            if Self.loopingModeEnabled && offset > validCount {
                effectiveOffset = ((offset - 1) % validCount) + 1
            } else if offset > validCount {
                return nil
            } else {
                effectiveOffset = offset
            }

            let readIndex = (writeIndex - effectiveOffset + activeCapacity) % activeCapacity
            guard let pixelBuffer = buffers[readIndex] else { return nil }

            return textureFromPixelBuffer(pixelBuffer)
        }
    }

    /// Get texture at specific history offset (thread-safe)
    /// - Parameter offset: How far back in history (0 = most recent)
    func texture(atHistoryOffset offset: Int) -> MTLTexture? {
        return previousTexture(offset: offset + 1)  // previousTexture uses 1-based offset
    }

    /// Current buffer dimensions
    var currentWidth: Int { queue.sync { bufferWidth } }
    var currentHeight: Int { queue.sync { bufferHeight } }

    /// Convert CVPixelBuffer to MTLTexture (zero-copy via IOSurface)
    private func textureFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = Self.textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTex = cvTexture else {
            return nil
        }

        return CVMetalTextureGetTexture(cvTex)
    }
}

// MARK: - Render Context

/// Per-frame context, used by BOTH preview and export.
struct RenderContext {
    let frameIndex: Int
    let time: CMTime
    let outputSize: CGSize

    /// Access to previous frames for motion-based effects
    let frameBuffer: FrameBuffer

    /// Index of the source currently being processed (if any).
    /// - `nil` when rendering the final composed frame or when no specific source is in scope.
    var sourceIndex: Int?

    init(
        frameIndex: Int,
        time: CMTime,
        outputSize: CGSize,
        frameBuffer: FrameBuffer,
        sourceIndex: Int? = nil
    ) {
        self.frameIndex = frameIndex
        self.time = time
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

    /// Number of past frames this effect needs access to.
    /// Used for buffer sizing and effect filtering by capability.
    ///
    /// Guidelines:
    /// - 0: No temporal dependency (pure per-frame effects)
    /// - 1-10: Simple temporal effects (frame diff, hold frame)
    /// - 10-40: Ghost trails, smear, basic datamosh
    /// - 40-120: Advanced datamosh, block propagation, AI effects
    var requiredLookback: Int { get }

    /// Apply effect to the current frame
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage

    /// Reset internal state (call when switching montages/effects)
    func reset()

    /// Create a fresh copy of this effect with the same configuration but reset state.
    /// Used for export to avoid sharing mutable state with preview.
    /// Stateless effects can return self. Class-based stateful effects MUST return a fresh instance.
    func copy() -> RenderHook
}

extension RenderHook {
    /// Default: no lookback required (pure per-frame effect)
    var requiredLookback: Int { 0 }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        image
    }

    func reset() {
        // Default: no-op for stateless hooks
    }

    func copy() -> RenderHook {
        // Default: return self (for struct-based stateless effects)
        // Class-based stateful effects MUST override this to return a fresh instance
        return self
    }
}

// MARK: - Available Effects

/// Namespace for available render effects
/// Effects are loaded from JSON config with fallback to bundled defaults
enum Effect {
    /// Cached loaded effects and source info
    private static var cachedResult: EffectConfigLoader.LoadResult?

    /// Callback triggered after effects are reloaded - allows managers to re-apply active effects
    static var onReload: (() -> Void)?

    /// All available effects (None is implicit, represented by nil)
    /// Loaded from: user config → bundled default → hardcoded fallback
    static var all: [RenderHook] {
        if let cached = cachedResult {
            return cached.effects
        }
        let result = EffectConfigLoader.loadEffects()
        cachedResult = result

        // Log source and notify on errors
        switch result.source {
        case .user:
            print("✓ Effects loaded from user config (\(result.effects.count) effects)")
        case .bundled:
            print("✓ Effects loaded from bundled defaults (\(result.effects.count) effects)")
        case .hardcoded:
            print("⚠️ Effects using hardcoded fallback")
            if result.error != nil {
                AppNotifications.show("⚠️ Effects config error - using defaults", flash: true, duration: 4.0)
            }
        }

        return result.effects
    }

    /// Reload effects from config (call when config file changes)
    @discardableResult
    static func reload() -> EffectConfigLoader.LoadResult {
        let result = EffectConfigLoader.loadEffects()
        cachedResult = result

        // Notify user of reload result
        switch result.source {
        case .user:
            print("✓ Effects reloaded from user config (\(result.effects.count) effects)")
            AppNotifications.show("Effects reloaded (\(result.effects.count))", flash: true, duration: 2.0)
        case .bundled:
            print("✓ Effects reloaded from bundled defaults")
            AppNotifications.show("Effects reloaded from defaults", flash: true, duration: 2.0)
        case .hardcoded:
            print("⚠️ Effects reload failed, using hardcoded fallback")
            AppNotifications.show("⚠️ Effects config error - using defaults", flash: true, duration: 4.0)
        }

        // Notify listeners to re-apply active effects with new config
        onReload?()

        return result
    }

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
    /// 120 frames at 30fps = 4 seconds of history for advanced datamosh/AI effects
    let frameBuffer = FrameBuffer(maxFrames: 120)

    /// Global frame counter - increments each frame, persists across video loops
    /// Used by temporal effects that need consistent timing
    private(set) var globalFrameIndex: Int = 0

    /// Increment frame counter and return current value
    func nextFrameIndex() -> Int {
        let current = globalFrameIndex
        globalFrameIndex += 1
        return current
    }

    /// Reset frame counter (call when switching montages or effects)
    func resetFrameIndex() {
        globalFrameIndex = 0
    }

    /// Create a manager for export with a frozen recipe
    /// Uses same code paths as preview but with isolated state
    static func forExport(recipe: HypnogramRecipe) -> RenderHookManager {
        let manager = RenderHookManager()
        manager.recipeProvider = { recipe }
        // No setters needed - export is read-only
        // flashSoloIndex stays nil - export renders all layers
        return manager
    }

    /// Get the maximum lookback required by any effect (global or per-source)
    var maxRequiredLookback: Int {
        guard let recipe = recipeProvider?() else { return 0 }

        // Check global effects
        let globalMax = recipe.effects.map { $0.requiredLookback }.max() ?? 0

        // Check per-source effects
        let sourceMax = recipe.sources.flatMap { $0.effects }.map { $0.requiredLookback }.max() ?? 0

        return max(globalMax, sourceMax)
    }

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
        // Clear frame buffer and reset frame counter so new effect starts fresh
        frameBuffer.clear()
        resetFrameIndex()

        // Find current index (-1 means None)
        let currentName = globalEffectName
        let currentIndex = Effect.all.firstIndex { $0.name == currentName } ?? -1
        // Cycle: -1 -> 0 -> 1 -> ... -> count-1 -> -1
        let nextIndex = (currentIndex + 2) % (Effect.all.count + 1) - 1
        setGlobalEffect(nextIndex >= 0 ? Effect.all[nextIndex] : nil)
    }

    /// Re-apply active effects using fresh instances from the reloaded config.
    /// Called when effects config changes to apply parameter updates immediately.
    func reapplyActiveEffects() {
        guard let recipe = recipeProvider?() else { return }

        // Re-apply global effect by name
        if let currentEffect = recipe.effects.first {
            let currentName = currentEffect.name
            if let freshEffect = Effect.all.first(where: { $0.name == currentName }) {
                // Found matching effect - replace with fresh copy
                effectsSetter?([freshEffect.copy()])
                print("🔄 Reapplied global effect: \(currentName)")
            }
        }

        // Re-apply per-source effects by name
        for (index, source) in recipe.sources.enumerated() {
            if let currentEffect = source.effects.first {
                let currentName = currentEffect.name
                if let freshEffect = Effect.all.first(where: { $0.name == currentName }) {
                    sourceEffectSetter?(index, [freshEffect.copy()])
                    print("🔄 Reapplied source \(index) effect: \(currentName)")
                }
            }
        }

        onEffectChanged?()
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

        // Skip global effects during flash solo - show raw source
        if flashSoloIndex != nil {
            frameBuffer.addFrame(image, at: context.time)
            return image
        }

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
        print("🔄 RenderHookManager: clearFrameBuffer() - clearing \(frameBuffer.frameCount) frames")
        frameBuffer.clear()
        resetFrameIndex()

        // Reset all effects that have internal state (HoldFrameHook, DatamoshMetalHook, etc.)
        // Important: Do this BEFORE the recipe clears effects, because effects may be preserved
        if let recipe = recipeProvider?() {
            for effect in recipe.effects {
                effect.reset()
            }
            for source in recipe.sources {
                for effect in source.effects {
                    effect.reset()
                }
            }
        }
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
