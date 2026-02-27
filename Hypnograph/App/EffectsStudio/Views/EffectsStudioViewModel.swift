//
//  EffectsStudioViewModel.swift
//  Hypnograph
//

import SwiftUI
import AppKit
import CoreImage
import AVFoundation
import Metal
import Foundation
import HypnoCore

@MainActor
final class EffectsStudioViewModel: ObservableObject {
    static let defaultRuntimeBindings = RuntimeMetalBindingsManifest(
        parameterBufferIndex: 0,
        inputTextures: [
            RuntimeMetalTextureBindingManifest(argumentIndex: 0, source: .currentFrame, historyOffset: nil)
        ],
        outputTextureIndex: 1
    )

    let settingsStore: EffectsStudioSettingsStore
    let runtimeEffectsService: RuntimeEffectsService
    let metalRenderService: MetalRenderService

    @Published var runtimeEffectUUID: String = UUID().uuidString.lowercased()
    @Published var runtimeEffectName: String = "New Effect"
    @Published var runtimeEffectVersion: String = "1.0.0"
    @Published var runtimeEffects: [EffectsStudioRuntimeEffectChoice] = []
    @Published var selectedRuntimeType: String = ""

    @Published var sourceCode: String = EffectsStudioViewModel.defaultCodeBody
    @Published var compileLog: String = "Compile to render preview." {
        didSet { appendLogEntry(from: compileLog) }
    }
    @Published var logEntries: [String] = []

    @Published var parameters: [EffectsStudioParameterDraft] = EffectsStudioViewModel.defaultParameters
    @Published var parameterValues: [String: AnyCodableValue] = [:]
    @Published var pendingCodeInsertion: String?

    @Published var previewImage: NSImage?
    @Published var inputSourceLabel: String = "Generated Sample"
    @Published var timelineDuration: Double = 12

    @Published var time: Double = 0 {
        didSet { renderPreview() }
    }

    @Published var isPlaying: Bool = false {
        didSet { updatePlaybackLoop() }
    }

    let previewSize = CGSize(width: 960, height: 540)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    let device: MTLDevice?
    let commandQueue: MTLCommandQueue?
    let ciContext: CIContext

    var pipelineState: MTLComputePipelineState?
    var parameterBufferLayout: EffectsStudioParamBufferLayout?
    var hasAppliedInitialRuntimeSelection = false
    var activeRuntimeKind: EffectRuntimeKind = .metal
    var activeRequiredLookback: Int = 0
    var activeUsesPersistentState: Bool = false
    var activeBindings: RuntimeMetalBindingsManifest = EffectsStudioViewModel.defaultRuntimeBindings

    var sourceStillImage: CIImage?
    var sourceVideoAsset: AVAsset?
    var videoFrameGenerator: AVAssetImageGenerator?
    var videoFrameGeneratorAssetID: ObjectIdentifier?
    var lastVideoFrameImage: CIImage?
    var playbackTask: Task<Void, Never>?
    var lastPlaybackTickUptimeNs: UInt64?
    var frameCounter: UInt32 = 0
    var previewFrameHistory: [CIImage] = []

    var effectFunctionName: String {
        RuntimeMetalEffectLibrary.defaultFunctionName
    }

    init(
        settingsStore: EffectsStudioSettingsStore,
        runtimeEffectsService: RuntimeEffectsService = .live,
        metalRenderService: MetalRenderService = .live
    ) {
        self.settingsStore = settingsStore
        self.runtimeEffectsService = runtimeEffectsService
        self.metalRenderService = metalRenderService
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

}
