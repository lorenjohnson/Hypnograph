//
//  PlayerSettingsView.swift
//  Hypnograph
//
//  Modal panel for per-player settings.
//  Appears at bottom-left corner, triggered by 'p' key.
//

import SwiftUI
import CoreMedia

/// Modal panel for player-specific settings (generation, playback)
struct PlayerSettingsView: View {
    @ObservedObject var player: DreamPlayerState
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

            // Effect Buffer Mode
            HStack {
                Text("Effect Buffer:")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Picker("", selection: $player.effectBufferMode) {
                    ForEach(EffectBufferMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }
        }
        .foregroundColor(.white)
        .padding(16)
        .frame(width: 320)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

