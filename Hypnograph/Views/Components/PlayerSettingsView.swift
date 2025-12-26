//
//  PlayerSettingsView.swift
//  Hypnograph
//
//  Modal panel for per-player settings.
//  Appears at bottom-left corner, triggered by 'p' key.
//

import SwiftUI
import CoreMedia

/// Row component for audio device selection with volume slider
struct AudioDeviceRow: View {
    let label: String
    @Binding var selectedDevice: AudioOutputDevice?
    @Binding var volume: Float
    @StateObject private var audioManager = AudioDeviceManager.shared

    /// Use device ID for stable selection (AudioDeviceID is stable across refreshes)
    private var selectedDeviceID: Binding<AudioDeviceID> {
        Binding(
            get: { selectedDevice?.id ?? 0 },
            set: { newID in
                if newID == 0 {
                    selectedDevice = nil
                } else {
                    selectedDevice = audioManager.outputDevices.first { $0.id == newID }
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Picker("", selection: selectedDeviceID) {
                    Text("None").tag(AudioDeviceID(0))
                    ForEach(audioManager.outputDevices.filter { $0 != .none }) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            // Volume slider (only show when device is selected)
            if selectedDevice != nil {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 20)

                    Slider(value: Binding(
                        get: { Double(volume) },
                        set: { volume = Float($0) }
                    ), in: 0...1)
                    .controlSize(.small)

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.leading, 20)
            }
        }
    }
}

/// Modal panel for player-specific settings (generation, playback)
struct PlayerSettingsView: View {
    @ObservedObject var player: DreamPlayerState
    @ObservedObject var dream: Dream
    let onClose: () -> Void

    /// Format seconds as mm:ss
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Parse mm:ss or raw seconds into Int
    private func parseDuration(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2,
                  let mins = Int(parts[0]),
                  let secs = Int(parts[1]) else { return nil }
            return mins * 60 + secs
        } else {
            return Int(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Player Settings")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Max Sources
            HStack {
                Text("Max Sources:")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Text("\(player.maxSourcesForNew)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 30)

                Stepper("", value: $player.maxSourcesForNew, in: 1...20)
                    .labelsHidden()
            }

            // Target Duration
            HStack {
                Text("Duration:")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                let seconds = Int(player.targetDuration.seconds)
                Text(formatDuration(seconds))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 50)

                Stepper("", value: Binding(
                    get: { Int(player.targetDuration.seconds) },
                    set: { player.targetDuration = CMTime(seconds: Double($0), preferredTimescale: 600) }
                ), in: 10...600, step: 10)
                .labelsHidden()
            }

            // Play Rate
            HStack {
                Text("Play Rate:")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Text(String(format: "%.0f%%", player.playRate * 100))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 50)

                Slider(value: $player.playRate, in: 0.25...2.0, step: 0.05)
                    .frame(width: 100)
            }

            // Aspect Ratio picker
            HStack {
                Text("Aspect Ratio:")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Picker("", selection: $player.aspectRatio) {
                    ForEach(AspectRatio.menuPresets, id: \.displayString) { ratio in
                        Text(ratio.menuLabel).tag(ratio)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            // Audio section header
            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.vertical, 4)

            Text("Audio")
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(.white)

            // Audio - Preview
            AudioDeviceRow(
                label: "Preview",
                selectedDevice: $dream.previewAudioDevice,
                volume: $dream.previewVolume
            )

            // Audio - Performance
            AudioDeviceRow(
                label: "Performance",
                selectedDevice: $dream.performanceAudioDevice,
                volume: $dream.performanceVolume
            )
        }
        .foregroundColor(.white)
        .padding(16)
        .frame(width: 320)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

