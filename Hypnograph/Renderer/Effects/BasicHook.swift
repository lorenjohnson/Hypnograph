//
//  BasicHook.swift
//  Hypnograph
//
//  Basic image adjustments via Metal compute shader.
//  Provides opacity, contrast, brightness, and saturation controls.
//

import Foundation
import CoreImage
import Metal

/// GPU parameters struct - must match layout in BasicShader.metal
struct BasicParamsGPU {
    var opacity: Float
    var contrast: Float
    var brightness: Float
    var saturation: Float
    var hueShift: Float
    var colorizeHue: Float
    var colorizeAmount: Float
    var textureWidth: Int32
    var textureHeight: Int32
}

/// Basic image adjustments effect.
/// Provides opacity, contrast, brightness, and saturation controls.
final class BasicHook: RenderHook {

    // MARK: - Parameter Specs (source of truth)

    static var parameterSpecs: [String: ParameterSpec] {
        [
            "opacity": .float(default: 1.0, range: 0...1),
            "contrast": .float(default: 0.0, range: -1...1),
            "brightness": .float(default: 0.0, range: -1...1),
            "saturation": .float(default: 0.0, range: -1...1),
            "hueShift": .float(default: 0.0, range: -1...1),
            "colorizeHue": .float(default: 0.0, range: 0...1),
            "colorizeAmount": .float(default: 0.0, range: 0...1)
        ]
    }

    // MARK: - Properties

    var name: String { customName ?? "Basic" }
    var requiredLookback: Int { 0 }  // No frame history needed

    // MARK: - Configuration

    private let customName: String?
    var opacity: Float
    var contrast: Float
    var brightness: Float
    var saturation: Float
    var hueShift: Float
    var colorizeHue: Float
    var colorizeAmount: Float

    // MARK: - Metal State

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var pipelineState: MTLComputePipelineState?
    private let ciContext: CIContext

    // MARK: - Init

    init(opacity: Float = 1.0, contrast: Float = 0.0, brightness: Float = 0.0,
         saturation: Float = 0.0, hueShift: Float = 0.0,
         colorizeHue: Float = 0.0, colorizeAmount: Float = 0.0, name: String? = nil) {
        self.opacity = max(0, min(1, opacity))
        self.contrast = max(-1, min(1, contrast))
        self.brightness = max(-1, min(1, brightness))
        self.saturation = max(-1, min(1, saturation))
        self.hueShift = max(-1, min(1, hueShift))
        self.colorizeHue = max(0, min(1, colorizeHue))
        self.colorizeAmount = max(0, min(1, colorizeAmount))
        self.customName = name
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()

        // Create CIContext backed by Metal for efficient texture conversion
        if let device = device {
            self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            self.ciContext = CIContext()
        }

        loadShader()
    }

    private func loadShader() {
        guard let device = device else {
            print("⚠️ BasicHook: No Metal device")
            return
        }

        do {
            let library = try device.makeDefaultLibrary(bundle: Bundle.main)
            guard let function = library.makeFunction(name: "basicKernel") else {
                print("⚠️ BasicHook: Kernel function not found")
                return
            }
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            print("⚠️ BasicHook: Failed to create pipeline: \(error)")
        }
    }
    
    // MARK: - RenderHook Protocol

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        guard let device = device,
              let commandQueue = commandQueue,
              let pipeline = pipelineState else {
            return image
        }

        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)

        guard width > 0, height > 0 else { return image }

        // Create textures
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]

        guard let inputTexture = device.makeTexture(descriptor: textureDescriptor),
              let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            return image
        }

        // Render CIImage to input texture
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        ciContext.render(image, to: inputTexture, commandBuffer: nil, bounds: extent, colorSpace: colorSpace)

        // Setup GPU params
        var gpuParams = BasicParamsGPU(
            opacity: opacity,
            contrast: contrast,
            brightness: brightness,
            saturation: saturation,
            hueShift: hueShift,
            colorizeHue: colorizeHue,
            colorizeAmount: colorizeAmount,
            textureWidth: Int32(width),
            textureHeight: Int32(height)
        )

        // Run compute shader
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return image
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(&gpuParams, length: MemoryLayout<BasicParamsGPU>.stride, index: 0)

        // Calculate threadgroup size
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

        // Convert back to CIImage
        guard let outputImage = CIImage(mtlTexture: outputTexture, options: [.colorSpace: colorSpace]) else {
            return image
        }

        return outputImage
    }

    func copy() -> RenderHook {
        BasicHook(opacity: opacity, contrast: contrast, brightness: brightness,
                  saturation: saturation, hueShift: hueShift,
                  colorizeHue: colorizeHue, colorizeAmount: colorizeAmount, name: customName)
    }
}

