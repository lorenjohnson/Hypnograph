//
//  MetalRenderState.swift
//  Hypnograph
//

import Foundation
import CoreImage
import CoreMedia
import Metal
import AppKit
import HypnoCore

extension EffectsComposerViewModel {
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
            let compileResult = try metalRenderService.compile(
                device: device,
                sourceCode: sourceCode,
                parameters: parameters,
                effectFunctionName: effectFunctionName,
                activeBindings: activeBindings
            )

            pipelineState = compileResult.pipelineState
            parameterBufferLayout = compileResult.parameterBufferLayout
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

        guard let inputTexture = metalRenderService.makeTexture(
            from: baseImage,
            width: width,
            height: height,
            device: device,
            ciContext: ciContext,
            colorSpace: colorSpace
        ) else {
            return
        }

        var inputTextures: [Int: MTLTexture] = [:]
        for binding in activeBindings.inputTextures {
            switch binding.source {
            case .currentFrame:
                inputTextures[binding.argumentIndex] = inputTexture

            case .historyFrame:
                let offset = resolvedHistoryOffset(for: binding)
                let historyImage = previewHistoryImage(offset: offset, fallback: baseImage)
                guard let historyTexture = metalRenderService.makeTexture(
                    from: historyImage,
                    width: width,
                    height: height,
                    device: device,
                    ciContext: ciContext,
                    colorSpace: colorSpace
                ) else {
                    return
                }
                inputTextures[binding.argumentIndex] = historyTexture
            }
        }

        var parameterBuffer: MetalRenderService.ParameterBufferBytes?
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
            parameterBuffer = .init(index: parameterBufferIndex, bytes: paramsBytes)
        }

        do {
            let result = try metalRenderService.render(
                pipelineState: pipelineState,
                device: device,
                commandQueue: commandQueue,
                activeBindings: activeBindings,
                inputTextures: inputTextures,
                parameterBuffer: parameterBuffer,
                width: width,
                height: height,
                colorSpace: colorSpace
            )
            previewImage = result.nsImage
            appendPreviewHistory(image: result.ciImage)
            frameCounter &+= 1
        } catch {
            compileLog = "Render failed: \(error.localizedDescription)"
        }
    }

    private func validateParameterDrafts() -> [String] {
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

    private func fillParameterBuffer(
        data: inout Data,
        layout: EffectsComposerParamBufferLayout,
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

    private func resolvedParameterValue(
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

    private func writeScalar<T>(_ value: T, into data: inout Data, offset: Int, size: Int) {
        guard offset >= 0, size > 0 else { return }
        let byteCount = MemoryLayout<T>.size
        guard byteCount <= size, offset + byteCount <= data.count else { return }
        var mutableValue = value
        withUnsafeBytes(of: &mutableValue) { bytes in
            data.replaceSubrange(offset..<(offset + byteCount), with: bytes)
        }
    }

    private func resolvedIntValue(for parameterName: String, from value: AnyCodableValue) -> Int? {
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

    func resetPreviewHistory() {
        previewFrameHistory.removeAll(keepingCapacity: true)
        frameCounter = 0
    }

    private func appendPreviewHistory(image: CIImage) {
        previewFrameHistory.insert(image, at: 0)
        let historyLimit = max(1, previewHistoryLimit())
        if previewFrameHistory.count > historyLimit {
            previewFrameHistory.removeLast(previewFrameHistory.count - historyLimit)
        }
    }

    private func previewHistoryImage(offset: Int, fallback: CIImage) -> CIImage {
        let index = max(0, offset - 1)
        guard index < previewFrameHistory.count else { return fallback }
        return previewFrameHistory[index]
    }

    private func previewHistoryLimit() -> Int {
        let maxBindingOffset = activeBindings.inputTextures.reduce(0) { partial, binding in
            guard binding.source == .historyFrame else { return partial }
            return max(partial, resolvedHistoryOffset(for: binding))
        }
        return max(2, max(activeRequiredLookback, maxBindingOffset) + 2)
    }

    private func resolvedHistoryOffset(for binding: RuntimeMetalTextureBindingManifest) -> Int {
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
