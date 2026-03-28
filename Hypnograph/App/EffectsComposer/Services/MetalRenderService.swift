//
//  MetalRenderService.swift
//  Hypnograph
//

import Foundation
import CoreImage
import Metal
import AppKit
import HypnoCore

enum MetalRenderServiceError: LocalizedError {
    case effectFunctionNotFound(String)
    case signatureMismatch(String)
    case missingParameterBufferLayout
    case missingOutputImage

    var errorDescription: String? {
        switch self {
        case .effectFunctionNotFound(let name):
            return "Compile succeeded, but function '\(name)' was not found."
        case .signatureMismatch(let message):
            return message
        case .missingParameterBufferLayout:
            return "Compile succeeded, but could not infer parameter buffer layout."
        case .missingOutputImage:
            return "Failed to convert rendered output texture into a preview image."
        }
    }
}

struct MetalRenderService {
    struct CompileResult {
        var pipelineState: MTLComputePipelineState
        var parameterBufferLayout: EffectsComposerParamBufferLayout?
    }

    struct ParameterBufferBytes {
        var index: Int
        var bytes: Data
    }

    struct RenderResult {
        var ciImage: CIImage
        var nsImage: NSImage
    }

    static let live = MetalRenderService()

    func compile(
        device: MTLDevice,
        sourceCode: String,
        parameters: [EffectsComposerParameterDraft],
        effectFunctionName: String,
        activeBindings: RuntimeMetalBindingsManifest
    ) throws -> CompileResult {
        let generatedSource: String
        if sourceContainsHypnoParamsStruct(sourceCode) {
            generatedSource = sourceCode
        } else {
            generatedSource = generatedParamStructSource(parameters: parameters) + "\n\n" + sourceCode
        }

        let library = try device.makeLibrary(source: generatedSource, options: nil)
        guard let function = library.makeFunction(name: effectFunctionName) else {
            throw MetalRenderServiceError.effectFunctionNotFound(effectFunctionName)
        }

        var reflection: MTLAutoreleasedComputePipelineReflection?
        let pipeline = try device.makeComputePipelineState(
            function: function,
            options: [.argumentInfo, .bufferTypeInfo],
            reflection: &reflection
        )

        let args = reflection?.arguments.filter(\.isActive) ?? []
        if let signatureError = validateSignature(arguments: args, activeBindings: activeBindings) {
            throw MetalRenderServiceError.signatureMismatch(signatureError)
        }

        let layout = buildParameterBufferLayout(arguments: args, activeBindings: activeBindings)
        if activeBindings.parameterBufferIndex != nil && layout == nil {
            throw MetalRenderServiceError.missingParameterBufferLayout
        }

        return CompileResult(
            pipelineState: pipeline,
            parameterBufferLayout: layout
        )
    }

    func makeTexture(
        from image: CIImage,
        width: Int,
        height: Int,
        device: MTLDevice,
        ciContext: CIContext,
        colorSpace: CGColorSpace
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        ciContext.render(image, to: texture, commandBuffer: nil, bounds: image.extent, colorSpace: colorSpace)
        return texture
    }

    func render(
        pipelineState: MTLComputePipelineState,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        activeBindings: RuntimeMetalBindingsManifest,
        inputTextures: [Int: MTLTexture],
        parameterBuffer: ParameterBufferBytes?,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) throws -> RenderResult {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let outputTexture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalRenderServiceError.missingOutputImage
        }

        encoder.setComputePipelineState(pipelineState)

        var boundTextures = inputTextures
        boundTextures[activeBindings.outputTextureIndex] = outputTexture
        for index in boundTextures.keys.sorted() {
            encoder.setTexture(boundTextures[index], index: index)
        }

