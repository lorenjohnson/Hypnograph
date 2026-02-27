//
//  EffectsStudioView.swift
//  Hypnograph
//
//  Runtime effect authoring studio (v1).
//  Authoring format: effect.json + shader.metal
//

import SwiftUI
import AppKit
import CoreImage
import AVFoundation
import UniformTypeIdentifiers
import Metal
import Foundation
import HypnoCore

extension Notification.Name {
    static let effectsStudioToggleCleanScreen = Notification.Name("Hypnograph.EffectsStudio.ToggleCleanScreen")
}

enum EffectsStudioParamType: String, CaseIterable, Identifiable {
    case float
    case int
    case uint
    case bool
    case choice

    var id: String { rawValue }

    var metalType: String {
        switch self {
        case .float: return "float"
        case .int: return "int"
        case .uint: return "uint"
        case .bool: return "bool"
        case .choice: return "int"
        }
    }

    var usesNumericRange: Bool {
        switch self {
        case .float, .int, .uint:
            return true
        case .bool, .choice:
            return false
        }
    }
}

enum EffectsStudioAutoBind: String, CaseIterable, Identifiable {
    case none
    case timeSeconds
    case textureWidth
    case textureHeight
    case frameIndex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .timeSeconds: return "Time"
        case .textureWidth: return "Texture Width"
        case .textureHeight: return "Texture Height"
        case .frameIndex: return "Frame Index"
        }
    }

    static func infer(from parameterName: String) -> EffectsStudioAutoBind {
        switch parameterName {
        case "timeSeconds", "time":
            return .timeSeconds
        case "textureWidth", "width":
            return .textureWidth
        case "textureHeight", "height":
            return .textureHeight
        case "frameIndex", "frame", "frame_index":
            return .frameIndex
        default:
            return .none
        }
    }
}

struct EffectsStudioChoiceOption: Identifiable, Equatable {
    var id: UUID = UUID()
    var key: String
    var label: String
}

struct EffectsStudioParameterDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var type: EffectsStudioParamType
    var defaultNumber: Double
    var minNumber: Double
    var maxNumber: Double
    var defaultBool: Bool
    var defaultChoiceKey: String = ""
    var choiceOptions: [EffectsStudioChoiceOption] = []
    var autoBind: EffectsStudioAutoBind

    var isAutoBound: Bool { autoBind != .none }

    static func `default`(named name: String = "param") -> EffectsStudioParameterDraft {
        EffectsStudioParameterDraft(
            name: name,
            type: .float,
            defaultNumber: 0,
            minNumber: 0,
            maxNumber: 1,
            defaultBool: false,
            autoBind: .none
        )
    }
}

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

struct EffectsStudioRuntimeEffectChoice: Identifiable, Hashable {
    var type: String
    var displayName: String
    var id: String { type }
}

