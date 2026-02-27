//
//  EffectsStudioViewModel.swift
//  Hypnograph
//

import SwiftUI
import AppKit
import CoreImage
import AVFoundation
import UniformTypeIdentifiers
import Metal
import Foundation
import HypnoCore

private enum EffectsStudioScalarValueType {
    case float
    case int
    case uint
    case bool
}

private struct EffectsStudioParamBufferMemberLayout {
    var name: String
    var offset: Int
    var size: Int
    var valueType: EffectsStudioScalarValueType
}

private struct EffectsStudioParamBufferLayout {
    var length: Int
    var members: [EffectsStudioParamBufferMemberLayout]
}
@MainActor
final class EffectsStudioViewModel: ObservableObject {
    private let settingsStore: EffectsStudioSettingsStore

    @Published var runtimeEffectUUID: String = UUID().uuidString.lowercased()
    @Published var runtimeEffectName: String = "New Effect"
    @Published var runtimeEffectVersion: String = "1.0.0"
    @Published private(set) var runtimeEffects: [EffectsStudioRuntimeEffectChoice] = []
    @Published var selectedRuntimeType: String = ""

    @Published var sourceCode: String = EffectsStudioViewModel.defaultCodeBody
    @Published var compileLog: String = "Compile to render preview." {
        didSet { appendLogEntry(from: compileLog) }
    }
    @Published private(set) var logEntries: [String] = []

    @Published var parameters: [EffectsStudioParameterDraft] = EffectsStudioViewModel.defaultParameters
    @Published private(set) var parameterValues: [String: AnyCodableValue] = [:]
    @Published var pendingCodeInsertion: String?

    @Published var previewImage: NSImage?
    @Published var inputSourceLabel: String = "Generated Sample"
    @Published private(set) var timelineDuration: Double = 12

    @Published var time: Double = 0 {
        didSet { renderPreview() }
    }

    @Published var isPlaying: Bool = false {
        didSet { updatePlaybackLoop() }
    }

    private let previewSize = CGSize(width: 960, height: 540)
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let ciContext: CIContext

    private var pipelineState: MTLComputePipelineState?
    private var parameterBufferLayout: EffectsStudioParamBufferLayout?
    private var hasAppliedInitialRuntimeSelection = false

    private var sourceStillImage: CIImage?
    private var sourceVideoAsset: AVAsset?
    private var videoFrameGenerator: AVAssetImageGenerator?
    private var videoFrameGeneratorAssetID: ObjectIdentifier?
    private var lastVideoFrameImage: CIImage?
    private var playbackTask: Task<Void, Never>?
    private var lastPlaybackTickUptimeNs: UInt64?
    private var frameCounter: UInt32 = 0

    private var effectFunctionName: String {
        RuntimeMetalEffectLibrary.defaultFunctionName
    }

    init(settingsStore: EffectsStudioSettingsStore) {
        self.settingsStore = settingsStore
        self.device = SharedRenderer.metalDevice
        self.commandQueue = device?.makeCommandQueue()

        if let device {
            self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            self.ciContext = CIContext(options: [.cacheIntermediates: false])
        }

        rebuildParameterValues(preserveExisting: false)
        updateTimelineDurationFromCurrentSource()
        refreshRuntimeEffectList()
        appendLogEntry(from: compileLog)

        if device == nil {
            compileLog = "Metal device unavailable on this machine."
        } else {
            _ = compileCode()
        }
    }

    deinit {
        playbackTask?.cancel()
    }

    var runtimeEffectsDirectoryPath: String {
        runtimeEffectsDirectoryURL.path
    }

    var manifestPreviewJSON: String {
        guard let json = encodeRuntimeManifestJSON(runtimeManifestFromCurrentState()) else {
            return "{}"
        }
        return json
    }

    var editableParameterNames: [String] {
        parameters
            .filter { !$0.isAutoBound && !Self.isSystemParameterName($0.name) }
            .map(\.name)
            .filter { !$0.isEmpty }
    }

    var autoBoundParameterSummaries: [String] {
        parameters.compactMap { parameter in
            let name = parameter.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, parameter.isAutoBound, !Self.isSystemParameterName(name) else { return nil }
            return "\(name) <- \(parameter.autoBind.label)"
        }
    }

    var editableParameterDefinitions: [EffectsStudioParameterDraft] {
        parameters.filter { !Self.isSystemParameterName($0.name) }
    }

    func parameterSpec(named name: String) -> ParameterSpec? {
        guard let draft = parameters.first(where: { $0.name == name }) else { return nil }
        return Self.parameterSpec(for: draft)
    }

    func parameterValue(named name: String) -> AnyCodableValue? {
        parameterValues[name]
    }

    func updateControlParameter(name: String, value: AnyCodableValue) {
        if let draft = parameters.first(where: { $0.name == name }), draft.type == .choice {
            parameterValues[name] = canonicalChoiceValue(for: draft, rawValue: value)
        } else {
            parameterValues[name] = value
        }
        renderPreview()
    }

    func parameterDefinitionDidChange() {
        ensureSystemParameters()
        rebuildParameterValues(preserveExisting: true)
    }

    func addParameter() {
        let name = nextParameterName(base: "param")
        parameters.append(.default(named: name))
        parameterDefinitionDidChange()
    }

