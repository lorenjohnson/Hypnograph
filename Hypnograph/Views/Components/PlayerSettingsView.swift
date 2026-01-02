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

// MARK: - Play Rate Control

/// Play rate slider with snap points at 50%, 80%, 100%, 200% and visual indicators
struct PlayRateControl: View {
    @Binding var playRate: Float

    /// Snap points for the slider (including min/max for visual indicators)
    private let snapPoints: [Float] = [0.25, 0.5, 0.8, 1.0, 1.5, 2.0]
    private let snapThreshold: Float = 0.03  // Snap when within 3%

    private let minValue: Float = 0.25
    private let maxValue: Float = 2.0

    /// Find next lower snap point
    private func previousSnapPoint() -> Float {
        for snap in snapPoints.reversed() {
            if snap < playRate - 0.01 {
                return snap
            }
        }
        return minValue
    }

    /// Find next higher snap point
    private func nextSnapPoint() -> Float {
        for snap in snapPoints {
            if snap > playRate + 0.01 {
                return snap
            }
        }
        return maxValue
    }

    /// Snap value if close to a snap point
    private func snappedValue(_ value: Float) -> Float {
        for snap in snapPoints {
            if abs(value - snap) < snapThreshold {
                return snap
            }
        }
        return value
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Play Rate:")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Text(String(format: "%.0f%%", playRate * 100))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
            }

            HStack(spacing: 8) {
                // Turtle button - go to previous snap point
                Button {
                    playRate = previousSnapPoint()
                } label: {
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                // Slider with snap point indicators behind
                Slider(
                    value: Binding(
                        get: { Double(playRate) },
                        set: { playRate = snappedValue(Float($0)) }
                    ),
                    in: Double(minValue)...Double(maxValue)
                )
                .controlSize(.small)
                .background(
                    GeometryReader { geometry in
                        // Account for slider thumb radius (the handle center can't go to the edge)
                        // For small controlSize, thumb is about 12px wide, so 6px from edge
                        let thumbRadius: CGFloat = 6
                        let trackWidth = geometry.size.width - (thumbRadius * 2)

                        // Snap point indicators (behind slider)
                        ForEach(snapPoints, id: \.self) { snap in
                            let normalizedPosition = CGFloat((snap - minValue) / (maxValue - minValue))
                            let position = thumbRadius + (normalizedPosition * trackWidth)
                            let isAt100 = snap == 1.0

                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 2, height: isAt100 ? 18 : 12)
                                .position(x: position, y: geometry.size.height / 2)
                        }
                    }
                )

                // Rabbit button - go to next snap point
                Button {
                    playRate = nextSnapPoint()
                } label: {
                    Image(systemName: "hare.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Row component for audio device selection with volume slider
struct AudioDeviceRow: View {
    let label: String
    @Binding var selectedDevice: AudioOutputDevice?
    @Binding var volume: Float
    @StateObject private var audioManager = AudioDeviceManager.shared

    /// Remember volume before muting so we can restore it
    @State private var volumeBeforeMute: Float = 1.0

    /// Muted when volume is 0
    private var isMuted: Bool { volume == 0 }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Picker("", selection: $selectedDevice) {
                    ForEach(audioManager.outputDevices) { device in
                        Text(device.name).tag(device as AudioOutputDevice?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }

            // Volume slider (always visible)
            HStack(spacing: 8) {
                // Mute button
                Button {
                    if isMuted {
                        // Unmute: restore previous volume
                        volume = volumeBeforeMute
                    } else {
                        // Mute: save current volume and set to 0
                        volumeBeforeMute = max(volume, 0.1) // Ensure we have something to restore
                        volume = 0
                    }
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isMuted ? .red : .white.opacity(0.6))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .frame(height: 24)

                Slider(value: $volume, in: 0...1)
                .controlSize(.small)

                // Max volume button
                Button {
                    volume = 1.0
                } label: {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .frame(height: 24)
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
            // Header row 1: Title and close button
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

            // Header row 2: Player mode switcher (full width)
            HStack(spacing: 6) {
                // Montage mode button
                playerModeButton(
                    icon: "square.grid.2x2",
                    label: "Montage",
                    isSelected: !dream.isLiveMode && dream.mode == .montage,
                    action: {
                        if dream.isLiveMode { dream.toggleLiveMode() }
                        if dream.mode != .montage { dream.toggleMode() }
                    }
                )

                // Sequence mode button
                playerModeButton(
                    icon: "arrow.right.square",
                    label: "Sequence",
                    isSelected: !dream.isLiveMode && dream.mode == .sequence,
                    action: {
                        if dream.isLiveMode { dream.toggleLiveMode() }
                        if dream.mode != .sequence { dream.toggleMode() }
                    }
                )

                // Live mode button
                playerModeButton(
                    icon: "play.display",
                    label: "Live",
                    isSelected: dream.isLiveMode,
                    action: {
                        if !dream.isLiveMode { dream.toggleLiveMode() }
                    }
                )
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

                Text("\(player.config.maxSourcesForNew)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 30)

                Stepper("", value: $player.config.maxSourcesForNew, in: 1...20)
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

                let seconds = Int(player.config.targetDuration.seconds)
                Text(formatDuration(seconds))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 50)

                Stepper("", value: Binding(
                    get: { Int(player.config.targetDuration.seconds) },
                    set: { player.config.targetDuration = CMTime(seconds: Double($0), preferredTimescale: 600) }
                ), in: 10...600, step: 10)
                .labelsHidden()
            }

            PlayRateControl(playRate: $player.playRate)

            HStack {
                Text("Aspect Ratio:")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Picker("", selection: $player.config.aspectRatio) {
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

            // Audio - Live
            AudioDeviceRow(
                label: "Live",
                selectedDevice: $dream.liveAudioDevice,
                volume: $dream.liveVolume
            )
        }
        .foregroundColor(.white)
        .padding(16)
        .frame(width: 320)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Helper to create a player mode button with icon and label
    @ViewBuilder
    private func playerModeButton(
        icon: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.blue.opacity(0.8) : Color.white.opacity(0.15))
        .cornerRadius(6)
    }
}
