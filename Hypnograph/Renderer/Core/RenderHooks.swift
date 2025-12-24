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

// MARK: - Parameter Metadata

/// Metadata for a single effect parameter - defines type, range, and default value.
/// Each hook declares its parameters using this, making the hook the source of truth.
enum ParameterSpec: Equatable {
    case double(default: Double, range: ClosedRange<Double>)
    case float(default: Float, range: ClosedRange<Float>)
    case int(default: Int, range: ClosedRange<Int>)
    case bool(default: Bool)
    /// Choice parameter: stores as string, displays as dropdown
    /// - default: the default choice key
    /// - options: ordered list of (key, displayLabel) pairs
    case choice(default: String, options: [(key: String, label: String)])
    /// Color parameter: stores as hex string (e.g., "#FFFFFF"), displays as color picker
    case color(default: String)
    /// File picker: stores filename as string, displays files from a directory
    /// - fileExtension: file extension to filter (e.g., "cube")
    /// - directoryProvider: closure that returns the directory URL to scan
    case file(fileExtension: String, directoryProvider: () -> URL)

    /// Get the default value as AnyCodableValue
    var defaultValue: AnyCodableValue {
        switch self {
        case .double(let d, _): return .double(d)
        case .float(let f, _): return .double(Double(f))
        case .int(let i, _): return .int(i)
        case .bool(let b): return .bool(b)
        case .choice(let d, _): return .string(d)
        case .color(let hex): return .string(hex)
        case .file: return .string("")  // Default to empty (will show placeholder in UI)
        }
    }

    /// Get range as (min, max) doubles (for UI sliders)
    var rangeAsDoubles: (min: Double, max: Double)? {
        switch self {
        case .double(_, let range): return (range.lowerBound, range.upperBound)
        case .float(_, let range): return (Double(range.lowerBound), Double(range.upperBound))
        case .int(_, let range): return (Double(range.lowerBound), Double(range.upperBound))
        case .bool, .choice, .color, .file: return nil
        }
    }

    /// Step size for UI (1 for ints, nil for continuous)
    var step: Double? {
        switch self {
        case .int: return 1
        default: return nil
        }
    }

    /// Get choice options (for dropdown UI)
    var choiceOptions: [(key: String, label: String)]? {
        switch self {
        case .choice(_, let options): return options
        default: return nil
        }
    }

    /// Check if this is a color parameter
    var isColor: Bool {
        if case .color = self { return true }
        return false
    }

    /// Check if this is a file picker parameter
    var isFile: Bool {
        if case .file = self { return true }
        return false
    }

    /// Get file picker info (extension and directory)
    var filePickerInfo: (fileExtension: String, directory: URL)? {
        if case .file(let ext, let dirProvider) = self {
            return (ext, dirProvider())
        }
        return nil
    }

    // MARK: - File List Cache (shared across all file parameters)

    /// Cache for file lists, keyed by "directory|extension"
    private static var fileListCache: [String: [(key: String, label: String)]] = [:]
    private static let fileListCacheLock = NSLock()

    /// Clear the file list cache (call when user might have added new files)
    static func clearFileListCache() {
        fileListCacheLock.lock()
        defer { fileListCacheLock.unlock() }
        fileListCache.removeAll()
        print("🔄 ParameterSpec: Cleared file list cache")
    }

    /// Get available files for file picker (cached to avoid repeated filesystem scans)
    var availableFiles: [(key: String, label: String)] {
        guard let info = filePickerInfo else { return [] }
        let cacheKey = "\(info.directory.path)|\(info.fileExtension)"

        // Check cache first
        Self.fileListCacheLock.lock()
        if let cached = Self.fileListCache[cacheKey] {
            Self.fileListCacheLock.unlock()
            return cached
        }
        Self.fileListCacheLock.unlock()

        // Cache miss - scan filesystem
        let fm = FileManager.default
        let dir = info.directory

        // Ensure directory exists
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Recursively enumerate all files in directory
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [(key: String, label: String)] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == info.fileExtension.lowercased() else {
                continue
            }
            // Use relative path from base directory as key (without extension)
            let relativePath = fileURL.path.replacingOccurrences(of: dir.path + "/", with: "")
            let key = (relativePath as NSString).deletingPathExtension
            // Label shows the relative path for clarity
            results.append((key: key, label: key))
        }

        let sorted = results.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        // Cache the results
        Self.fileListCacheLock.lock()
        Self.fileListCache[cacheKey] = sorted
        Self.fileListCacheLock.unlock()

