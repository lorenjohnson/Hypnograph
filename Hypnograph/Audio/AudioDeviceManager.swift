//
//  AudioDeviceManager.swift
//  Hypnograph
//
//  Manages audio output device discovery and routing.
//

import Foundation
import CoreAudio
import Combine

/// Represents an audio output device
struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    
    /// Special "None" device representing muted state
    static let none = AudioOutputDevice(id: 0, uid: "none", name: "None")
    
    /// System default device
    static let systemDefault = AudioOutputDevice(id: 0, uid: "default", name: "System Default")
}

/// Manages discovery of audio output devices
@MainActor
class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()
    
    @Published private(set) var outputDevices: [AudioOutputDevice] = []
    
    private init() {
        refreshDevices()
        setupDeviceChangeListener()
    }
    
    /// Refresh the list of available output devices
    func refreshDevices() {
        var devices: [AudioOutputDevice] = [.none]
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        guard status == noErr else {
            print("⚠️ AudioDeviceManager: Failed to get device list size")
            outputDevices = devices
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("⚠️ AudioDeviceManager: Failed to get device list")
            outputDevices = devices
            return
        }
        
        for deviceID in deviceIDs {
            // Check if device has output channels
            if hasOutputChannels(deviceID: deviceID) {
                if let name = getDeviceName(deviceID: deviceID),
                   let uid = getDeviceUID(deviceID: deviceID) {
                    devices.append(AudioOutputDevice(id: deviceID, uid: uid, name: name))
                }
            }
        }
        
        outputDevices = devices
        print("🔊 AudioDeviceManager: Found \(devices.count - 1) output devices")
    }
    
    private func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }
        
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferList.deallocate() }
        
        let status2 = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferList)
        guard status2 == noErr else { return false }
        
        // Check if any buffers have channels
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }
    
    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        return status == noErr ? name as String : nil
    }
    
    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)
        return status == noErr ? uid as String : nil
    }
    
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?

    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        deviceListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }

        if let block = deviceListenerBlock {
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                DispatchQueue.main,
                block
            )
            if status == noErr {
                print("🔊 AudioDeviceManager: Listening for device changes")
            }
        }
    }

    deinit {
        if let block = deviceListenerBlock {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                DispatchQueue.main,
                block
            )
        }
    }
}

