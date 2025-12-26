//
//  AudioRouter.swift
//  Hypnograph
//
//  Routes AVPlayer audio to specific output devices using AVAudioEngine.
//
//  Strategy: Use MTAudioProcessingTap to intercept audio from AVPlayer,
//  then push it to an AVAudioEngine configured for a specific output device.
//

import Foundation
import AVFoundation
import CoreAudio

/// Routes audio from an AVPlayer to a specific output device
class AudioRouter {
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var currentDeviceID: AudioDeviceID = 0
    private var processingFormat: AVAudioFormat?
    private var mixerFormat: AVAudioFormat?

    /// Whether audio routing is active
    private(set) var isActive: Bool = false

    /// The current output device
    private(set) var currentDevice: AudioOutputDevice?

    /// Lock for thread-safe buffer scheduling
    private let bufferLock = NSLock()

    /// Volume level (0.0 to 1.0)
    var volume: Float = 1.0 {
        didSet {
            audioEngine.mainMixerNode.outputVolume = volume
        }
    }

    init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // Attach player node
        audioEngine.attach(playerNode)

        // Connect with a standard format - will be reconfigured when we get actual audio
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: defaultFormat)
        mixerFormat = defaultFormat
    }

    /// Set the output device for this router
    /// - Parameter device: The audio device to route to, or nil/none to disable
    func setOutputDevice(_ device: AudioOutputDevice?) {
        let wasActive = isActive

        // Stop current playback
        if wasActive {
            stopEngine()
        }

        guard let device = device, device != .none, device.id != 0 else {
            currentDevice = nil
            currentDeviceID = 0
            print("🔊 AudioRouter: Disabled (no device)")
            return
        }

        currentDevice = device
        currentDeviceID = device.id

        // Configure and start engine with new device
        configureEngineOutput()
    }

    /// Configure the audio engine to output to the selected device
    private func configureEngineOutput() {
        guard currentDeviceID != 0 else { return }

        do {
            // Set the output device on the output node's audio unit
            let outputNode = audioEngine.outputNode
            guard let audioUnit = outputNode.audioUnit else {
                print("⚠️ AudioRouter: No audio unit on output node")
                return
            }

            var deviceID = currentDeviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )

            if status == noErr {
                print("🔊 AudioRouter: Set output device to \(currentDevice?.name ?? "unknown") (ID: \(currentDeviceID))")
            } else {
                print("⚠️ AudioRouter: Failed to set output device: \(status)")
                return
            }

            // Prepare and start the engine
            audioEngine.prepare()
            try audioEngine.start()
            playerNode.play()
            isActive = true
            print("🔊 AudioRouter: Engine started with device \(currentDevice?.name ?? "unknown")")
        } catch {
            print("⚠️ AudioRouter: Failed to start engine: \(error)")
            isActive = false
        }
    }

    /// Stop the audio engine
    func stopEngine() {
        playerNode.stop()
        audioEngine.stop()
        isActive = false
    }

    /// Schedule audio buffer from the tap to play through the engine
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isActive else { return }

        bufferLock.lock()
        defer { bufferLock.unlock() }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Create an audio mix with a processing tap for the given player item
    /// The tap intercepts audio and routes it to this router's output device
    func createAudioMix(for playerItem: AVPlayerItem) -> AVAudioMix? {
        // Try to get audio tracks - use synchronous method first
        var audioTracks = playerItem.asset.tracks(withMediaType: .audio)

        // If empty, it might be an AVComposition - check tracks on the item itself
        if audioTracks.isEmpty {
            // For compositions, also check the player item's tracks
            audioTracks = playerItem.tracks.compactMap { $0.assetTrack }.filter { $0.mediaType == .audio }
        }

        guard let assetTrack = audioTracks.first else {
            print("⚠️ AudioRouter: No audio track found in asset (tried asset.tracks and playerItem.tracks)")
            return nil
        }

        print("🔊 AudioRouter: Found audio track: \(assetTrack.trackID)")

        // Create callbacks struct with self as client info
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: audioTapInit,
            finalize: audioTapFinalize,
            prepare: audioTapPrepare,
            unprepare: audioTapUnprepare,
            process: audioTapProcess
        )

        var tapRef: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapRef
        )

        guard status == noErr, let tap = tapRef else {
            print("⚠️ AudioRouter: Failed to create audio tap: \(status)")
            return nil
        }

        let inputParams = AVMutableAudioMixInputParameters(track: assetTrack)
        inputParams.audioTapProcessor = tap

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]

        print("🔊 AudioRouter: Created audio mix with processing tap for track \(assetTrack.trackID)")
        return audioMix
    }

    /// Async version of createAudioMix that loads tracks asynchronously
    /// Use this when applying to a currently playing item where tracks may need loading
    func createAudioMixAsync(for playerItem: AVPlayerItem) async -> AVAudioMix? {
        do {
            let audioTracks = try await playerItem.asset.loadTracks(withMediaType: .audio)
            guard let assetTrack = audioTracks.first else {
                print("⚠️ AudioRouter: No audio track found in asset (async)")
                return nil
            }

            print("🔊 AudioRouter: Found audio track (async): \(assetTrack.trackID)")

            // Create callbacks struct with self as client info
            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: Unmanaged.passUnretained(self).toOpaque(),
                init: audioTapInit,
                finalize: audioTapFinalize,
                prepare: audioTapPrepare,
                unprepare: audioTapUnprepare,
                process: audioTapProcess
            )

            var tapRef: MTAudioProcessingTap?
            let status = MTAudioProcessingTapCreate(
                kCFAllocatorDefault,
                &callbacks,
                kMTAudioProcessingTapCreationFlag_PostEffects,
                &tapRef
            )

            guard status == noErr, let tap = tapRef else {
                print("⚠️ AudioRouter: Failed to create audio tap (async): \(status)")
                return nil
            }

            let inputParams = AVMutableAudioMixInputParameters(track: assetTrack)
            inputParams.audioTapProcessor = tap

            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [inputParams]

            print("🔊 AudioRouter: Created audio mix with processing tap (async)")
            return audioMix
        } catch {
            print("⚠️ AudioRouter: Failed to load audio tracks: \(error)")
            return nil
        }
    }

    deinit {
        stopEngine()
    }
}