    func removeParameter(id: UUID) {
        parameters.removeAll { $0.id == id }
        parameterDefinitionDidChange()
    }

    func insertParameterUsage(name: String) {
        guard !name.isEmpty else { return }
        pendingCodeInsertion = "params.\(name)"
    }

    func resetToTemplate() {
        sourceCode = EffectsStudioViewModel.defaultCodeBody
        parameters = EffectsStudioViewModel.defaultParameters
        ensureSystemParameters()
        selectedRuntimeType = ""
        runtimeEffectUUID = UUID().uuidString.lowercased()
        runtimeEffectName = "New Effect"
        runtimeEffectVersion = "1.0.0"
        rebuildParameterValues(preserveExisting: false)
        compileLog = "Template restored."
    }

    func refreshRuntimeEffectList() {
        RuntimeMetalEffectLibrary.shared.reload()

        let effects = EffectRegistry.availableEffectTypes
            .filter { RuntimeMetalEffectLibrary.isRuntimeType($0.type) }
            .map { EffectsStudioRuntimeEffectChoice(type: $0.type, displayName: $0.displayName) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        runtimeEffects = effects

        if selectedRuntimeType.isEmpty {
            if !hasAppliedInitialRuntimeSelection, let first = effects.first {
                selectedRuntimeType = first.type
                hasAppliedInitialRuntimeSelection = true
            }
            return
        }

        let validTypes = Set(effects.map(\.type))
        if !validTypes.contains(selectedRuntimeType), let first = effects.first {
            selectedRuntimeType = first.type
        }
    }

    func loadRuntimeEffectAsset() {
        let uuid = Self.effectUUID(fromTypeName: selectedRuntimeType) ?? normalizedEffectUUID()
        guard !uuid.isEmpty else {
            compileLog = "Enter a valid effect UUID before loading."
            return
        }

        guard let directory = runtimeEffectDirectoryURL(forUUID: uuid) else {
            compileLog = "Runtime effect '\(uuid)' was not found."
            return
        }
        let manifestURL = directory.appendingPathComponent("effect.json")
        let shaderURL = directory.appendingPathComponent("shader.metal")

        do {
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(RuntimeMetalEffectManifest.self, from: manifestData)
            let shader = try String(contentsOf: shaderURL, encoding: .utf8)

            runtimeEffectUUID = manifest.uuid
            runtimeEffectName = manifest.name
            runtimeEffectVersion = manifest.version
            selectedRuntimeType = RuntimeMetalEffectLibrary.typeName(forUUID: manifest.uuid)
            sourceCode = shader
            parameters = Self.parameterDrafts(from: manifest)
            ensureSystemParameters()
            rebuildParameterValues(preserveExisting: false)
            _ = compileCode()
            refreshRuntimeEffectList()
            compileLog = "Loaded runtime effect '\(manifest.name)' (\(manifest.uuid))."
        } catch {
            compileLog = "Failed to load runtime effect '\(uuid)': \(error.localizedDescription)"
        }
    }

    func saveRuntimeEffectAsset() {
        let uuid = normalizedEffectUUID()
        guard UUID(uuidString: uuid) != nil else {
            compileLog = "Enter a valid effect UUID before saving."
            return
        }
        runtimeEffectUUID = uuid

        let fm = FileManager.default
        let directory = runtimeEffectsDirectoryURL.appendingPathComponent(uuid, isDirectory: true)
        let manifestURL = directory.appendingPathComponent("effect.json")
        let shaderURL = directory.appendingPathComponent("shader.metal")

        do {
            if !fm.fileExists(atPath: directory.path) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let manifest = runtimeManifestFromCurrentState()
            guard let json = encodeRuntimeManifestJSON(manifest) else {
                compileLog = "Failed to encode effect manifest."
                return
            }

            try json.write(to: manifestURL, atomically: true, encoding: .utf8)
            try sourceCode.write(to: shaderURL, atomically: true, encoding: .utf8)
            refreshRuntimeEffectList()
            selectedRuntimeType = RuntimeMetalEffectLibrary.typeName(forUUID: uuid)
            compileLog = "Saved runtime effect '\(runtimeEffectName)' (\(uuid)) to \(directory.path)"
        } catch {
            compileLog = "Failed to save runtime effect '\(uuid)': \(error.localizedDescription)"
        }
    }

    func deleteRuntimeEffectAsset() {
        let uuid = Self.effectUUID(fromTypeName: selectedRuntimeType) ?? normalizedEffectUUID()
        guard UUID(uuidString: uuid) != nil else {
            compileLog = "Select a valid runtime effect before deleting."
            return
        }

        guard let directory = runtimeEffectDirectoryURL(forUUID: uuid) else {
            compileLog = "Runtime effect '\(uuid)' was not found."
            return
        }

        do {
            try FileManager.default.removeItem(at: directory)
            refreshRuntimeEffectList()

            if runtimeEffects.isEmpty {
                selectedRuntimeType = ""
                resetToTemplate()
                compileLog = "Deleted runtime effect '\(uuid)'. No runtime effects remain."
            } else {
                compileLog = "Deleted runtime effect '\(uuid)'."
            }
        } catch {
            compileLog = "Failed to delete runtime effect '\(uuid)': \(error.localizedDescription)"
        }
    }

    func chooseCodeSourceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        var contentTypes: [UTType] = [.plainText, .sourceCode]
        if let metalType = UTType(filenameExtension: "metal") {
            contentTypes.append(metalType)
        }
        panel.allowedContentTypes = contentTypes

        panel.title = "Open Metal Source"
        panel.message = "Select a .metal or text source file."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            sourceCode = try String(contentsOf: url, encoding: .utf8)
            compileLog = "Loaded shader source: \(url.lastPathComponent)"
        } catch {
            compileLog = "Failed to load shader source: \(error.localizedDescription)"
        }
    }

    func chooseFileSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .movie]
        panel.title = "Choose Effect Studio Source"
        panel.message = "Select a single image or video as preview source."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFileSource(url: url, persist: true)
    }

    func useGeneratedSample() {
        sourceStillImage = nil
        sourceVideoAsset = nil
        invalidateVideoFrameCache()
        inputSourceLabel = "Generated Sample"
        persistLastSourceSample()
        updateTimelineDurationFromCurrentSource()
        renderPreview()
    }

    func loadRandomSource(from library: MediaLibrary, preferredLength: Double = 8.0) {
        guard let clip = library.randomClip(clipLength: preferredLength) else {
            compileLog = "No source available in active libraries for random pick. Using generated sample."
            useGeneratedSample()
            return
        }
        loadMediaClip(clip)
    }

    func restoreInitialSource(from library: MediaLibrary, preferredLength: Double = 8.0) {
        let persisted = settingsStore.value
        guard let kind = persisted.lastSourceKind else {
            loadRandomSource(from: library, preferredLength: preferredLength)
            return
        }

        switch kind {
        case .file:
            guard let path = persisted.lastSourceValue, !path.isEmpty else {
                loadRandomSource(from: library, preferredLength: preferredLength)
                return
            }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                loadRandomSource(from: library, preferredLength: preferredLength)
                return
            }
            loadFileSource(url: url, persist: false)

        case .photos:
            guard let identifier = persisted.lastSourceValue, !identifier.isEmpty else {
                loadRandomSource(from: library, preferredLength: preferredLength)
                return
            }
            loadPhotosSource(identifier: identifier)

        case .sample:
            useGeneratedSample()
        }
    }

    func loadMediaClip(_ clip: MediaClip) {
        Task {
            if clip.file.mediaKind == .image {
                let image = await clip.file.loadImage()
                await MainActor.run {
                    sourceStillImage = image
                    sourceVideoAsset = nil
                    self.invalidateVideoFrameCache()
                    inputSourceLabel = "Random \(clip.file.displayName)"
                    compileLog = image == nil ? "Failed to load random image source." : compileLog
                    if image != nil {
                        persistSource(file: clip.file)
                    }
                    isPlaying = false
                    updateTimelineDurationFromCurrentSource()
                    renderPreview()
                }
                return
            }

            let asset = await clip.file.loadAsset()
            await MainActor.run {
                sourceStillImage = nil
                sourceVideoAsset = asset
                self.invalidateVideoFrameCache()
                inputSourceLabel = "Random \(clip.file.displayName)"
                compileLog = asset == nil ? "Failed to load random video source." : compileLog
                if asset != nil {
                    persistSource(file: clip.file)
                }
                isPlaying = asset != nil
                updateTimelineDurationFromCurrentSource()
                renderPreview()
            }
        }
    }

    func loadPhotosSource(identifier: String) {
        Task {
            let auth: ApplePhotos.AuthorizationStatus
            if ApplePhotos.shared.status.canRead {
                auth = ApplePhotos.shared.status
            } else {
                auth = await ApplePhotos.shared.requestAuthorization()
            }

            guard auth.canRead else {
                await MainActor.run {
                    compileLog = "Apple Photos access denied. Enable Photos access in System Settings."
                }
                return
            }

            guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else {
                await MainActor.run {
                    compileLog = "Could not load selected Photos asset."
                }
                return
            }

            if asset.mediaType == .image {
                let image = await ApplePhotos.shared.requestCIImage(for: asset)
                await MainActor.run {
                    sourceStillImage = image
                    sourceVideoAsset = nil
                    self.invalidateVideoFrameCache()
                    inputSourceLabel = "Apple Photos Image"
                    compileLog = image == nil ? "Failed to load Apple Photos image." : compileLog
                    if image != nil {
                        persistLastPhotosSource(identifier: identifier)
                    }
                    isPlaying = false
                    updateTimelineDurationFromCurrentSource()
                    renderPreview()
                }
                return
            }

            if asset.mediaType == .video {
                let avAsset = await ApplePhotos.shared.requestAVAsset(for: asset)
                await MainActor.run {
                    sourceStillImage = nil
                    if let avAsset {
                        sourceVideoAsset = avAsset
                        self.invalidateVideoFrameCache()
                        inputSourceLabel = "Apple Photos Video"
                        persistLastPhotosSource(identifier: identifier)
                        isPlaying = true
                        updateTimelineDurationFromCurrentSource()
                        renderPreview()
                    } else {
                        sourceVideoAsset = nil
                        isPlaying = false
                        compileLog = "Failed to load selected Apple Photos video asset."
                    }
                }
                return
            }

            await MainActor.run {
                compileLog = "Unsupported Photos asset type."
            }
        }
    }

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
                compileLog = signatureError
                return false
            }

            guard let layout = buildParameterBufferLayout(arguments: args) else {
                compileLog = "Compile succeeded, but could not infer buffer(0) parameter layout."
                return false
            }

            pipelineState = pipeline
            parameterBufferLayout = layout
            compileLog = "Compiled successfully. Kernel '\(effectFunctionName)' is ready."
            renderPreview()
            return true
        } catch {
            compileLog = "Compile failed:\n\(error.localizedDescription)"
            return false
        }
    }

    func renderPreview() {
        guard let pipelineState,
              let parameterBufferLayout,
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
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)

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
            encoder.setBytes(base, length: paramsBytes.count, index: 0)
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
        frameCounter &+= 1
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

    private func generatedParamStructSource() -> String {
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

    private var sourceContainsHypnoParamsStruct: Bool {
        if let regex = try? NSRegularExpression(pattern: #"\bstruct\s+HypnoParams\b"#) {
            let range = NSRange(sourceCode.startIndex..<sourceCode.endIndex, in: sourceCode)
            return regex.firstMatch(in: sourceCode, options: [], range: range) != nil
        }
        return sourceCode.contains("struct HypnoParams")
    }

    private func validateSignature(arguments: [MTLArgument]) -> String? {
        let textures = arguments.filter { $0.type == .texture }
        let buffers = arguments.filter { $0.type == .buffer }

        guard textures.contains(where: { Int($0.index) == 0 }) else {
            return "Metal code must declare input texture at texture(0)."
        }

        guard let outputArg = textures.first(where: { Int($0.index) == 1 }) else {
            return "Metal code must declare output texture at texture(1)."
        }

        if outputArg.access == .readOnly {
            return "texture(1) must be write or read_write."
        }

        guard buffers.contains(where: { Int($0.index) == 0 }) else {
            return "Metal code must declare constant HypnoParams& params at buffer(0)."
        }

        return nil
    }

    private func buildParameterBufferLayout(arguments: [MTLArgument]) -> EffectsStudioParamBufferLayout? {
        guard let bufferArg = arguments.first(where: { $0.type == .buffer && Int($0.index) == 0 }),
              let structType = bufferArg.bufferStructType else {
            return nil
        }

        let members: [EffectsStudioParamBufferMemberLayout] = structType.members
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

        return EffectsStudioParamBufferLayout(
            length: max(Int(bufferArg.bufferDataSize), 1),
            members: members
        )
    }

    private func fillParameterBuffer(
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

    private func makeTexture(from image: CIImage, width: Int, height: Int, device: MTLDevice) -> MTLTexture? {
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

    private func normalizedEffectUUID() -> String {
        runtimeEffectUUID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizedEffectName() -> String {
        let name = runtimeEffectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled Effect" : name
    }

    private func normalizedEffectVersion() -> String {
        let version = runtimeEffectVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? "1.0.0" : version
    }

    private func runtimeEffectDirectoryURL(forUUID uuid: String) -> URL? {
        let direct = runtimeEffectsDirectoryURL.appendingPathComponent(uuid, isDirectory: true)
        return FileManager.default.fileExists(atPath: direct.path) ? direct : nil
    }

    private func appendLogEntry(from message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if logEntries.last == trimmed { return }
        logEntries.append(trimmed)
    }

    private func nextParameterName(base: String) -> String {
        let existing = Set(parameters.map { $0.name })
        if !existing.contains(base) {
            return base
        }
        var index = 1
        while existing.contains("\(base)\(index)") {
            index += 1
        }
        return "\(base)\(index)"
    }

    private func canonicalChoiceValue(
        for draft: EffectsStudioParameterDraft,
        rawValue: AnyCodableValue
    ) -> AnyCodableValue {
        let options = Self.sanitizedChoiceOptions(for: draft)
        guard !options.isEmpty else { return rawValue }

        if let stringValue = rawValue.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let option = options.first(where: { $0.key == stringValue }) {
                return .string(option.key)
            }
            if let option = options.first(where: { $0.key.caseInsensitiveCompare(stringValue) == .orderedSame }) {
                return .string(option.key)
            }
            if let option = options.first(where: { $0.label == stringValue }) {
                return .string(option.key)
            }
            if let option = options.first(where: { $0.label.caseInsensitiveCompare(stringValue) == .orderedSame }) {
                return .string(option.key)
            }
            if let parsedIndex = Int(stringValue), options.indices.contains(parsedIndex) {
                return .string(options[parsedIndex].key)
            }
            return .string(stringValue)
        }

        if let intValue = rawValue.intValue, options.indices.contains(intValue) {
            return .string(options[intValue].key)
        }

        if let doubleValue = rawValue.doubleValue {
            let index = Int(doubleValue.rounded())
            if options.indices.contains(index) {
                return .string(options[index].key)
            }
        }

        return rawValue
    }

    private func runtimeManifestFromCurrentState() -> RuntimeMetalEffectManifest {
        var parameterEntries: [String: RuntimeMetalParameterSchemaEntry] = [:]
        var order: [String] = []
        var autoBound: [String] = []

        for param in parameters {
            let name = param.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard let entry = runtimeParameterEntry(from: param) else { continue }
            parameterEntries[name] = entry
            order.append(name)
            if param.isAutoBound {
                autoBound.append(name)
            }
        }

        return RuntimeMetalEffectManifest(
            uuid: normalizedEffectUUID(),
            name: normalizedEffectName(),
            version: normalizedEffectVersion(),
            runtimeKind: .metal,
            requiredLookback: 0,
            usesPersistentState: false,
            parameters: parameterEntries,
            parameterOrder: order,
            autoBoundParameters: autoBound,
            bindings: RuntimeMetalBindingsManifest(
                parameterBufferIndex: 0,
                inputTextures: [
                    RuntimeMetalTextureBindingManifest(argumentIndex: 0, source: .currentFrame, historyOffset: nil)
                ],
                outputTextureIndex: 1
            )
        )
    }

    private static func sanitizedChoiceOptions(for param: EffectsStudioParameterDraft) -> [EffectsStudioChoiceOption] {
        var seenKeys = Set<String>()
        var sanitized: [EffectsStudioChoiceOption] = []

        for option in param.choiceOptions {
            let key = option.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)

            let label = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitized.append(
                EffectsStudioChoiceOption(
                    id: option.id,
                    key: key,
                    label: label.isEmpty ? key : label
                )
            )
        }

        return sanitized
    }

    private static func resolvedChoiceDefaultKey(
        for param: EffectsStudioParameterDraft,
        options: [EffectsStudioChoiceOption]? = nil
    ) -> String {
        let resolvedOptions = options ?? sanitizedChoiceOptions(for: param)
        let explicit = param.defaultChoiceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedOptions.contains(where: { $0.key == explicit }) {
            return explicit
        }
        return resolvedOptions.first?.key ?? ""
    }

    private func runtimeParameterEntry(from param: EffectsStudioParameterDraft) -> RuntimeMetalParameterSchemaEntry? {
        switch param.type {
        case .float:
            return RuntimeMetalParameterSchemaEntry(
                type: "float",
                defaultValue: .double(param.defaultNumber),
                min: param.minNumber,
                max: max(param.maxNumber, param.minNumber + 0.0001),
                options: nil
            )

        case .int:
            return RuntimeMetalParameterSchemaEntry(
                type: "int",
                defaultValue: .int(Int(param.defaultNumber.rounded())),
                min: param.minNumber,
                max: max(param.maxNumber, param.minNumber + 1),
                options: nil
            )

        case .uint:
            return RuntimeMetalParameterSchemaEntry(
                type: "uint",
                defaultValue: .int(max(0, Int(param.defaultNumber.rounded()))),
                min: max(0, param.minNumber),
                max: max(max(0, param.maxNumber), max(0, param.minNumber) + 1),
                options: nil
            )

        case .bool:
            return RuntimeMetalParameterSchemaEntry(
                type: "bool",
                defaultValue: .bool(param.defaultBool),
                min: nil,
                max: nil,
                options: nil
            )

        case .choice:
            let options = Self.sanitizedChoiceOptions(for: param)
            let defaultKey = Self.resolvedChoiceDefaultKey(for: param, options: options)
            return RuntimeMetalParameterSchemaEntry(
                type: "choice",
                defaultValue: .string(defaultKey),
                min: nil,
                max: nil,
                options: options.map { RuntimeMetalChoiceOption(key: $0.key, label: $0.label) }
            )
        }
    }

    private func encodeRuntimeManifestJSON(_ manifest: RuntimeMetalEffectManifest) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func rebuildParameterValues(preserveExisting: Bool) {
        let existing = parameterValues
        var rebuilt: [String: AnyCodableValue] = [:]

        for param in parameters {
            let name = param.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if preserveExisting, let old = existing[name] {
                rebuilt[name] = old
            } else {
                rebuilt[name] = Self.defaultValue(for: param)
            }
        }

        parameterValues = rebuilt
    }

    private static func defaultValue(for param: EffectsStudioParameterDraft) -> AnyCodableValue {
        switch param.type {
        case .float:
            return .double(param.defaultNumber)
        case .int:
            return .int(Int(param.defaultNumber.rounded()))
        case .uint:
            return .int(max(0, Int(param.defaultNumber.rounded())))
        case .bool:
            return .bool(param.defaultBool)
        case .choice:
            return .string(resolvedChoiceDefaultKey(for: param))
        }
    }

    private static func parameterSpec(for param: EffectsStudioParameterDraft) -> ParameterSpec {
        switch param.type {
        case .float:
            let minV = Float(param.minNumber)
            let maxV = Float(max(param.maxNumber, param.minNumber + 0.0001))
            let def = Float(param.defaultNumber)
            return .float(default: def, range: minV...maxV)

        case .int:
            let minV = Int(param.minNumber.rounded())
            let maxV = Int(max(param.maxNumber, param.minNumber + 1).rounded())
            let def = Int(param.defaultNumber.rounded())
            return .int(default: def, range: minV...maxV)

        case .uint:
            let minV = max(0, Int(param.minNumber.rounded()))
            let maxV = max(minV + 1, Int(max(param.maxNumber, param.minNumber + 1).rounded()))
            let def = max(0, Int(param.defaultNumber.rounded()))
            return .int(default: def, range: minV...maxV)

        case .bool:
            return .bool(default: param.defaultBool)

        case .choice:
            let options = sanitizedChoiceOptions(for: param)
            let normalized = options.map { (key: $0.key, label: $0.label) }
            let defaultKey = resolvedChoiceDefaultKey(for: param, options: options)
            return .choice(default: defaultKey, options: normalized)
        }
    }

    private static func parameterDrafts(from manifest: RuntimeMetalEffectManifest) -> [EffectsStudioParameterDraft] {
        let autoBoundSet = Set(manifest.autoBoundParameters ?? [])
        let order = manifest.parameterOrder ?? manifest.parameters.keys.sorted()

        var result: [EffectsStudioParameterDraft] = []
        for name in order {
            guard let entry = manifest.parameters[name] else { continue }
            guard let type = paramType(from: entry.type) else { continue }

            let autoBind: EffectsStudioAutoBind = autoBoundSet.contains(name) ? EffectsStudioAutoBind.infer(from: name) : .none
            switch type {
            case .bool:
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .bool,
                        defaultNumber: 0,
                        minNumber: 0,
                        maxNumber: 1,
                        defaultBool: entry.defaultValue.boolValue ?? false,
                        autoBind: autoBind
                    )
                )

            case .float:
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .float,
                        defaultNumber: entry.defaultValue.doubleValue ?? 0,
                        minNumber: entry.min ?? 0,
                        maxNumber: entry.max ?? 1,
                        defaultBool: false,
                        autoBind: autoBind
                    )
                )

            case .int:
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .int,
                        defaultNumber: Double(entry.defaultValue.intValue ?? 0),
                        minNumber: entry.min ?? 0,
                        maxNumber: entry.max ?? 1,
                        defaultBool: false,
                        autoBind: autoBind
                    )
                )

            case .uint:
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .uint,
                        defaultNumber: Double(max(0, entry.defaultValue.intValue ?? 0)),
                        minNumber: max(0, entry.min ?? 0),
                        maxNumber: max(1, entry.max ?? 1),
                        defaultBool: false,
                        autoBind: autoBind
                    )
                )

            case .choice:
                let options = (entry.options ?? []).map {
                    EffectsStudioChoiceOption(key: $0.key, label: $0.label)
                }
                let defaultKey = entry.defaultValue.stringValue
                    ?? options.first?.key
                    ?? ""
                result.append(
                    EffectsStudioParameterDraft(
                        name: name,
                        type: .choice,
                        defaultNumber: 0,
                        minNumber: 0,
                        maxNumber: 1,
                        defaultBool: false,
                        defaultChoiceKey: defaultKey,
                        choiceOptions: options,
                        autoBind: autoBind
                    )
                )
            }
        }

        return result
    }

    private static func paramType(from raw: String) -> EffectsStudioParamType? {
        switch raw.lowercased() {
        case "float", "double":
            return .float
        case "int":
            return .int
        case "uint":
            return .uint
        case "bool":
            return .bool
        case "choice":
            return .choice
        default:
            return nil
        }
    }

    private static func scalarType(for dataType: MTLDataType) -> EffectsStudioScalarValueType? {
        switch dataType {
        case .float:
            return .float
        case .int:
            return .int
        case .uint:
            return .uint
        case .bool:
            return .bool
        default:
            return nil
        }
    }

    private static func scalarSize(for type: EffectsStudioScalarValueType) -> Int? {
        switch type {
        case .float, .int, .uint:
            return 4
        case .bool:
            return 1
        }
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        let pattern = "^[A-Za-z_][A-Za-z0-9_]*$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private var runtimeEffectsDirectoryURL: URL {
        HypnoCoreConfig.shared.runtimeEffectsDirectory
    }

    private func loadFileSource(url: URL, persist: Bool) {
        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]
        let videoExts: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]

        if imageExts.contains(ext), let image = CIImage(contentsOf: url) {
            sourceStillImage = image
            sourceVideoAsset = nil
            invalidateVideoFrameCache()
            inputSourceLabel = "File Image: \(url.lastPathComponent)"
            if persist {
                persistLastFileSource(url: url)
            }
            isPlaying = false
            updateTimelineDurationFromCurrentSource()
            renderPreview()
            return
        }

        if videoExts.contains(ext) {
            sourceStillImage = nil
            sourceVideoAsset = AVURLAsset(url: url)
            invalidateVideoFrameCache()
            inputSourceLabel = "File Video: \(url.lastPathComponent)"
            if persist {
                persistLastFileSource(url: url)
            }
            updateTimelineDurationFromCurrentSource()
            isPlaying = true
            renderPreview()
            return
        }

        compileLog = "Unsupported file type. Pick an image or video."
    }

    private func persistSource(file: MediaFile) {
        switch file.source {
        case .url(let url):
            persistLastFileSource(url: url)
        case .external(let identifier):
            persistLastPhotosSource(identifier: identifier)
        }
    }

    private func persistLastFileSource(url: URL) {
        settingsStore.update { value in
            value.lastSourceKind = .file
            value.lastSourceValue = url.path
        }
    }

    private func persistLastPhotosSource(identifier: String) {
        settingsStore.update { value in
            value.lastSourceKind = .photos
            value.lastSourceValue = identifier
        }
    }

    private func persistLastSourceSample() {
        settingsStore.update { value in
            value.lastSourceKind = .sample
            value.lastSourceValue = nil
        }
    }

    private func currentSourceImage(time: Double) -> CIImage {
        if let image = sourceStillImage {
            return aspectFill(image: image, to: previewSize)
        }

        if let asset = sourceVideoAsset, let frame = videoFrame(from: asset, at: time) {
            return aspectFill(image: frame, to: previewSize)
        }

        return makeGeneratedPreviewImage(size: previewSize, time: Float(time))
    }

    private func videoFrame(from asset: AVAsset, at time: Double) -> CIImage? {
        let duration = asset.duration.seconds
        let sampleTimeSeconds: Double

        if duration.isFinite, duration > 0 {
            sampleTimeSeconds = time.truncatingRemainder(dividingBy: duration)
        } else {
            sampleTimeSeconds = 0
        }

        let sampleTime = CMTime(seconds: max(0, sampleTimeSeconds), preferredTimescale: 600)
        let assetID = ObjectIdentifier(asset)

        if videoFrameGenerator == nil || videoFrameGeneratorAssetID != assetID {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0 / 120.0, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0 / 120.0, preferredTimescale: 600)
            videoFrameGenerator = generator
            videoFrameGeneratorAssetID = assetID
            lastVideoFrameImage = nil
        }

        guard let generator = videoFrameGenerator else {
            return lastVideoFrameImage
        }
        guard let cgImage = try? generator.copyCGImage(at: sampleTime, actualTime: nil) else {
            return lastVideoFrameImage
        }

        let image = CIImage(cgImage: cgImage)
        lastVideoFrameImage = image
        return image
    }

    private func invalidateVideoFrameCache() {
        videoFrameGenerator = nil
        videoFrameGeneratorAssetID = nil
        lastVideoFrameImage = nil
    }

    private func aspectFill(image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return makeGeneratedPreviewImage(size: size, time: 0)
        }

        let normalized = image.transformed(by: .init(translationX: -extent.origin.x, y: -extent.origin.y))
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaled = normalized.transformed(by: .init(scaleX: scale, y: scale))
        let x = (size.width - scaled.extent.width) * 0.5
        let y = (size.height - scaled.extent.height) * 0.5

        return scaled
            .transformed(by: .init(translationX: x, y: y))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func makeGeneratedPreviewImage(size: CGSize, time: Float) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        var image = CIImage(color: CIColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1)).cropped(to: rect)

        if let checker = CIFilter(name: "CICheckerboardGenerator") {
            checker.setValue(CIVector(x: size.width * 0.5 + CGFloat(sin(Double(time)) * 120.0), y: size.height * 0.5), forKey: "inputCenter")
            checker.setValue(CIColor(red: 0.12, green: 0.16, blue: 0.26, alpha: 1), forKey: "inputColor0")
            checker.setValue(CIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1), forKey: "inputColor1")
            checker.setValue(34.0, forKey: "inputWidth")
            checker.setValue(0.95, forKey: "inputSharpness")

            if let board = checker.outputImage?.cropped(to: rect),
               let overlay = CIFilter(name: "CISoftLightBlendMode") {
                overlay.setValue(board, forKey: kCIInputImageKey)
                overlay.setValue(image, forKey: kCIInputBackgroundImageKey)
                image = overlay.outputImage?.cropped(to: rect) ?? image
            }
        }

        if let radial = CIFilter(name: "CIRadialGradient") {
            radial.setValue(CIVector(x: size.width * 0.5, y: size.height * 0.5), forKey: "inputCenter")
            radial.setValue(size.height * 0.10, forKey: "inputRadius0")
            radial.setValue(size.height * 0.48, forKey: "inputRadius1")
            radial.setValue(CIColor(red: 1.0, green: 0.35, blue: 0.1, alpha: 0.32), forKey: "inputColor0")
            radial.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")

            if let glow = radial.outputImage?.cropped(to: rect),
               let comp = CIFilter(name: "CISourceOverCompositing") {
                comp.setValue(glow, forKey: kCIInputImageKey)
                comp.setValue(image, forKey: kCIInputBackgroundImageKey)
                image = comp.outputImage?.cropped(to: rect) ?? image
            }
        }

        return image
    }

    private func updatePlaybackLoop() {
        if !isPlaying {
            playbackTask?.cancel()
            playbackTask = nil
            lastPlaybackTickUptimeNs = nil
            return
        }

        if playbackTask != nil {
            return
        }

        lastPlaybackTickUptimeNs = DispatchTime.now().uptimeNanoseconds
        playbackTask = Task { [weak self] in
            let tickDurationNs: UInt64 = 16_666_667
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickDurationNs)
                await MainActor.run {
                    guard let self else { return }
                    guard self.isPlaying else { return }

                    let now = DispatchTime.now().uptimeNanoseconds
                    let last = self.lastPlaybackTickUptimeNs ?? now
                    self.lastPlaybackTickUptimeNs = now

                    let elapsed = Double(now &- last) / 1_000_000_000.0
                    guard elapsed.isFinite, elapsed > 0 else { return }

                    let duration = max(self.timelineDuration, 0.001)
                    var nextTime = self.time + elapsed
                    if nextTime >= duration {
                        nextTime = nextTime.truncatingRemainder(dividingBy: duration)
                    }
                    if !nextTime.isFinite || nextTime < 0 {
                        nextTime = 0
                    }
                    self.time = nextTime
                }
            }
        }
    }

    private func updateTimelineDurationFromCurrentSource() {
        if let asset = sourceVideoAsset {
            let duration = asset.duration.seconds
            if duration.isFinite, duration > 0 {
                timelineDuration = duration
            } else {
                timelineDuration = 12
            }
        } else {
            timelineDuration = 12
        }

        let maxTime = max(timelineDuration, 0.001)
        if time >= maxTime {
            time = time.truncatingRemainder(dividingBy: maxTime)
        }
        if !time.isFinite || time < 0 {
            time = 0
        }
    }

    private static func effectUUID(fromTypeName typeName: String) -> String? {
        RuntimeMetalEffectLibrary.uuid(fromTypeName: typeName)
    }

    private static func isSystemParameterName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return systemParameterBlueprints.contains { $0.name == trimmed }
    }

    private func ensureSystemParameters() {
        for blueprint in Self.systemParameterBlueprints {
            let name = blueprint.name
            if let index = parameters.firstIndex(where: { $0.name == name }) {
                var existing = parameters[index]
                var changed = false

                if existing.name != blueprint.name {
                    existing.name = blueprint.name
                    changed = true
                }
                if existing.type != blueprint.type {
                    existing.type = blueprint.type
                    changed = true
                }
                if existing.autoBind != blueprint.autoBind {
                    existing.autoBind = blueprint.autoBind
                    changed = true
                }
                if existing.defaultNumber != blueprint.defaultNumber {
                    existing.defaultNumber = blueprint.defaultNumber
                    changed = true
                }
                if existing.minNumber != blueprint.minNumber {
                    existing.minNumber = blueprint.minNumber
                    changed = true
                }
                if existing.maxNumber != blueprint.maxNumber {
                    existing.maxNumber = blueprint.maxNumber
                    changed = true
                }
                if existing.defaultBool != blueprint.defaultBool {
                    existing.defaultBool = blueprint.defaultBool
                    changed = true
                }

                if changed {
                    parameters[index] = existing
                }
            } else {
                parameters.append(blueprint)
            }
        }
    }

    private static let defaultParameters: [EffectsStudioParameterDraft] = [
        EffectsStudioParameterDraft(
            name: "offsetAmount",
            type: .float,
            defaultNumber: 10,
            minNumber: 0,
            maxNumber: 500,
            defaultBool: false,
            autoBind: .none
        ),
        EffectsStudioParameterDraft(
            name: "animated",
            type: .bool,
            defaultNumber: 0,
            minNumber: 0,
            maxNumber: 1,
            defaultBool: true,
            autoBind: .none
        ),
    ] + systemParameterBlueprints

    private static let systemParameterBlueprints: [EffectsStudioParameterDraft] = [
        EffectsStudioParameterDraft(
            name: "timeSeconds",
            type: .float,
            defaultNumber: 0,
            minNumber: 0,
            maxNumber: 100000,
            defaultBool: false,
            autoBind: .timeSeconds
        ),
        EffectsStudioParameterDraft(
            name: "textureWidth",
            type: .int,
            defaultNumber: 1920,
            minNumber: 1,
            maxNumber: 8192,
            defaultBool: false,
            autoBind: .textureWidth
        ),
        EffectsStudioParameterDraft(
            name: "textureHeight",
            type: .int,
            defaultNumber: 1080,
            minNumber: 1,
            maxNumber: 8192,
            defaultBool: false,
            autoBind: .textureHeight
        )
    ]

    private static let defaultCodeBody: String = """
    #include <metal_stdlib>
    using namespace metal;

    inline float animatedPhase(float t) {
        float slow = sin(t * 0.7);
        float medium = sin(t * 2.3 + 1.5) * 0.4;
        float fast = sin(t * 7.1 + 3.0) * 0.15;
        float erratic = sin(t * 13.7 + t * 0.3) * 0.1;
        float combined = slow + medium + fast + erratic;
        return (combined + 1.0) * 0.45 + 0.1;
    }

    kernel void render(
        texture2d<float, access::sample> inputTexture [[texture(0)]],
        texture2d<float, access::write> outputTexture [[texture(1)]],
        constant HypnoParams& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= uint(params.textureWidth) || gid.y >= uint(params.textureHeight)) {
            return;
        }

        constexpr sampler samplerLinear(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

        float2 texSize = float2(params.textureWidth, params.textureHeight);
        float2 uv = (float2(gid) + 0.5) / texSize;

        float offsetPixels = params.offsetAmount;
        if (params.animated != 0) {
            offsetPixels *= animatedPhase(params.timeSeconds);
        }
        float offsetUV = offsetPixels / max(texSize.x, 1.0);

        float4 center = inputTexture.sample(samplerLinear, uv);
        float4 redShifted = inputTexture.sample(samplerLinear, uv + float2(offsetUV, 0.0));
        float4 blueShifted = inputTexture.sample(samplerLinear, uv - float2(offsetUV, 0.0));

        float3 rgb = float3(redShifted.r, center.g, blueShifted.b);
        outputTexture.write(float4(clamp(rgb, 0.0, 1.0), center.a), gid);
    }
    """
}