private struct MetalCodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: String?

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MetalCodeEditorView
        weak var textView: NSTextView?

        init(parent: MetalCodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.black.withAlphaComponent(0.20)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.string = text

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView ?? (nsView.documentView as? NSTextView) else { return }
        context.coordinator.textView = textView

        if textView.string != text {
            textView.string = text
        }

        if let insertion = insertionRequest {
            let selected = textView.selectedRange()
            if let storage = textView.textStorage {
                storage.replaceCharacters(in: selected, with: insertion)
                textView.setSelectedRange(NSRange(location: selected.location + (insertion as NSString).length, length: 0))
                textView.didChangeText()
            } else {
                textView.insertText(insertion, replacementRange: selected)
            }

            DispatchQueue.main.async {
                insertionRequest = nil
            }
        }
    }
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
        parameterValues[name] = value
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
           case .choice(_, let options) = spec,
           let index = options.firstIndex(where: { $0.key == stringValue }) {
            return index
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

private struct EffectsStudioParameterDefinitionRow: View {
    @Binding var parameter: EffectsStudioParameterDraft
    let onChanged: () -> Void
    let onInsert: (String) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("name", text: Binding(
                    get: { parameter.name },
                    set: { parameter.name = $0; onChanged() }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 130, maxWidth: .infinity)

                Picker("Type", selection: Binding(
                    get: { parameter.type },
                    set: {
                        parameter.type = $0
                        if parameter.type == .choice {
                            if parameter.choiceOptions.isEmpty {
                                parameter.choiceOptions = [
                                    EffectsStudioChoiceOption(key: "option1", label: "Option 1")
                                ]
                            }
                            if !parameter.choiceOptions.contains(where: { $0.key == parameter.defaultChoiceKey }) {
                                parameter.defaultChoiceKey = parameter.choiceOptions.first?.key ?? ""
                            }
                        }
                        onChanged()
                    }
                )) {
                    ForEach(EffectsStudioParamType.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            HStack(spacing: 8) {
                Picker("Binding", selection: Binding(
                    get: { parameter.autoBind },
                    set: {
                        parameter.autoBind = $0
                        onChanged()
                    }
                )) {
                    ForEach(EffectsStudioAutoBind.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)

                Spacer(minLength: 0)

                Button {
                    onInsert(parameter.name)
                } label: {
                    Label("Insert Usage", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
            }

            if parameter.type == .bool {
                Toggle("Default", isOn: Binding(
                    get: { parameter.defaultBool },
                    set: { parameter.defaultBool = $0; onChanged() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            } else if parameter.type == .choice {
                choiceEditor
            } else {
                HStack(spacing: 10) {
                    numberField(
                        title: "Default",
                        value: Binding(
                            get: { parameter.defaultNumber },
                            set: { parameter.defaultNumber = $0; onChanged() }
                        )
                    )

                    numberField(
                        title: "Min",
                        value: Binding(
                            get: { parameter.minNumber },
                            set: { parameter.minNumber = $0; onChanged() }
                        )
                    )

                    numberField(
                        title: "Max",
                        value: Binding(
                            get: { parameter.maxNumber },
                            set: { parameter.maxNumber = $0; onChanged() }
                        )
                    )
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func numberField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var choiceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Options")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let newKey = nextChoiceKey()
                    parameter.choiceOptions.append(
                        EffectsStudioChoiceOption(
                            key: newKey,
                            label: "Option \(parameter.choiceOptions.count + 1)"
                        )
                    )
                    if parameter.defaultChoiceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parameter.defaultChoiceKey = newKey
                    }
                    onChanged()
                } label: {
                    Label("Add Option", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach($parameter.choiceOptions) { $option in
                HStack(spacing: 8) {
                    TextField("key", text: Binding(
                        get: { option.key },
                        set: {
                            let previousKey = option.key
                            option.key = $0
                            if parameter.defaultChoiceKey == previousKey {
                                parameter.defaultChoiceKey = $0
                            }
                            onChanged()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)

                    TextField("label", text: Binding(
                        get: { option.label },
                        set: {
                            option.label = $0
                            onChanged()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button {
                        let removedKey = option.key
                        parameter.choiceOptions.removeAll { $0.id == option.id }
                        if parameter.defaultChoiceKey == removedKey {
                            parameter.defaultChoiceKey = parameter.choiceOptions.first?.key ?? ""
                        }
                        onChanged()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }

            if !parameter.choiceOptions.isEmpty {
                Picker("Default", selection: Binding(
                    get: { parameter.defaultChoiceKey },
                    set: {
                        parameter.defaultChoiceKey = $0
                        onChanged()
                    }
                )) {
                    ForEach(parameter.choiceOptions) { option in
                        Text(option.label.isEmpty ? option.key : option.label)
                            .tag(option.key)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 240, alignment: .leading)
            }
        }
        .font(.caption)
    }

    private func nextChoiceKey() -> String {
        let existing = Set(parameter.choiceOptions.map { $0.key })
        var index = 1
        while existing.contains("option\(index)") {
            index += 1
        }
        return "option\(index)"
    }
}

struct EffectsStudioView: View {
    private enum EffectsStudioPanelID: String, CaseIterable, Identifiable {
        case code
        case parameters
        case manifest
        var id: String { rawValue }
    }

    private struct EffectsStudioCleanScreenSnapshot {
        let showCodePanel: Bool
        let showInspectorPanel: Bool
        let showManifestPanel: Bool
        let showLiveControlsPanel: Bool
        let showLogOverlay: Bool
        let showChrome: Bool
    }

    @ObservedObject var state: HypnographState
    @ObservedObject var settingsStore: EffectsStudioSettingsStore
    @StateObject private var model: EffectsStudioViewModel
    @StateObject private var panelWindows = EffectsStudioPanelWindowController()
    @StateObject private var tabMonitor = EffectsStudioTabKeyMonitor()

    @State private var showPhotosPicker = false
    @State private var selectedPhotosIdentifier: String?

    @State private var autoCompile = true
    @State private var compileGeneration = 0
    @State private var didInitialLoad = false
    @State private var didLoadEffectsStudioUIState = false
    @State private var isApplyingStoredEffectsStudioUIState = false

    @State private var panelOpacity: Double = EffectsStudioSettings.defaultValue.panelOpacity
    @State private var showCodePanel = EffectsStudioSettings.defaultValue.showCodePanel
    @State private var showInspectorPanel = EffectsStudioSettings.defaultValue.showInspectorPanel
    @State private var showManifestPanel = EffectsStudioSettings.defaultValue.showManifestPanel
    @State private var showLiveControlsPanel = EffectsStudioSettings.defaultValue.showLiveControlsPanel
    @State private var showLogOverlay = EffectsStudioSettings.defaultValue.showLogOverlay

    @State private var codePanelX: Double = 20
    @State private var codePanelY: Double = 20
    @State private var codePanelW: Double = 720
    @State private var codePanelH: Double = 520

    @State private var inspectorPanelX: Double = 780
    @State private var inspectorPanelY: Double = 20
    @State private var inspectorPanelW: Double = 390
    @State private var inspectorPanelH: Double = 520
    @State private var manifestPanelX: Double = 860
    @State private var manifestPanelY: Double = 140
    @State private var manifestPanelW: Double = 420
    @State private var manifestPanelH: Double = 420
    @State private var panelStack: [EffectsStudioPanelID] = [.code, .parameters, .manifest]
    @State private var showEffectsStudioChrome = true
    @State private var cleanScreenSnapshot: EffectsStudioCleanScreenSnapshot?

    init(state: HypnographState, settingsStore: EffectsStudioSettingsStore) {
        self.state = state
        self.settingsStore = settingsStore
        _model = StateObject(wrappedValue: EffectsStudioViewModel(settingsStore: settingsStore))
    }

    var body: some View {
        VStack(spacing: 10) {
            if showEffectsStudioChrome {
                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .zIndex(10)
            }

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    previewBackdrop
                    Color.black.opacity(0.20)

                    if showLogOverlay {
                        logOverlay(
                            maxWidth: max(260, proxy.size.width * 0.46),
                            maxHeight: max(120, proxy.size.height - 20)
                        )
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
            }
            .zIndex(1)

            if showEffectsStudioChrome {
                bottomTransportBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .zIndex(10)
            }
        }
        .frame(minWidth: 1240, minHeight: 820)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if !didLoadEffectsStudioUIState {
                applyEffectsStudioUIState(settingsStore.value)
                didLoadEffectsStudioUIState = true
            }
            tabMonitor.start(
                shouldHandleEvent: shouldHandleEffectsStudioTab(event:),
                onTabPressed: toggleEffectsStudioCleanScreen
            )
            guard !didInitialLoad else { return }
            didInitialLoad = true
            model.refreshRuntimeEffectList()
            if !model.selectedRuntimeType.isEmpty {
                model.loadRuntimeEffectAsset()
            }
            model.restoreInitialSource(
                from: state.library,
                preferredLength: max(2.0, state.settings.clipLengthMaxSeconds)
            )
        }
        .onChange(of: model.selectedRuntimeType) { _, newType in
            guard didInitialLoad, !newType.isEmpty else { return }
            model.loadRuntimeEffectAsset()
        }
        .onChange(of: model.sourceCode) { _, _ in queueAutoCompile() }
        .onChange(of: model.parameters) { _, _ in queueAutoCompile() }
        .onChange(of: panelOpacity) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showCodePanel) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showInspectorPanel) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showManifestPanel) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showLiveControlsPanel) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showLogOverlay) { _, _ in persistEffectsStudioUIState() }
        .task(id: compileGeneration) {
            guard autoCompile else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            _ = model.compileCode()
        }
        .background(
            EffectsStudioPanelHostBridge(
                controller: panelWindows,
                showCodePanel: showCodePanel,
                showInspectorPanel: showInspectorPanel,
                showManifestPanel: showManifestPanel,
                showLiveControlsPanel: showLiveControlsPanel,
                panelOpacity: panelOpacity,
                codeContent: AnyView(panelWindowSurface { codePanelContent }),
                inspectorContent: AnyView(panelWindowSurface { inspectorPanelContent }),
                manifestContent: AnyView(panelWindowSurface { manifestPanelContent }),
                liveControlsContent: AnyView(panelWindowSurface { liveControlsPanelContent })
            )
            .frame(width: 0, height: 0)
        )
        .onDisappear {
            cleanScreenSnapshot = nil
            persistEffectsStudioUIState()
            tabMonitor.stop()
            panelWindows.teardown()
        }
        .sheet(isPresented: $showPhotosPicker) {
            PhotosPickerSheet(
                isPresented: $showPhotosPicker,
                preselectedIdentifiers: selectedPhotosIdentifier.map { [$0] } ?? [],
                selectionLimit: 1
            ) { identifiers in
                guard let id = identifiers.first else { return }
                selectedPhotosIdentifier = id
                model.loadPhotosSource(identifier: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .effectsStudioToggleCleanScreen)) { _ in
            toggleEffectsStudioCleanScreen()
        }
    }

    private func panelWindowSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func panelOverlay(totalWidth: CGFloat, totalHeight: CGFloat) -> some View {
        let canvas = CGSize(width: max(100, totalWidth - 24), height: max(100, totalHeight - 24))

        ZStack(alignment: .topLeading) {
            if showCodePanel {
                FloatingEffectsStudioPanel(
                    title: "Code",
                    x: $codePanelX,
                    y: $codePanelY,
                    width: $codePanelW,
                    height: $codePanelH,
                    containerSize: canvas,
                    minWidth: 380,
                    minHeight: 260,
                    maxWidth: max(380, canvas.width),
                    maxHeight: max(260, canvas.height),
                    panelOpacity: panelOpacity,
                    onFrameCommit: persistCodePanelFrame,
                    onInteractionBegan: { bringPanelToFront(.code) }
                ) {
                    codePanelContent
                }
                .zIndex(zIndex(for: .code))
            }

            if showInspectorPanel {
                FloatingEffectsStudioPanel(
                    title: "Parameters",
                    x: $inspectorPanelX,
                    y: $inspectorPanelY,
                    width: $inspectorPanelW,
                    height: $inspectorPanelH,
                    containerSize: canvas,
                    minWidth: 300,
                    minHeight: 260,
                    maxWidth: min(max(300, canvas.width), 620),
                    maxHeight: max(260, canvas.height),
                    panelOpacity: panelOpacity,
                    onFrameCommit: persistInspectorPanelFrame,
                    onInteractionBegan: { bringPanelToFront(.parameters) }
                ) {
                    inspectorPanelContent
                }
                .zIndex(zIndex(for: .parameters))
            }
        }
        .padding(12)
    }

    private var previewBackdrop: some View {
        GeometryReader { proxy in
            if let image = model.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.16),
                        Color(red: 0.03, green: 0.04, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var topBar: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Picker("Effect", selection: $model.selectedRuntimeType) {
                        if model.runtimeEffects.isEmpty {
                            Text("No runtime effects").tag("")
                        } else {
                            Text("Draft (unsaved)").tag("")
                            ForEach(model.runtimeEffects) { effect in
                                Text(effect.displayName).tag(effect.type)
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 260)
                    .disabled(model.runtimeEffects.isEmpty)

                    Button("Refresh") { model.refreshRuntimeEffectList() }
                        .buttonStyle(.bordered)

                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 2)

                    Text("Name")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Effect Name", text: $model.runtimeEffectName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 170, idealWidth: 250, maxWidth: 300)

                    Text("Version")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("1.0.0", text: $model.runtimeEffectVersion)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)

                    Button("Save") { model.saveRuntimeEffectAsset() }
                        .buttonStyle(.borderedProminent)
                    Button(role: .destructive) { model.deleteRuntimeEffectAsset() } label: {
                        Text("Delete")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    Button("New") { model.resetToTemplate() }
                        .buttonStyle(.bordered)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    panelToggleButton("Code", isOn: $showCodePanel)
                    panelToggleButton("Parameters", isOn: $showInspectorPanel)
                    panelToggleButton("Live Controls", isOn: $showLiveControlsPanel)
                    panelToggleButton("Log", isOn: $showLogOverlay)
                    panelToggleButton("Manifest", isOn: $showManifestPanel)

                    Text("Panels")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $panelOpacity, in: 0.22...0.92)
                        .frame(width: 110)
                        .help("Adjust overlay window transparency.")

                    Spacer(minLength: 0)

                    Toggle("Live", isOn: $autoCompile)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Automatically compile after code or parameter edits.")

                    Button("Compile") { _ = model.compileCode() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func panelToggleButton(_ title: String, isOn: Binding<Bool>) -> some View {
        if isOn.wrappedValue {
            Button(title) {
                isOn.wrappedValue.toggle()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(title) {
                isOn.wrappedValue.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func bindingForParameter(id: UUID) -> Binding<EffectsStudioParameterDraft>? {
        guard let index = model.parameters.firstIndex(where: { $0.id == id }) else { return nil }
        return $model.parameters[index]
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let whole = max(0, Int(seconds.rounded(.down)))
        let mins = whole / 60
        let secs = whole % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func logOverlay(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LazyVStack(alignment: .trailing, spacing: 3) {
                        ForEach(Array(model.logEntries.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .id(index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: maxHeight, alignment: .bottomTrailing)
                .padding(.bottom, 1)
            }
            .scrollIndicators(.hidden)
            .frame(width: min(maxWidth, 560))
            .frame(height: maxHeight, alignment: .bottomTrailing)
            .onAppear {
                guard let last = model.logEntries.indices.last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
            .onChange(of: model.logEntries.count) { _, newCount in
                guard newCount > 0 else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newCount - 1, anchor: .bottom)
                }
            }
        }
    }

    private func persistCodePanelFrame(_ rect: CGRect) {}

    private func persistInspectorPanelFrame(_ rect: CGRect) {}

    private func applyEffectsStudioUIState(_ state: EffectsStudioSettings) {
        isApplyingStoredEffectsStudioUIState = true
        panelOpacity = state.panelOpacity
        showCodePanel = state.showCodePanel
        showInspectorPanel = state.showInspectorPanel
        showManifestPanel = state.showManifestPanel
        showLiveControlsPanel = state.showLiveControlsPanel
        showLogOverlay = state.showLogOverlay
        isApplyingStoredEffectsStudioUIState = false
    }

    private func persistEffectsStudioUIState() {
        guard didLoadEffectsStudioUIState, !isApplyingStoredEffectsStudioUIState else { return }
        settingsStore.update { value in
            value.panelOpacity = panelOpacity
            value.showCodePanel = showCodePanel
            value.showInspectorPanel = showInspectorPanel
            value.showManifestPanel = showManifestPanel
            value.showLiveControlsPanel = showLiveControlsPanel
            value.showLogOverlay = showLogOverlay
        }
    }

    private func zIndex(for panel: EffectsStudioPanelID) -> Double {
        guard let index = panelStack.firstIndex(of: panel) else { return 1 }
        return Double(index + 1)
    }

    private func bringPanelToFront(_ panel: EffectsStudioPanelID) {
        guard panelStack.last != panel else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
        panelStack.removeAll { $0 == panel }
        panelStack.append(panel)
        }
    }

    private var codePanelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Live Metal Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(model.sourceCode.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            MetalCodeEditorView(text: $model.sourceCode, insertionRequest: $model.pendingCodeInsertion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private var inspectorPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            parameterDefinitionSection
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var manifestPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            manifestInspectorSection
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var liveControlsPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            liveControlsSection
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var bottomTransportBar: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Menu {
                        Button {
                            model.loadRandomSource(from: state.library, preferredLength: max(2.0, state.settings.clipLengthMaxSeconds))
                        } label: {
                            Label("Random Source", systemImage: "shuffle")
                        }

                        Divider()

                        Button {
                            model.chooseFileSource()
                        } label: {
                            Label("From Files...", systemImage: "doc")
                        }

                        Button {
                            showPhotosPicker = true
                        } label: {
                            Label("From Photos...", systemImage: "photo")
                        }

                        Divider()

                        Button {
                            model.useGeneratedSample()
                        } label: {
                            Label("Use Sample", systemImage: "sparkles")
                        }
                    } label: {
                        Label("Select Source...", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 0)

                    Text("Source: \(model.inputSourceLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    let duration = max(0.1, model.timelineDuration)
                    Text(formatTime(model.time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Slider(value: $model.time, in: 0...duration)

                    Button {
                        model.isPlaying.toggle()
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Text(formatTime(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var parameterDefinitionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Effect ID (UUID) is managed automatically. Edit Name/Version in the top bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("System params `timeSeconds`, `textureWidth`, and `textureHeight` are host-managed and implicit.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Parameter Definitions")
                    .font(.headline)

                Spacer(minLength: 0)

                Button {
                    model.addParameter()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.editableParameterDefinitions) { parameter in
                        if let parameterBinding = bindingForParameter(id: parameter.id) {
                            EffectsStudioParameterDefinitionRow(
                                parameter: parameterBinding,
                                onChanged: { model.parameterDefinitionDidChange() },
                                onInsert: { name in model.insertParameterUsage(name: name) },
                                onRemove: { model.removeParameter(id: parameter.id) }
                            )
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var manifestInspectorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Manifest (read-only)")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(model.manifestPreviewJSON)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var liveControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Controls")
                .font(.headline)

            if !model.autoBoundParameterSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto-bound (host-driven):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.autoBoundParameterSummaries, id: \.self) { summary in
                        Text(summary)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.editableParameterNames.isEmpty {
                Text("No editable parameters (all parameters are auto-bound or unnamed).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.editableParameterNames, id: \.self) { name in
                            if let value = model.parameterValue(named: name),
                               let spec = model.parameterSpec(named: name) {
                                ParameterSliderRow(
                                    name: name,
                                    value: value,
                                    effectType: nil,
                                    spec: spec
                                ) { newValue in
                                    model.updateControlParameter(name: name, value: newValue)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func shouldHandleEffectsStudioTab(event: NSEvent) -> Bool {
        guard state.appSettings.keyboardAccessibilityOverridesEnabled else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPlainTab = modifiers.isEmpty
        let isShiftTab = modifiers == .shift
        guard event.keyCode == 48, (isPlainTab || isShiftTab) else { return false }

        guard isEffectsStudioWindow(NSApp.keyWindow) else { return false }
        if let eventWindow = event.window, !isEffectsStudioWindow(eventWindow) {
            return false
        }
        return true
    }

    private func isEffectsStudioWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window.title == "Effect Studio" {
            return true
        }
        if let parent = window.parent {
            return isEffectsStudioWindow(parent)
        }
        return false
    }

    private func toggleEffectsStudioCleanScreen() {
        if let snapshot = cleanScreenSnapshot {
            // Always restore exactly what was visible when entering clean screen.
            showCodePanel = snapshot.showCodePanel
            showInspectorPanel = snapshot.showInspectorPanel
            showManifestPanel = snapshot.showManifestPanel
            showLiveControlsPanel = snapshot.showLiveControlsPanel
            showLogOverlay = snapshot.showLogOverlay
            showEffectsStudioChrome = snapshot.showChrome

            cleanScreenSnapshot = nil
            focusEffectsStudioHostWindow()
            return
        }

        let hasAnyVisibleOverlay =
            showCodePanel ||
            showInspectorPanel ||
            showManifestPanel ||
            showLiveControlsPanel ||
            showLogOverlay

        // If there is literally nothing visible, clean-screen toggle is a no-op.
        guard hasAnyVisibleOverlay || showEffectsStudioChrome else { return }

            cleanScreenSnapshot = EffectsStudioCleanScreenSnapshot(
                showCodePanel: showCodePanel,
                showInspectorPanel: showInspectorPanel,
                showManifestPanel: showManifestPanel,
                showLiveControlsPanel: showLiveControlsPanel,
                showLogOverlay: showLogOverlay,
                showChrome: showEffectsStudioChrome
            )

        showCodePanel = false
        showInspectorPanel = false
        showManifestPanel = false
        showLiveControlsPanel = false
        showLogOverlay = false
        showEffectsStudioChrome = false
        focusEffectsStudioHostWindow()
    }

    private func focusEffectsStudioHostWindow() {
        guard let studioWindow = NSApp.windows.first(where: { $0.title == "Effect Studio" }) else { return }
        studioWindow.makeKeyAndOrderFront(nil)
    }

    private func queueAutoCompile() {
        guard autoCompile else { return }
        compileGeneration &+= 1
    }
}

@MainActor
private final class EffectsStudioTabKeyMonitor: ObservableObject {
    private var keyMonitor: Any?
    private var shouldHandleEvent: ((NSEvent) -> Bool)?
    private var onTabPressed: (() -> Void)?

    func start(
        shouldHandleEvent: @escaping (NSEvent) -> Bool,
        onTabPressed: @escaping () -> Void
    ) {
        stop()
        self.shouldHandleEvent = shouldHandleEvent
        self.onTabPressed = onTabPressed

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldHandleEvent?(event) == true else { return event }
            if event.isARepeat {
                return nil
            }
            self.onTabPressed?()
            return nil
        }
    }

    func stop() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        shouldHandleEvent = nil
        onTabPressed = nil
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}

private enum EffectsStudioPanelKind: String, CaseIterable {
    case code
    case parameters
    case manifest
    case liveControls

    var title: String {
        switch self {
        case .code: return "Code"
        case .parameters: return "Parameters"
        case .manifest: return "Manifest"
        case .liveControls: return "Live Controls"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .code: return CGSize(width: 760, height: 560)
        case .parameters: return CGSize(width: 460, height: 620)
        case .manifest: return CGSize(width: 460, height: 460)
        case .liveControls: return CGSize(width: 420, height: 520)
        }
    }

    var minSize: CGSize {
        switch self {
        case .code: return CGSize(width: 420, height: 280)
        case .parameters: return CGSize(width: 360, height: 360)
        case .manifest: return CGSize(width: 340, height: 280)
        case .liveControls: return CGSize(width: 320, height: 300)
        }
    }

    var defaultOffset: CGPoint {
        switch self {
        case .code: return CGPoint(x: 36, y: 80)
        case .parameters: return CGPoint(x: 820, y: 70)
        case .manifest: return CGPoint(x: 860, y: 160)
        case .liveControls: return CGPoint(x: 900, y: 260)
        }
    }

    var autosaveName: String {
        "Hypnograph.EffectsStudio.\(rawValue)"
    }
}

private final class EffectsStudioChildPanel: NSPanel {
    var onUserInteraction: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func toggleFullScreen(_ sender: Any?) {
        if let parent {
            parent.toggleFullScreen(sender)
            return
        }
        super.toggleFullScreen(sender)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            onUserInteraction?()
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class EffectsStudioPanelWindowController: ObservableObject {
    private struct ManagedPanel {
        let panel: EffectsStudioChildPanel
        let host: NSHostingController<AnyView>
    }

    private weak var parentWindow: NSWindow?
    private var panels: [EffectsStudioPanelKind: ManagedPanel] = [:]
    private var parentCloseObserver: NSObjectProtocol?

    func sync(
        parentWindow: NSWindow?,
        showCodePanel: Bool,
        showInspectorPanel: Bool,
        showManifestPanel: Bool,
        showLiveControlsPanel: Bool,
        panelOpacity: Double,
        codeContent: AnyView,
        inspectorContent: AnyView,
        manifestContent: AnyView,
        liveControlsContent: AnyView
    ) {
        guard let parentWindow else {
            hideAllPanels()
            return
        }

        if self.parentWindow !== parentWindow {
            detachFromCurrentParent()
            removeParentCloseObserver()
            self.parentWindow = parentWindow
            installParentCloseObserver(for: parentWindow)
        }

        guard parentWindow.isVisible else {
            hideAllPanels()
            return
        }

        configureParentWindowForFullScreen(parentWindow)

        let opacity = min(max(panelOpacity, 0.15), 1.0)
        syncPanel(kind: .code, visible: showCodePanel, opacity: opacity, content: codeContent, parentWindow: parentWindow)
        syncPanel(kind: .parameters, visible: showInspectorPanel, opacity: opacity, content: inspectorContent, parentWindow: parentWindow)
        syncPanel(kind: .manifest, visible: showManifestPanel, opacity: opacity, content: manifestContent, parentWindow: parentWindow)
        syncPanel(kind: .liveControls, visible: showLiveControlsPanel, opacity: opacity, content: liveControlsContent, parentWindow: parentWindow)
    }

    func teardown() {
        hideAllPanels()
        detachFromCurrentParent()
        removeParentCloseObserver()
        panels.values.forEach { $0.panel.close() }
        panels.removeAll()
        parentWindow = nil
    }

    private func syncPanel(
        kind: EffectsStudioPanelKind,
        visible: Bool,
        opacity: Double,
        content: AnyView,
        parentWindow: NSWindow
    ) {
        if visible {
            let managed = ensurePanel(kind: kind, parentWindow: parentWindow)
            managed.host.rootView = content
            managed.panel.alphaValue = opacity

            if managed.panel.parent == nil {
                parentWindow.addChildWindow(managed.panel, ordered: .above)
            }
            if !managed.panel.isVisible {
                managed.panel.orderFront(nil)
            }
        } else if let managed = panels[kind] {
            managed.panel.orderOut(nil)
        }
    }

    private func ensurePanel(kind: EffectsStudioPanelKind, parentWindow: NSWindow) -> ManagedPanel {
        if let existing = panels[kind] {
            return existing
        }

        let frame = defaultFrame(kind: kind, parentWindow: parentWindow)
        let panel = EffectsStudioChildPanel(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = parentWindow.level
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.minSize = kind.minSize
        panel.setFrameAutosaveName(kind.autosaveName)
        _ = panel.setFrameUsingName(kind.autosaveName, force: false)
        panel.onUserInteraction = { [weak self, weak panel] in
            guard let self, let panel else { return }
            bringToFront(panel)
        }

        let host = NSHostingController(rootView: AnyView(EmptyView()))
        panel.contentViewController = host

        let managed = ManagedPanel(panel: panel, host: host)
        panels[kind] = managed
        return managed
    }

    private func configureParentWindowForFullScreen(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        if !behavior.contains(.fullScreenPrimary) {
            behavior.insert(.fullScreenPrimary)
            window.collectionBehavior = behavior
        }
    }

    private func defaultFrame(kind: EffectsStudioPanelKind, parentWindow: NSWindow) -> NSRect {
        let parentFrame = parentWindow.frame
        let size = kind.defaultSize
        let offset = kind.defaultOffset
        let x = parentFrame.minX + offset.x
        let y = parentFrame.maxY - offset.y - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func hideAllPanels() {
        panels.values.forEach { $0.panel.orderOut(nil) }
    }

    private func bringToFront(_ panel: NSPanel) {
        if let parentWindow, panel.parent === parentWindow {
            parentWindow.removeChildWindow(panel)
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func detachFromCurrentParent() {
        guard let currentParent = parentWindow else { return }
        panels.values.forEach { managed in
            if managed.panel.parent === currentParent {
                currentParent.removeChildWindow(managed.panel)
            }
        }
    }

    private func installParentCloseObserver(for window: NSWindow) {
        parentCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.handleParentWillClose()
        }
    }

    private func removeParentCloseObserver() {
        if let observer = parentCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            parentCloseObserver = nil
        }
    }

    private func handleParentWillClose() {
        hideAllPanels()
        detachFromCurrentParent()
        parentWindow = nil
    }
}

private struct EffectsStudioPanelHostBridge: NSViewRepresentable {
    @ObservedObject var controller: EffectsStudioPanelWindowController
    let showCodePanel: Bool
    let showInspectorPanel: Bool
    let showManifestPanel: Bool
    let showLiveControlsPanel: Bool
    let panelOpacity: Double
    let codeContent: AnyView
    let inspectorContent: AnyView
    let manifestContent: AnyView
    let liveControlsContent: AnyView

    final class Coordinator {
        var controller: EffectsStudioPanelWindowController
        init(controller: EffectsStudioPanelWindowController) {
            self.controller = controller
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.controller = controller
        context.coordinator.controller.sync(
            parentWindow: nsView.window,
            showCodePanel: showCodePanel,
            showInspectorPanel: showInspectorPanel,
            showManifestPanel: showManifestPanel,
            showLiveControlsPanel: showLiveControlsPanel,
            panelOpacity: panelOpacity,
            codeContent: codeContent,
            inspectorContent: inspectorContent,
            manifestContent: manifestContent,
            liveControlsContent: liveControlsContent
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.controller.teardown()
    }
}

private struct FloatingEffectsStudioPanel<Content: View>: View {
    let title: String
    @Binding var x: Double
    @Binding var y: Double
    @Binding var width: Double
    @Binding var height: Double
    let containerSize: CGSize
    let minWidth: CGFloat
    let minHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let panelOpacity: Double
    let onFrameCommit: ((CGRect) -> Void)?
    let onInteractionBegan: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var moveStartRect: CGRect?

    var body: some View {
        let rect = normalizedRect()

        VStack(spacing: 0) {
            moveHandle(rect: rect)
            content()
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: rect.width, height: rect.height)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(clampedOpacity(panelOpacity))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .simultaneousGesture(
            TapGesture().onEnded {
                onInteractionBegan?()
            }
        )
        .overlay {
            FloatingPanelInteractionOverlay(
                x: $x,
                y: $y,
                width: $width,
                height: $height,
                containerSize: containerSize,
                minWidth: minWidth,
                minHeight: minHeight,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                onInteractionBegan: onInteractionBegan
            ) { rect, committed in
                if committed {
                    onFrameCommit?(rect)
                }
            }
        }
        .offset(x: rect.minX, y: rect.minY)
    }

    @ViewBuilder
    private func moveHandle(rect: CGRect) -> some View {
        HStack {
            Spacer(minLength: 0)
            Capsule()
                .fill(Color.white.opacity(0.30))
                .frame(width: 42, height: 4)
                .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if moveStartRect == nil {
                        moveStartRect = rect
                        onInteractionBegan?()
                    }
                    guard let start = moveStartRect else { return }
                    var updated = start
                    updated.origin.x = start.minX + value.translation.width
                    updated.origin.y = start.minY + value.translation.height
                    let clamped = clampedRect(updated)
                    x = Double(clamped.minX)
                    y = Double(clamped.minY)
                }
                .onEnded { _ in
                    let clamped = normalizedRect()
                    x = Double(clamped.minX)
                    y = Double(clamped.minY)
                    moveStartRect = nil
                    onFrameCommit?(clamped)
                }
        )
    }

    private func normalizedRect() -> CGRect {
        let boundedMaxWidth = max(minWidth, min(maxWidth, containerSize.width))
        let boundedMaxHeight = max(minHeight, min(maxHeight, containerSize.height))

        var w = min(max(CGFloat(width), minWidth), boundedMaxWidth)
        var h = min(max(CGFloat(height), minHeight), boundedMaxHeight)
        w = min(w, containerSize.width)
        h = min(h, containerSize.height)

        var originX = CGFloat(x)
        var originY = CGFloat(y)
        let maxX = max(0, containerSize.width - w)
        let maxY = max(0, containerSize.height - h)
        originX = min(max(originX, 0), maxX)
        originY = min(max(originY, 0), maxY)

        return CGRect(x: originX, y: originY, width: w, height: h)
    }

    private func clampedRect(_ rect: CGRect) -> CGRect {
        let current = normalizedRect()
        let w = current.width
        let h = current.height
        let maxX = max(0, containerSize.width - w)
        let maxY = max(0, containerSize.height - h)
        let x = min(max(rect.minX, 0), maxX)
        let y = min(max(rect.minY, 0), maxY)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func clampedOpacity(_ value: Double) -> Double {
        min(max(value, 0.1), 1.0)
    }
}

private struct FloatingPanelInteractionOverlay: NSViewRepresentable {
    @Binding var x: Double
    @Binding var y: Double
    @Binding var width: Double
    @Binding var height: Double

    let containerSize: CGSize
    let minWidth: CGFloat
    let minHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let onInteractionBegan: (() -> Void)?
    let onRectChanged: (CGRect, Bool) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.onRectUpdate = { rect, committed in
            x = Double(rect.minX)
            y = Double(rect.minY)
            width = Double(rect.width)
            height = Double(rect.height)
            onRectChanged(rect, committed)
        }
        view.onInteractionBegan = onInteractionBegan
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.modelRect = CGRect(x: x, y: y, width: width, height: height)
        nsView.containerSize = containerSize
        nsView.minWidth = minWidth
        nsView.minHeight = minHeight
        nsView.maxWidth = maxWidth
        nsView.maxHeight = maxHeight
        nsView.onInteractionBegan = onInteractionBegan
    }

    final class InteractionView: NSView {
        enum Mode {
            case left
            case right
            case top
            case bottom
            case topLeft
            case topRight
            case bottomLeft
            case bottomRight

            var hasLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
            var hasRight: Bool { self == .right || self == .topRight || self == .bottomRight }
            var hasTop: Bool { self == .top || self == .topLeft || self == .topRight }
            var hasBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
        }

        override var isFlipped: Bool { true }

        var modelRect: CGRect = .zero
        var containerSize: CGSize = .zero
        var minWidth: CGFloat = 280
        var minHeight: CGFloat = 220
        var maxWidth: CGFloat = 2000
        var maxHeight: CGFloat = 2000
        var onRectUpdate: ((CGRect, Bool) -> Void)?
        var onInteractionBegan: (() -> Void)?

        private let edgeThreshold: CGFloat = 8

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            return interactionMode(at: point) == nil ? nil : self
        }

        override func resetCursorRects() {
            discardCursorRects()
            let band = edgeThreshold
            let left = NSRect(x: 0, y: band, width: band, height: max(0, bounds.height - band * 2))
            let right = NSRect(x: max(bounds.width - band, 0), y: band, width: band, height: max(0, bounds.height - band * 2))
            let top = NSRect(x: band, y: 0, width: max(0, bounds.width - band * 2), height: band)
            let bottom = NSRect(x: band, y: max(bounds.height - band, 0), width: max(0, bounds.width - band * 2), height: band)
            addCursorRect(left, cursor: .resizeLeftRight)
            addCursorRect(right, cursor: .resizeLeftRight)
            addCursorRect(top, cursor: .resizeUpDown)
            addCursorRect(bottom, cursor: .resizeUpDown)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let localStart = convert(event.locationInWindow, from: nil)
            guard let mode = interactionMode(at: localStart) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onInteractionBegan?()
            }
            let startFrame = modelRect
            let startWindowPoint = event.locationInWindow
            var latestFrame = startFrame

            while let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) {
                switch next.type {
                case .leftMouseDragged:
                    let currentPoint = next.locationInWindow
                    let deltaX = currentPoint.x - startWindowPoint.x
                    let deltaY = startWindowPoint.y - currentPoint.y
                    latestFrame = resolvedRect(from: startFrame, mode: mode, deltaX: deltaX, deltaY: deltaY)
                    modelRect = latestFrame
                    onRectUpdate?(latestFrame, false)
                case .leftMouseUp:
                    onRectUpdate?(latestFrame, true)
                    return
                default:
                    break
                }
            }
        }

        private func interactionMode(at point: CGPoint) -> Mode? {
            let nearLeft = point.x <= edgeThreshold
            let nearRight = point.x >= bounds.width - edgeThreshold
            let nearTop = point.y <= edgeThreshold
            let nearBottom = point.y >= bounds.height - edgeThreshold

            if nearLeft && nearTop { return .topLeft }
            if nearRight && nearTop { return .topRight }
            if nearLeft && nearBottom { return .bottomLeft }
            if nearRight && nearBottom { return .bottomRight }
            if nearLeft { return .left }
            if nearRight { return .right }
            if nearTop { return .top }
            if nearBottom { return .bottom }
            return nil
        }

        private func resolvedRect(from start: CGRect, mode: Mode, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
            let boundedMaxWidth = max(minWidth, min(maxWidth, containerSize.width))
            let boundedMaxHeight = max(minHeight, min(maxHeight, containerSize.height))

            var x = start.minX
            var y = start.minY
            var w = start.width
            var h = start.height

            if mode.hasLeft {
                x += deltaX
                w -= deltaX
            }
            if mode.hasRight {
                w += deltaX
            }
            if mode.hasTop {
                y += deltaY
                h -= deltaY
            }
            if mode.hasBottom {
                h += deltaY
            }

            w = min(max(w, minWidth), boundedMaxWidth)
            h = min(max(h, minHeight), boundedMaxHeight)

            if mode.hasLeft {
                x = start.maxX - w
            }
            if mode.hasTop {
                y = start.maxY - h
            }

            let maxX = max(0, containerSize.width - w)
            let maxY = max(0, containerSize.height - h)
            x = min(max(x, 0), maxX)
            y = min(max(y, 0), maxY)

            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
}

#Preview {
    Text("Effect Studio")
}
