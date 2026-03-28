//
//  AudioController.swift
//  Hypnograph
//
//  Manages audio output devices and volumes for in-app and live players.
//  Handles device discovery, selection persistence, and device disconnect handling.
//

import Foundation
import Combine
import HypnoCore

/// Manages audio output routing for Main's in-app and live players
@MainActor
final class AudioController: ObservableObject {

    // MARK: - Published State

    /// Selected audio output device for in-app player (nil = system default)
    @Published var audioDevice: AudioOutputDevice?

    /// Selected audio output device for Live player (nil = system default)
    @Published var liveAudioDevice: AudioOutputDevice?

    /// Volume level for in-app audio (0.0 to 1.0)
    @Published var volume: Float = 1.0

    /// Volume level for Live audio (0.0 to 1.0)
    @Published var liveVolume: Float = 1.0

    // MARK: - Dependencies

    private let audioManager = AudioDeviceManager.shared
    private weak var settingsStore: WorkspaceSettingsStore?
    private weak var livePlayer: LivePlayer?
    private var subscriptions: Set<AnyCancellable> = []

    // MARK: - Computed Properties

    /// Get the device UID for in-app audio routing (nil = system default)
    var audioDeviceUID: String? {
        audioDevice?.uid
    }

    /// Get the device UID for live audio routing (nil = system default)
    var liveAudioDeviceUID: String? {
        liveAudioDevice?.uid
    }

    // MARK: - Init

    init(settingsStore: WorkspaceSettingsStore, livePlayer: LivePlayer) {
        self.settingsStore = settingsStore
        self.livePlayer = livePlayer

        loadAudioSettings(from: settingsStore.value)
        setupSubscriptions()
    }

    // MARK: - Setup

    private func setupSubscriptions() {
        // Watch for device list changes (device disconnected)
        audioManager.$outputDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.handleDeviceListChange(devices)
            }
            .store(in: &subscriptions)

        // Live volume changes
        $liveVolume
            .receive(on: RunLoop.main)
            .dropFirst()  // Skip initial value (loaded from settings)
            .sink { [weak self] volume in
                guard let self = self else { return }
                self.livePlayer?.setVolume(volume)
                self.saveAudioSettings()
            }
            .store(in: &subscriptions)

        // Live audio device changes
        $liveAudioDevice
            .receive(on: RunLoop.main)
            .dropFirst()  // Skip initial value (loaded from settings)
            .sink { [weak self] device in
                guard let self = self else { return }
                let deviceUID = device?.uid
                print("🔊 AudioController: liveAudioDevice changed to \(device?.name ?? "nil"), uid=\(deviceUID ?? "System Default")")
                self.livePlayer?.setAudioDevice(deviceUID)
                self.saveAudioSettings()
            }
            .store(in: &subscriptions)

        // In-app audio device changes (for saving settings)
        $audioDevice
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in
                self?.saveAudioSettings()
            }
            .store(in: &subscriptions)

        // In-app volume changes (for saving settings)
        $volume
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in
                self?.saveAudioSettings()
            }
            .store(in: &subscriptions)
    }

    // MARK: - WorkspaceSettings Persistence

    /// Load audio device and volume settings from WorkspaceSettings
    private func loadAudioSettings(from settings: WorkspaceSettings) {
        // Load volumes
        volume = settings.volume
        liveVolume = settings.liveVolume

        // Load devices by UID, defaulting to system default if not found
        audioDevice = findAudioDevice(byUID: settings.audioDeviceUID)
        liveAudioDevice = findAudioDevice(byUID: settings.liveAudioDeviceUID)

        // Apply initial live audio settings to LivePlayer
        // (subscriptions use .dropFirst() so initial values aren't applied via Combine)
        livePlayer?.setVolume(liveVolume)
        livePlayer?.setAudioDevice(liveAudioDevice?.uid)

        print("🔊 AudioController: Loaded audio settings - in-app: \(audioDevice?.name ?? "System Default") @ \(volume), live: \(liveAudioDevice?.name ?? "System Default") @ \(liveVolume)")
    }

    /// Save audio device and volume settings to WorkspaceSettings
    private func saveAudioSettings() {
        settingsStore?.update { settings in
            settings.audioDeviceUID = audioDevice?.uid
            settings.volume = volume
            settings.liveAudioDeviceUID = liveAudioDevice?.uid
            settings.liveVolume = liveVolume
        }
    }

    // MARK: - Device Management

    /// Find audio device by UID, returns system default if not found
    private func findAudioDevice(byUID uid: String?) -> AudioOutputDevice? {
        guard let uid = uid else { return audioManager.systemDefault }
        return audioManager.outputDevices.first { $0.uid == uid } ?? audioManager.systemDefault
    }

    /// Handle device list changes - switch to system default if current device is no longer available
    private func handleDeviceListChange(_ devices: [AudioOutputDevice]) {
        // Check in-app device
        if let device = audioDevice,
           !device.isSystemDefault,
           !devices.contains(where: { $0.uid == device.uid }) {
            print("🔊 AudioController: In-app audio device '\(device.name)' disconnected, switching to System Default")
            audioDevice = audioManager.systemDefault
        }

        // Check live device
        if let live = liveAudioDevice,
           !live.isSystemDefault,
           !devices.contains(where: { $0.uid == live.uid }) {
            print("🔊 AudioController: Live audio device '\(live.name)' disconnected, switching to System Default")
            liveAudioDevice = audioManager.systemDefault
        }
    }
}