        if let parameterBuffer {
            parameterBuffer.bytes.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setBytes(base, length: parameterBuffer.bytes.count, index: parameterBuffer.index)
            }
        }

        let threadWidth = pipelineState.threadExecutionWidth
        let threadHeight = max(1, pipelineState.maxTotalThreadsPerThreadgroup / max(threadWidth, 1))
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

        guard let ciOutput = CIImage(mtlTexture: outputTexture, options: [.colorSpace: colorSpace]) else {
            throw MetalRenderServiceError.missingOutputImage
        }

        let rep = NSCIImageRep(ciImage: ciOutput)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return RenderResult(ciImage: ciOutput, nsImage: image)
    }

    private func generatedParamStructSource(parameters: [EffectsComposerParameterDraft]) -> String {
        var lines: [String] = [
            "struct HypnoParams {"
        ]

        if parameters.isEmpty {
            lines.append("    float _studioUnused;")
        } else {
            for param in parameters {
                let name = param.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                lines.append("    \(param.type.metalType) \(name);")
            }
        }

        lines.append("};")
        return lines.joined(separator: "\n")
    }

    private func sourceContainsHypnoParamsStruct(_ sourceCode: String) -> Bool {
        if let regex = try? NSRegularExpression(pattern: #"\bstruct\s+HypnoParams\b"#) {
            let range = NSRange(sourceCode.startIndex..<sourceCode.endIndex, in: sourceCode)
            return regex.firstMatch(in: sourceCode, options: [], range: range) != nil
        }
        return sourceCode.contains("struct HypnoParams")
    }

    private func validateSignature(arguments: [MTLArgument], activeBindings: RuntimeMetalBindingsManifest) -> String? {
        let activeTextureIndices = Set(
            arguments
                .filter { $0.type == .texture }
                .map { Int($0.index) }
        )

        var expectedTextureIndices = Set(activeBindings.inputTextures.map(\.argumentIndex))
        expectedTextureIndices.insert(activeBindings.outputTextureIndex)
        if activeTextureIndices != expectedTextureIndices {
            let missing = expectedTextureIndices.subtracting(activeTextureIndices).sorted()
            let extra = activeTextureIndices.subtracting(expectedTextureIndices).sorted()
            return "Texture bindings mismatch. Missing: \(missing), extra: \(extra)."
        }

        let textureArgs = arguments.filter { $0.type == .texture }
        guard let outputArg = textureArgs.first(where: { Int($0.index) == activeBindings.outputTextureIndex }) else {
            return "Output texture must be declared at texture(\(activeBindings.outputTextureIndex))."
        }
        if outputArg.access == .readOnly {
            return "Output texture at texture(\(activeBindings.outputTextureIndex)) must be write or read_write."
        }

        if let parameterBufferIndex = activeBindings.parameterBufferIndex {
            let activeBufferIndices = Set(
                arguments
                    .filter { $0.type == .buffer }
                    .map { Int($0.index) }
            )
            if !activeBufferIndices.contains(parameterBufferIndex) {
                return "Metal code must declare constant HypnoParams& params at buffer(\(parameterBufferIndex))."
            }
        }

        return nil
    }

    private func buildParameterBufferLayout(
        arguments: [MTLArgument],
        activeBindings: RuntimeMetalBindingsManifest
    ) -> EffectsComposerParamBufferLayout? {
        guard let parameterBufferIndex = activeBindings.parameterBufferIndex,
              let bufferArg = arguments.first(where: { $0.type == .buffer && Int($0.index) == parameterBufferIndex }) else {
            return nil
        }

        let members: [EffectsComposerParamBufferMemberLayout]
        if let structType = bufferArg.bufferStructType {
            members = structType.members
                .sorted { $0.offset < $1.offset }
                .compactMap { member in
                    guard let valueType = EffectsComposerParameterModeling.scalarType(for: member.dataType),
                          let size = EffectsComposerParameterModeling.scalarSize(for: valueType) else {
                        return nil
                    }

                    return EffectsComposerParamBufferMemberLayout(
                        name: member.name,
                        offset: Int(member.offset),
                        size: size,
                        valueType: valueType
                    )
                }
        } else {
            members = []
        }

        return EffectsComposerParamBufferLayout(
            length: max(Int(bufferArg.bufferDataSize), 1),
            members: members
        )
    }
}
