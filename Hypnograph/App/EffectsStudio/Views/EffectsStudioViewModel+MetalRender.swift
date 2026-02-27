//
//  EffectsStudioViewModel+MetalRender.swift
//  Hypnograph
//

import Foundation
import CoreImage
import CoreMedia
import Metal
import AppKit
import HypnoCore

extension EffectsStudioViewModel {
    @discardableResult
    func compileCode() -> Bool {
        guard let device else {
            pipelineState = nil
            parameterBufferLayout = nil
            compileLog = "Metal device unavailable."
            return false
        }

        do {
            let validationProblems = validateParameterDrafts()
            if !validationProblems.isEmpty {
                compileLog = "Fix parameter issues before compile:\n- " + validationProblems.joined(separator: "\n- ")
                return false
            }

            let generatedSource: String
            if sourceContainsHypnoParamsStruct {
                generatedSource = sourceCode
            } else {
                generatedSource = generatedParamStructSource() + "\n\n" + sourceCode
            }
            let library = try device.makeLibrary(source: generatedSource, options: nil)

            guard let function = library.makeFunction(name: effectFunctionName) else {
                compileLog = "Compile succeeded, but function '\(effectFunctionName)' was not found."
                return false
            }

            var reflection: MTLAutoreleasedComputePipelineReflection?
            let pipeline = try device.makeComputePipelineState(
                function: function,
                options: [.argumentInfo, .bufferTypeInfo],
                reflection: &reflection
            )

            let args = reflection?.arguments.filter(\.isActive) ?? []
            if let signatureError = validateSignature(arguments: args) {
                pipelineState = nil
                parameterBufferLayout = nil
                compileLog = signatureError
                return false
            }

            let layout = buildParameterBufferLayout(arguments: args)
            if activeBindings.parameterBufferIndex != nil && layout == nil {
                pipelineState = nil
                parameterBufferLayout = nil
                compileLog = "Compile succeeded, but could not infer parameter buffer layout."
                return false
            }

            pipelineState = pipeline
            parameterBufferLayout = layout
            compileLog = "Compiled successfully. Kernel '\(effectFunctionName)' is ready."
            resetPreviewHistory()
            renderPreview()
            return true
        } catch {
            pipelineState = nil
            parameterBufferLayout = nil
            compileLog = "Compile failed:\n\(error.localizedDescription)"
            return false
        }
    }

    func renderPreview() {
        guard let pipelineState,
              let device,
              let commandQueue else {
            return
        }

        let baseImage = currentSourceImage(time: time)
        let width = Int(previewSize.width)
        let height = Int(previewSize.height)
        guard width > 0, height > 0 else { return }

        guard let inputTexture = makeTexture(from: baseImage, width: width, height: height, device: device) else {
            return
        }

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
            return
        }

        encoder.setComputePipelineState(pipelineState)

        var boundTextures: [Int: MTLTexture] = [:]
        for binding in activeBindings.inputTextures {
            switch binding.source {
            case .currentFrame:
                boundTextures[binding.argumentIndex] = inputTexture

            case .historyFrame:
                let offset = resolvedHistoryOffset(for: binding)
                let historyImage = previewHistoryImage(offset: offset, fallback: baseImage)
                guard let historyTexture = makeTexture(from: historyImage, width: width, height: height, device: device) else {
                    return
                }
                boundTextures[binding.argumentIndex] = historyTexture
            }
        }
        boundTextures[activeBindings.outputTextureIndex] = outputTexture

        for index in boundTextures.keys.sorted() {
            encoder.setTexture(boundTextures[index], index: index)
        }

        if let parameterBufferIndex = activeBindings.parameterBufferIndex,
           let parameterBufferLayout {
            var paramsBytes = Data(count: max(parameterBufferLayout.length, 1))
            fillParameterBuffer(
                data: &paramsBytes,
                layout: parameterBufferLayout,
                width: width,
                height: height,
                frameIndex: Int(frameCounter),
                time: CMTime(seconds: time, preferredTimescale: 600)
            )

            paramsBytes.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setBytes(base, length: paramsBytes.count, index: parameterBufferIndex)
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
            return
        }

