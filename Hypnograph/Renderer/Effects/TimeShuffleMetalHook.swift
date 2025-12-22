//
//  TimeShuffleMetalHook.swift
//  Hypnograph
//
//  Time shuffle - swaps chunks of frames out of order.
//  Screen regions show different temporal chunks, like scrambled tape.
//  Simple and organic degradation feel.
//

import Foundation
import CoreImage
import CoreVideo
import Metal

/// GPU parameters - must match TimeShuffleShader.metal
struct TimeShuffleParamsGPU {
    var textureWidth: Int32
    var textureHeight: Int32
    var numRegions: Int32
    var chunkSize: Int32
    var maxHistoryFrames: Int32
    var shuffleSeed: UInt32
}

/// Time shuffle - regions show different chunks of frame history
final class TimeShuffleMetalHook: RenderHook {

    // MARK: - Parameter Specs

    static var parameterSpecs: [String: ParameterSpec] {
        [
            "numRegions": .int(default: 4, range: 2...8),
            "chunkSize": .int(default: 20, range: 15...60),
            "shuffleRate": .float(default: 0.02, range: 0...0.2)
        ]
    }

    // MARK: - Properties

    var name: String { "Time Shuffle" }
    var requiredLookback: Int { 300 }  // Need deep history for chunks

    var numRegions: Int      // How many horizontal bands
    var chunkSize: Int       // Frames per chunk
    var shuffleRate: Float   // Probability of reshuffling per frame

    // Metal state
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var pipelineState: MTLComputePipelineState?
    private var textureCache: CVMetalTextureCache?

    // Output buffer
    private var outputBuffer: CVPixelBuffer?

    // Shuffle state
    private var currentSeed: UInt32 = 0
    private var frameCounter: Int = 0

    // MARK: - Init

    init(numRegions: Int = 4, chunkSize: Int = 20, shuffleRate: Float = 0.02) {
        self.numRegions = max(2, min(8, numRegions))
        self.chunkSize = max(15, min(60, chunkSize))
        self.shuffleRate = max(0, min(0.2, shuffleRate))

        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()

        if let device = device {
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            self.textureCache = cache
        }

        loadShader()
    }

    private func loadShader() {
        guard let device = device else { return }

        do {
            let library = try device.makeDefaultLibrary(bundle: Bundle.main)
            guard let function = library.makeFunction(name: "timeShuffleKernel") else {
                print("⚠️ TimeShuffleMetalHook: Kernel not found")
                return
            }
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            print("⚠️ TimeShuffleMetalHook: Pipeline error: \(error)")
        }
    }

    private func ensureOutputBuffer(width: Int, height: Int) {
        if let buf = outputBuffer,
           CVPixelBufferGetWidth(buf) == width,
           CVPixelBufferGetHeight(buf) == height {
            return
        }

        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                           kCVPixelFormatType_32BGRA, attrs as CFDictionary, &outputBuffer)
    }

    private func textureFromBuffer(_ buffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, buffer, nil, .bgra8Unorm, w, h, 0, &cvTex
        )
        guard status == kCVReturnSuccess, let tex = cvTex else { return nil }
        return CVMetalTextureGetTexture(tex)
    }

    // MARK: - RenderHook Protocol

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        frameCounter += 1

        // Randomly reshuffle based on shuffleRate
        if Float.random(in: 0...1) < shuffleRate {
            currentSeed = UInt32.random(in: 0..<UInt32.max)
        }

        // Need some history, but start earlier
        let frameCount = context.frameBuffer.frameCount
        guard frameCount >= chunkSize else { return image }

        guard let device = device,
              let commandQueue = commandQueue,
              let pipeline = pipelineState else {
            return image
        }

        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else { return image }

        // Generate 8 random offsets based on current seed
        // Each texture samples from a random point in available history
        var historyTextures: [MTLTexture] = []
        var rng = currentSeed
        for _ in 0..<8 {
            // Simple LCG for deterministic randomness from seed
            rng = rng &* 1103515245 &+ 12345
            let maxOffset = max(1, frameCount - 1)
            // Ensure minimum chunk separation but randomize within available range
            let randomOffset = Int(rng % UInt32(maxOffset))
            let clampedOffset = max(chunkSize, min(randomOffset, frameCount - 1))

            if let tex = context.frameBuffer.texture(atHistoryOffset: clampedOffset) {
                historyTextures.append(tex)
            }
        }

        guard historyTextures.count == 8 else { return image }

        ensureOutputBuffer(width: width, height: height)
        guard let outBuf = outputBuffer,
              let outputTexture = textureFromBuffer(outBuf) else {
            return image
        }

        var gpuParams = TimeShuffleParamsGPU(
            textureWidth: Int32(width),
            textureHeight: Int32(height),
            numRegions: Int32(numRegions),
            chunkSize: Int32(chunkSize),
            maxHistoryFrames: Int32(frameCount),
            shuffleSeed: currentSeed
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return image
        }

        encoder.setComputePipelineState(pipeline)
        for (i, tex) in historyTextures.enumerated() {
            encoder.setTexture(tex, index: i)
        }
        encoder.setTexture(outputTexture, index: 8)
        encoder.setBytes(&gpuParams, length: MemoryLayout<TimeShuffleParamsGPU>.stride, index: 0)

        let threadWidth = pipeline.threadExecutionWidth
        let threadHeight = pipeline.maxTotalThreadsPerThreadgroup / threadWidth
        let threadsPerGroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        let threadgroups = MTLSize(
            width: (width + threadWidth - 1) / threadWidth,
            height: (height + threadHeight - 1) / threadHeight,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return CIImage(cvPixelBuffer: outBuf)
    }

    func reset() {
        outputBuffer = nil
        currentSeed = 0
        frameCounter = 0
    }

    func copy() -> RenderHook {
        TimeShuffleMetalHook(numRegions: numRegions, chunkSize: chunkSize, shuffleRate: shuffleRate)
    }
}