// MARK: - MTAudioProcessingTap Callbacks

/// Called when tap is initialized
private func audioTapInit(
    tap: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    // Store the router reference for later callbacks
    tapStorageOut.pointee = clientInfo
}

/// Called when tap is finalized
private func audioTapFinalize(tap: MTAudioProcessingTap) {
    // Nothing to clean up
}

/// Called when tap is prepared with the audio format
private func audioTapPrepare(
    tap: MTAudioProcessingTap,
    maxFrames: CMItemCount,
    processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    // Could reconfigure engine format here if needed
}

/// Called when tap is unprepared
private func audioTapUnprepare(tap: MTAudioProcessingTap) {
    // Nothing to clean up
}

/// Called for each audio buffer - this is where we intercept and route audio
private func audioTapProcess(
    tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    // Get the source audio first
    var sourceFlags = MTAudioProcessingTapFlags()
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        &sourceFlags,
        nil,
        numberFramesOut
    )

    guard status == noErr else { return }

    // Get the router from storage
    let storage = MTAudioProcessingTapGetStorage(tap)
    let router = Unmanaged<AudioRouter>.fromOpaque(storage).takeUnretainedValue()

    // If router is not active, just let audio pass through to system default
    guard router.isActive else { return }

    // Get the actual format from the audio buffer
    let ablPointer = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    guard ablPointer.count > 0 else { return }

    // Try to determine sample rate from buffer size and frame count
    // Most video files use 44100 or 48000
    let sampleRate: Double = 48000
    let channelCount = min(ablPointer.count, 2)

    // Create AVAudioPCMBuffer from the audio buffer list
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: AVAudioChannelCount(channelCount),
        interleaved: false
    ) else { return }

    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numberFrames)) else {
        return
    }
    pcmBuffer.frameLength = AVAudioFrameCount(numberFramesOut.pointee)

    // Copy audio data from buffer list to PCM buffer
    for (index, buffer) in ablPointer.enumerated() {
        guard index < channelCount,
              let src = buffer.mData,
              let dst = pcmBuffer.floatChannelData?[index] else { continue }

        memcpy(dst, src, Int(buffer.mDataByteSize))
    }

    // Schedule buffer on the router's engine
    router.scheduleBuffer(pcmBuffer)

    // Zero out the original buffer so AVPlayer doesn't also play through system default
    // This ensures audio only goes to the routed device
    for buffer in ablPointer {
        if let data = buffer.mData {
            memset(data, 0, Int(buffer.mDataByteSize))
        }
    }
}