        let rep = NSCIImageRep(ciImage: ciOutput)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        previewImage = image
        appendPreviewHistory(image: ciOutput)
        frameCounter &+= 1
    }

    func validateParameterDrafts() -> [String] {
        var issues: [String] = []
        var seen: Set<String> = []

        for param in parameters {
            let trimmed = param.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                issues.append("Parameter names cannot be empty.")
                continue
            }
            if !Self.isValidIdentifier(trimmed) {
                issues.append("'\(trimmed)' is not a valid Metal identifier.")
            }
            if seen.contains(trimmed) {
                issues.append("Duplicate parameter name '\(trimmed)'.")
            }
            seen.insert(trimmed)

            if param.type.usesNumericRange {
                if param.maxNumber <= param.minNumber {
                    issues.append("'\(trimmed)' max must be greater than min.")
                }
                if param.type == .uint && (param.minNumber < 0 || param.defaultNumber < 0 || param.maxNumber < 0) {
                    issues.append("'\(trimmed)' uint values must be non-negative.")
                }
            } else if param.type == .choice {
                let options = Self.sanitizedChoiceOptions(for: param)
                if options.isEmpty {
                    issues.append("'\(trimmed)' choice parameters need at least one option.")
                }
                if Self.resolvedChoiceDefaultKey(for: param, options: options).isEmpty {
                    issues.append("'\(trimmed)' choice parameters need a default option.")
                }
            }
        }

        return issues
    }

    func generatedParamStructSource() -> String {
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

    var sourceContainsHypnoParamsStruct: Bool {
        if let regex = try? NSRegularExpression(pattern: #"\bstruct\s+HypnoParams\b"#) {
            let range = NSRange(sourceCode.startIndex..<sourceCode.endIndex, in: sourceCode)
            return regex.firstMatch(in: sourceCode, options: [], range: range) != nil
        }
        return sourceCode.contains("struct HypnoParams")
    }

    func validateSignature(arguments: [MTLArgument]) -> String? {
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

    func buildParameterBufferLayout(arguments: [MTLArgument]) -> EffectsStudioParamBufferLayout? {
        guard let parameterBufferIndex = activeBindings.parameterBufferIndex,
              let bufferArg = arguments.first(where: { $0.type == .buffer && Int($0.index) == parameterBufferIndex }) else {
            return nil
        }

        let members: [EffectsStudioParamBufferMemberLayout]
        if let structType = bufferArg.bufferStructType {
            members = structType.members
                .sorted { $0.offset < $1.offset }
                .compactMap { member in
                    guard let valueType = Self.scalarType(for: member.dataType),
                          let size = Self.scalarSize(for: valueType) else {
                        return nil
                    }

                    return EffectsStudioParamBufferMemberLayout(
                        name: member.name,
                        offset: Int(member.offset),
                        size: size,
                        valueType: valueType
                    )
                }
        } else {
            members = []
        }

        return EffectsStudioParamBufferLayout(
            length: max(Int(bufferArg.bufferDataSize), 1),
            members: members
        )
    }

    func fillParameterBuffer(
        data: inout Data,
        layout: EffectsStudioParamBufferLayout,
        width: Int,
        height: Int,
        frameIndex: Int,
        time: CMTime
    ) {
        for member in layout.members {
            let value = resolvedParameterValue(
                named: member.name,
                width: width,
                height: height,
                frameIndex: frameIndex,
                time: time
            )

            switch member.valueType {
            case .float:
                let encoded = Float(value.doubleValue ?? Double(value.intValue ?? 0))
                writeScalar(encoded, into: &data, offset: member.offset, size: member.size)

            case .int:
                let encodedValue = resolvedIntValue(for: member.name, from: value) ?? 0
                let encoded = Int32(encodedValue)
                writeScalar(encoded, into: &data, offset: member.offset, size: member.size)

            case .uint:
                let raw = resolvedIntValue(for: member.name, from: value) ?? 0
                let encoded = UInt32(max(0, raw))
                writeScalar(encoded, into: &data, offset: member.offset, size: member.size)

            case .bool:
                let encoded: UInt8 = (value.boolValue ?? false) ? 1 : 0
                writeScalar(encoded, into: &data, offset: member.offset, size: member.size)
            }
        }
    }

    func resolvedParameterValue(
        named name: String,
        width: Int,
        height: Int,
        frameIndex: Int,
        time: CMTime
    ) -> AnyCodableValue {
        if let draft = parameters.first(where: { $0.name == name }) {
            switch draft.autoBind {
            case .timeSeconds:
                return .double(CMTimeGetSeconds(time))
            case .textureWidth:
                return .int(width)
            case .textureHeight:
                return .int(height)
            case .frameIndex:
                return .int(frameIndex)
            case .none:
                break
            }
        }

        if let value = parameterValues[name] {
            return value
        }
        if let draft = parameters.first(where: { $0.name == name }) {
            return Self.defaultValue(for: draft)
        }
        return .double(0)
    }

    func writeScalar<T>(_ value: T, into data: inout Data, offset: Int, size: Int) {
        guard offset >= 0, size > 0 else { return }
        let byteCount = MemoryLayout<T>.size
        guard byteCount <= size, offset + byteCount <= data.count else { return }
        var mutableValue = value
        withUnsafeBytes(of: &mutableValue) { bytes in
            data.replaceSubrange(offset..<(offset + byteCount), with: bytes)
        }
    }

    func resolvedIntValue(for parameterName: String, from value: AnyCodableValue) -> Int? {
        if let intValue = value.intValue {
            return intValue
        }
        if let boolValue = value.boolValue {
            return boolValue ? 1 : 0
        }
        if let stringValue = value.stringValue,
           let spec = parameterSpec(named: parameterName),
           case .choice(_, let options) = spec {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if let index = options.firstIndex(where: { $0.key == trimmed }) {
                return index
            }
            if let index = options.firstIndex(where: { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return index
            }
            if let index = options.firstIndex(where: { $0.label == trimmed }) {
                return index
            }
            if let index = options.firstIndex(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return index
            }
            if let parsedIndex = Int(trimmed), options.indices.contains(parsedIndex) {
                return parsedIndex
            }
        }
        if let doubleValue = value.doubleValue {
            return Int(doubleValue.rounded())
        }
        return nil
    }

    func makeTexture(from image: CIImage, width: Int, height: Int, device: MTLDevice) -> MTLTexture? {
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

    func resetPreviewHistory() {
        previewFrameHistory.removeAll(keepingCapacity: true)
        frameCounter = 0
    }

    func appendPreviewHistory(image: CIImage) {
        previewFrameHistory.insert(image, at: 0)
        let historyLimit = max(1, previewHistoryLimit())
        if previewFrameHistory.count > historyLimit {
            previewFrameHistory.removeLast(previewFrameHistory.count - historyLimit)
        }
    }

    func previewHistoryImage(offset: Int, fallback: CIImage) -> CIImage {
        let index = max(0, offset - 1)
        guard index < previewFrameHistory.count else { return fallback }
        return previewFrameHistory[index]
    }

    func previewHistoryLimit() -> Int {
        let maxBindingOffset = activeBindings.inputTextures.reduce(0) { partial, binding in
            guard binding.source == .historyFrame else { return partial }
            return max(partial, resolvedHistoryOffset(for: binding))
        }
        return max(2, max(activeRequiredLookback, maxBindingOffset) + 2)
    }

    func resolvedHistoryOffset(for binding: RuntimeMetalTextureBindingManifest) -> Int {
        if let parameterName = binding.historyOffsetParameter {
            let runtimeValue = parameterValues[parameterName]
            let parameterDefault: AnyCodableValue? = {
                guard let draft = parameters.first(where: { $0.name == parameterName }) else { return nil }
                return Self.defaultValue(for: draft)
            }()
            let runtimeDouble = runtimeValue?.doubleValue
            let runtimeIntDouble = runtimeValue?.intValue.map(Double.init)
            let defaultDouble = parameterDefault?.doubleValue
            let defaultIntDouble = parameterDefault?.intValue.map(Double.init)
            let fallback = Double(binding.historyOffset ?? 1)
            let raw = runtimeDouble ?? runtimeIntDouble ?? defaultDouble ?? defaultIntDouble ?? fallback
            let scale = binding.historyOffsetScale ?? 1.0
            let bias = Double(binding.historyOffsetBias ?? 0)
            let computed = Int((raw * scale + bias).rounded())
            return max(1, computed)
        }

        return max(binding.historyOffset ?? 1, 1)
    }
}