        return sorted
    }

    /// Custom Equatable for choice (tuples aren't Equatable by default)
    static func == (lhs: ParameterSpec, rhs: ParameterSpec) -> Bool {
        switch (lhs, rhs) {
        case (.double(let d1, let r1), .double(let d2, let r2)):
            return d1 == d2 && r1 == r2
        case (.float(let f1, let r1), .float(let f2, let r2)):
            return f1 == f2 && r1 == r2
        case (.int(let i1, let r1), .int(let i2, let r2)):
            return i1 == i2 && r1 == r2
        case (.bool(let b1), .bool(let b2)):
            return b1 == b2
        case (.choice(let d1, let o1), .choice(let d2, let o2)):
            return d1 == d2 && o1.map(\.key) == o2.map(\.key) && o1.map(\.label) == o2.map(\.label)
        case (.color(let c1), .color(let c2)):
            return c1 == c2
        case (.file(let e1, _), .file(let e2, _)):
            return e1 == e2  // Compare extension only, not closure
        default:
            return false
        }
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

    /// Parameter metadata - defines what parameters this hook accepts,
    /// their types, ranges, and default values. Hook is the source of truth.
    static var parameterSpecs: [String: ParameterSpec] { get }

    /// Create an instance from a parameters dictionary.
    /// Each effect extracts its own parameters using parameterSpecs defaults as fallback.
    /// Returns nil if the effect cannot be created (e.g., missing Metal device).
    init?(params: [String: AnyCodableValue]?)

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

    /// Default: no parameters
    static var parameterSpecs: [String: ParameterSpec] { [:] }

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

// MARK: - Parameter Extraction Helper

/// Helper for extracting parameter values with defaults from parameterSpecs.
/// Eliminates redundant default value specifications in init?(params:).
struct Params {
    private let dict: [String: AnyCodableValue]?
    private let specs: [String: ParameterSpec]

    init(_ params: [String: AnyCodableValue]?, specs: [String: ParameterSpec]) {
        self.dict = params
        self.specs = specs
    }

    /// Get Float value, falling back to spec default
    func float(_ key: String) -> Float {
        if let value = dict?[key]?.floatValue { return value }
        if case .float(let d, _) = specs[key] { return d }
        return 0
    }

    /// Get Double value, falling back to spec default
    func double(_ key: String) -> Double {
        if let value = dict?[key]?.doubleValue { return value }
        if case .double(let d, _) = specs[key] { return d }
        return 0
    }

    /// Get Int value, falling back to spec default
    func int(_ key: String) -> Int {
        if let value = dict?[key]?.intValue { return value }
        if case .int(let d, _) = specs[key] { return d }
        return 0
    }

    /// Get Bool value, falling back to spec default
    func bool(_ key: String) -> Bool {
        if let value = dict?[key]?.boolValue { return value }
        if case .bool(let d) = specs[key] { return d }
        return false
    }

    /// Get String value (for choice params), falling back to spec default
    func string(_ key: String) -> String {
        if let value = dict?[key]?.stringValue { return value }
        if case .choice(let d, _) = specs[key] { return d }
        if case .color(let d) = specs[key] { return d }
        return ""
    }

    /// Get CGFloat value (from double spec), falling back to spec default
    func cgFloat(_ key: String) -> CGFloat {
        CGFloat(double(key))
    }
}

// MARK: - Named Hook Wrapper

/// Wrapper that overrides the name of any RenderHook
/// Used by the config loader to apply custom names from JSON without modifying each hook implementation
struct NamedHook: RenderHook {
    private let wrapped: RenderHook
    let name: String

    var requiredLookback: Int { wrapped.requiredLookback }

    init(wrapping hook: RenderHook, name: String) {
        self.wrapped = hook
        self.name = name
    }

    /// NamedHook cannot be created from params - it's only used to wrap existing hooks
    init?(params: [String: AnyCodableValue]?) {
        return nil
    }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        wrapped.willRenderFrame(&context, image: image)
    }

    func reset() {
        wrapped.reset()
    }

    func copy() -> RenderHook {
        NamedHook(wrapping: wrapped.copy(), name: name)
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

    /// Update a single effect in the cache (used for live parameter updates)
    static func updateCachedEffect(at index: Int, with hook: RenderHook) {
        guard var result = cachedResult, index >= 0, index < result.effects.count else { return }
        var effects = result.effects
        effects[index] = hook
        cachedResult = EffectConfigLoader.LoadResult(effects: effects, source: result.source, error: result.error)
    }

    /// Replace the entire effects cache with new hooks
    /// Used by EffectConfigLoader when effects are added/deleted in-memory
    static func updateCache(with hooks: [RenderHook]) {
        let source = cachedResult?.source ?? .user
        cachedResult = EffectConfigLoader.LoadResult(effects: hooks, source: source, error: nil)
        // Notify listeners to re-apply active effects
        onReload?()
    }

    /// Reload effects from config (call when config file changes)
    /// - Parameter silent: If true, don't show notification (used for live parameter updates)
    @discardableResult
    static func reload(silent: Bool = false) -> EffectConfigLoader.LoadResult {
        // Clear loader cache first so we get fresh data
        EffectConfigLoader.clearCache()

        let result = EffectConfigLoader.loadEffects()
        cachedResult = result

        // Notify user of reload result (unless silent)
        if !silent {
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
        }

        // Notify listeners to re-apply active effects with new config
        onReload?()

        return result
    }

    /// Reload effects from a specific URL (for library switching)
    @discardableResult
    static func reload(from url: URL) -> EffectConfigLoader.LoadResult {
        do {
            let effects = try EffectConfigLoader.loadFromURL(url)
            let result = EffectConfigLoader.LoadResult(effects: effects, source: .user, error: nil)
            cachedResult = result
            print("✓ Effects loaded from library: \(url.lastPathComponent) (\(effects.count) effects)")

            // Notify listeners to re-apply active effects
            onReload?()

            return result
        } catch {
            print("⚠️ Failed to load effects from \(url.path): \(error)")
            // Fall back to normal reload
            return reload()
        }
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

    /// Closure to update the global effect definition
    var globalEffectDefinitionSetter: ((EffectDefinition?) -> Void)?

    /// Closure to update a source's effect definition
    var sourceEffectDefinitionSetter: ((Int, EffectDefinition?) -> Void)?

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

    /// Set global effect from a definition - stores definition and instantiates hook
    /// This is the preferred method for selecting effects from the library
    func setGlobalEffect(from definition: EffectDefinition?) {
        globalEffectDefinitionSetter?(definition)
        if let def = definition, let hook = EffectConfigLoader.instantiateEffect(def) {
            effectsSetter?([hook])
        } else {
            effectsSetter?([])
        }
        onEffectChanged?()
    }

    /// Get the current global effect definition (for editing)
    var globalEffectDefinition: EffectDefinition? {
        recipeProvider?()?.effectDefinition
    }

    /// Update a parameter in the recipe's effect definition and re-instantiate
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - hookIndex: nil for top-level effect, or index of child hook in chain
    ///   - paramName: name of the parameter to update
    ///   - value: new value for the parameter
    func updateEffectParameter(for layer: Int, hookIndex: Int?, paramName: String, value: AnyCodableValue) {
        // Get current definition
        guard var definition = effectDefinition(for: layer) else { return }

        // Update the parameter in the definition
        if let hookIdx = hookIndex, var hooks = definition.hooks {
            // Update parameter in a chained hook
            guard hookIdx >= 0 && hookIdx < hooks.count else { return }
            var hook = hooks[hookIdx]
            var params = hook.params ?? [:]
            params[paramName] = value
            hook = EffectDefinition(name: hook.name, type: hook.type, params: params, hooks: hook.hooks)
            hooks[hookIdx] = hook
            definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)
        } else {
            // Update parameter on the effect itself
            var params = definition.params ?? [:]
            params[paramName] = value
            definition = EffectDefinition(name: definition.name, type: definition.type, params: params, hooks: definition.hooks)
        }

        // Store updated definition and re-instantiate
        setEffect(from: definition, for: layer)
    }

    /// Add a hook to the recipe's effect chain for a layer
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - hookType: the type of hook to add (e.g. "DatamoshMetalHook")
    func addHookToChain(for layer: Int, hookType: String) {
        guard var definition = effectDefinition(for: layer) else { return }

        var hooks = definition.hooks ?? []
        let defaults = EffectRegistry.defaults(for: hookType)
        let newHook = EffectDefinition(name: nil, type: hookType, params: defaults, hooks: nil)
        hooks.append(newHook)
        definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)

        setEffect(from: definition, for: layer)
    }

    /// Remove a hook from the recipe's effect chain for a layer
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - hookIndex: index of the hook to remove
    func removeHookFromChain(for layer: Int, hookIndex: Int) {
        guard var definition = effectDefinition(for: layer) else { return }
        guard var hooks = definition.hooks, hookIndex >= 0, hookIndex < hooks.count else { return }

        hooks.remove(at: hookIndex)
        definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)

        setEffect(from: definition, for: layer)
    }

    /// Update the effect name in the recipe's definition
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - name: new name for the effect
    func updateEffectName(for layer: Int, name: String) {
        guard var definition = effectDefinition(for: layer) else { return }

        definition = EffectDefinition(name: name, type: definition.type, params: definition.params, hooks: definition.hooks)

        setEffect(from: definition, for: layer)
    }

    /// Reorder hooks in the recipe's effect chain for a layer
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - fromIndex: source index
    ///   - toIndex: destination index
    func reorderHooksInChain(for layer: Int, fromIndex: Int, toIndex: Int) {
        guard var definition = effectDefinition(for: layer) else { return }
        guard var hooks = definition.hooks else { return }
        guard fromIndex >= 0, fromIndex < hooks.count, toIndex >= 0, toIndex < hooks.count else { return }

        let hook = hooks.remove(at: fromIndex)
        hooks.insert(hook, at: toIndex)
        definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)

        setEffect(from: definition, for: layer)
    }

    /// Reset a hook's parameters to defaults in the recipe
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - hookIndex: index of the hook to reset
    func resetHookToDefaults(for layer: Int, hookIndex: Int) {
        guard var definition = effectDefinition(for: layer) else { return }
        guard var hooks = definition.hooks, hookIndex >= 0, hookIndex < hooks.count else { return }

        var hook = hooks[hookIndex]
        guard let hookType = hook.resolvedType else { return }

        // Get defaults from registry, preserve _enabled state
        var defaults = EffectRegistry.defaults(for: hookType)
        if let wasEnabled = hook.params?["_enabled"] {
            defaults["_enabled"] = wasEnabled
        }

        hook = EffectDefinition(name: hook.name, type: hook.type, params: defaults, hooks: hook.hooks)
        hooks[hookIndex] = hook
        definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)

        setEffect(from: definition, for: layer)
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

    /// Set source effect from a definition - stores definition and instantiates hook
    func setSourceEffect(from definition: EffectDefinition?, for sourceIndex: Int) {
        sourceEffectDefinitionSetter?(sourceIndex, definition)
        if let def = definition, let hook = EffectConfigLoader.instantiateEffect(def) {
            sourceEffectSetter?(sourceIndex, [hook])
        } else {
            sourceEffectSetter?(sourceIndex, [])
        }
        onEffectChanged?()
    }

    /// Get a source's effect definition (for editing)
    func sourceEffectDefinition(for sourceIndex: Int) -> EffectDefinition? {
        guard let recipe = recipeProvider?(),
              sourceIndex >= 0,
              sourceIndex < recipe.sources.count else {
            return nil
        }
        return recipe.sources[sourceIndex].effectDefinition
    }

    func cycleSourceEffect(for sourceIndex: Int) {
        let currentName = sourceEffectName(for: sourceIndex)
        let currentIndex = Effect.all.firstIndex { $0.name == currentName } ?? -1
        let nextIndex = (currentIndex + 2) % (Effect.all.count + 1) - 1
        setSourceEffect(nextIndex >= 0 ? Effect.all[nextIndex] : nil, for: sourceIndex)
    }

    // MARK: - Unified Layer API (layer -1 = global, 0+ = source)

    /// Get effect name for a layer (-1 = global, 0+ = source index)
    func effectName(for layer: Int) -> String {
        if layer == -1 {
            return globalEffectName
        }
        return sourceEffectName(for: layer)
    }

    /// Get effect definition for a layer (-1 = global, 0+ = source index)
    func effectDefinition(for layer: Int) -> EffectDefinition? {
        if layer == -1 {
            return globalEffectDefinition
        }
        return sourceEffectDefinition(for: layer)
    }

    /// Set effect for a layer (-1 = global, 0+ = source index)
    func setEffect(_ effect: RenderHook?, for layer: Int) {
        if layer == -1 {
            setGlobalEffect(effect)
        } else {
            setSourceEffect(effect, for: layer)
        }
    }

    /// Set effect from a definition for a layer (-1 = global, 0+ = source index)
    /// This is the preferred method for selecting effects from the library
    func setEffect(from definition: EffectDefinition?, for layer: Int) {
        if layer == -1 {
            setGlobalEffect(from: definition)
        } else {
            setSourceEffect(from: definition, for: layer)
        }
    }

    /// Cycle effect for a layer (-1 = global, 0+ = source index)
    /// direction: 1 = forward, -1 = backward
    func cycleEffect(for layer: Int, direction: Int = 1) {
        // Clear frame buffer and reset frame counter so new effect starts fresh
        frameBuffer.clear()
        resetFrameIndex()

        let currentName = effectName(for: layer)
        let currentIndex = Effect.all.firstIndex { $0.name == currentName } ?? -1

        // Cycle through effects: -1 (None) -> 0 -> 1 -> ... -> count-1 -> -1
        let effectCount = Effect.all.count
        let totalStates = effectCount + 1  // +1 for "None"

        // Convert to 0-based index where 0 = None, 1+ = effects
        let current0Based = currentIndex + 1
        let next0Based = (current0Based + direction + totalStates) % totalStates
        let nextIndex = next0Based - 1  // Back to -1 based

        setEffect(nextIndex >= 0 ? Effect.all[nextIndex] : nil, for: layer)
    }

    /// Clear effect for a specific layer (-1 = global, 0+ = source index)
    func clearEffect(for layer: Int) {
        setEffect(nil, for: layer)
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

        // Update frame buffer with processed result so temporal effects see prior effects
        frameBuffer.addFrame(result, at: context.time)

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
