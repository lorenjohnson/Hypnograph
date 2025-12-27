//
//  PlayerSettingsView.swift
//  Hypnograph
//
//  Modal panel for per-player settings.
//  Appears at bottom-left corner, triggered by 'p' key.
//

import SwiftUI
import CoreMedia

// MARK: - Dark Mode Toggle Styles

/// Custom switch style that shows better on dark backgrounds when disabled
/// Provides a visible background capsule for the switch track
struct DarkModeSwitchStyle: ToggleStyle {
    @SwiftUI.Environment(\.isEnabled) private var isEnabled

    /// Whether to use compact sizing (for inline use in lists)
    var compact: Bool = false

    private var trackWidth: CGFloat { compact ? 32 : 44 }
    private var trackHeight: CGFloat { compact ? 18 : 24 }
    private var thumbSize: CGFloat { compact ? 14 : 20 }
    private var thumbOffset: CGFloat { compact ? 7 : 10 }

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            if !compact {
                Spacer()
            }

            // Custom switch appearance
            ZStack {
                // Track background - visible even when disabled
                Capsule()
                    .fill(configuration.isOn
                        ? Color.blue.opacity(isEnabled ? 1.0 : 0.4)
                        : Color.white.opacity(isEnabled ? 0.3 : 0.15))
                    .frame(width: trackWidth, height: trackHeight)

                // Thumb
                Circle()
                    .fill(Color.white.opacity(isEnabled ? 1.0 : 0.6))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .offset(x: configuration.isOn ? thumbOffset : -thumbOffset)
            }
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            .onTapGesture {
                if isEnabled {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

/// Custom checkbox style that shows better on dark backgrounds
/// Provides a visible border and background for the checkbox
struct DarkModeCheckboxStyle: ToggleStyle {
    @SwiftUI.Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            // Custom checkbox appearance
            ZStack {
                // Background box
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn
                        ? Color.blue.opacity(isEnabled ? 1.0 : 0.4)
                        : Color.white.opacity(isEnabled ? 0.15 : 0.08))
                    .frame(width: 16, height: 16)

                // Border
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.white.opacity(isEnabled ? 0.5 : 0.25), lineWidth: 1)
                    .frame(width: 16, height: 16)

                // Checkmark
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(isEnabled ? 1.0 : 0.6))
                }
            }
            .onTapGesture {
                if isEnabled {
                    configuration.isOn.toggle()
                }
            }

            configuration.label
        }
    }
}

extension ToggleStyle where Self == DarkModeSwitchStyle {
    /// A switch style optimized for dark backgrounds with visible disabled states
    static var darkModeSwitch: DarkModeSwitchStyle { DarkModeSwitchStyle() }

    /// A compact switch style for inline use in lists
    static var darkModeSwitchCompact: DarkModeSwitchStyle { DarkModeSwitchStyle(compact: true) }

    /// Alias for darkModeSwitch
    static var darkMode: DarkModeSwitchStyle { DarkModeSwitchStyle() }
}

extension ToggleStyle where Self == DarkModeCheckboxStyle {
    /// A checkbox style optimized for dark backgrounds with visible disabled states
    static var darkModeCheckbox: DarkModeCheckboxStyle { DarkModeCheckboxStyle() }
}

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

            HStack {
                Text("Watch Mode:")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { dream.state.settings.watch },
                    set: { _ in dream.state.toggleWatchMode() }
                ))
                .toggleStyle(.darkMode)
            }

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

            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.vertical, 4)

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
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}



