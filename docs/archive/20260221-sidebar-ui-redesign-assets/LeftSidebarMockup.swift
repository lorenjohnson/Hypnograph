import SwiftUI

// MARK: - Left Sidebar Mockup (Settings)

/// Design mockup for left sidebar - Settings only.
/// Sources and Favorites are accessed via modals/dialogs, not sidebar tabs.
/// Uses Liquid Glass styling (iOS 18/macOS 15 design language).

struct LeftSidebarMockup: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Settings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            LiquidGlassDivider()

            SettingsSidebarContent()
        }
        .frame(width: 280)
        .liquidGlass(cornerRadius: 16)
    }
}

// MARK: - Settings Sidebar Content

struct SettingsSidebarContent: View {
    // Play Rate
    @State private var playRate: Double = 1.0

    // Clip Length (range slider)
    @State private var clipLengthRange: ClosedRange<Double> = 5...20
    @State private var maxLayers = 1
    @State private var watchMode = false
    @State private var sourceFraming = "Aspect Fill"
    @State private var aspectRatio = "16:9"

    // Transitions
    @State private var transitionStyle = "Crossfade"
    @State private var transitionDuration: Double = 1.0

    // Effects randomization
    @State private var randomizeGlobalEffect = true
    @State private var globalEffectFrequency: Double = 0.7  // 70% of the time
    @State private var randomizeLayerEffects = false
    @State private var layerEffectFrequency: Double = 0.3  // 30% of the time

    // Audio
    @State private var previewDevice = "Built-in Output"
    @State private var previewVolume: Double = 0.8
    @State private var liveDevice = "Built-in Output"
    @State private var liveVolume: Double = 1.0

    private let sourceFramingOptions = ["Aspect Fit", "Aspect Fill", "Stretch"]
    private let aspectRatioOptions = ["16:9", "4:3", "1:1", "9:16", "Source"]
    private let transitionStyles = ["Cut", "Crossfade", "Dissolve", "Wipe"]
    private let audioDevices = ["Built-in Output", "External DAC", "AirPods Pro"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: Watch Section
                Text("Watch")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // Watch toggle
                HStack {
                    Text("Watch")
                    Spacer()
                    Toggle("", isOn: $watchMode)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }

                // Play Rate
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Play Rate")
                        Spacer()
                        Text(String(format: "%.0f%%", playRate * 100))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $playRate, in: 0.2...2.0, step: 0.2)
                }

                // Transition Style
                HStack {
                    Text("Transition Style")
                    Spacer()
                    Picker("", selection: $transitionStyle) {
                        ForEach(transitionStyles, id: \.self) { style in
                            Text(style).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                // Transition Duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Transition Duration")
                        Spacer()
                        Text(String(format: "%.1fs", transitionDuration))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $transitionDuration, in: 0.1...3.0, step: 0.1)
                }

                // MARK: Display Section
                Text("Display")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // Source Framing
                HStack {
                    Text("Source Framing")
                    Spacer()
                    Picker("", selection: $sourceFraming) {
                        ForEach(sourceFramingOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                // Aspect Ratio
                HStack {
                    Text("Aspect Ratio")
                    Spacer()
                    Picker("", selection: $aspectRatio) {
                        ForEach(aspectRatioOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                // MARK: Audio Section
                Text("Audio")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // Preview Audio
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Preview")
                        Spacer()
                        Picker("", selection: $previewDevice) {
                            ForEach(audioDevices, id: \.self) { device in
                                Text(device).tag(device)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: previewVolume == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $previewVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                // Live Audio
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Live")
                        Spacer()
                        Picker("", selection: $liveDevice) {
                            ForEach(audioDevices, id: \.self) { device in
                                Text(device).tag(device)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: liveVolume == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $liveVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                LiquidGlassDivider()

                // MARK: Generation Section
                Text("Generation")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // Max Layers
                HStack {
                    Text("Max Layers")
                    Spacer()
                    Stepper("\(maxLayers)", value: $maxLayers, in: 1...20)
                        .fixedSize()
                }

                // Total Clip Length (range slider)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Clip Length")
                        Spacer()
                        Text("\(Int(clipLengthRange.lowerBound))–\(Int(clipLengthRange.upperBound))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    // Visual mockup of RangeSlider
                    // Real implementation: RangeSlider(range: $clipLengthRange, in: 1...60, distance: 2...55)
                    RangeSliderMockup(range: $clipLengthRange, bounds: 1...60, minDistance: 2)
                }

                // Global effect randomization
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Randomize Global Effect")
                        Spacer()
                        Toggle("", isOn: $randomizeGlobalEffect)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }

                    if randomizeGlobalEffect {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Frequency")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(globalEffectFrequency * 100))%")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $globalEffectFrequency, in: 0...1)
                        }
                        .padding(.leading, 20)
                    }
                }

                // Layer effects randomization
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Randomize Layer Effects")
                        Spacer()
                        Toggle("", isOn: $randomizeLayerEffects)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }

                    if randomizeLayerEffects {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Frequency")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(layerEffectFrequency * 100))%")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $layerEffectFrequency, in: 0...1)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Favorites Popover/Sheet Mockup
// TODO: This is a starting point for the Favorites modal UI - needs design work

struct FavoritesPopoverMockup: View {
    // Sample favorites with date/time as default name, optional custom name, and layer info
    @State private var favorites: [(id: UUID, name: String, date: Date, layers: Int)] = [
        (UUID(), "Jan 25, 4:31 PM", Date().addingTimeInterval(-3600), 3),
        (UUID(), "Jan 25, 2:15 PM", Date().addingTimeInterval(-7200), 2),
        (UUID(), "Vintage Look", Date().addingTimeInterval(-86400), 4),  // User renamed this one
        (UUID(), "Jan 24, 11:22 AM", Date().addingTimeInterval(-100000), 2)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($favorites, id: \.id) { $favorite in
                    FavoriteRowMockup(
                        name: $favorite.name,
                        layers: favorite.layers,
                        onLoad: {
                            // Load this favorite
                        },
                        onDelete: {
                            favorites.removeAll { $0.id == favorite.id }
                        }
                    )
                }
            }
            .padding(12)
        }
    }
}

struct FavoriteRowMockup: View {
    @Binding var name: String
    let layers: Int
    let onLoad: () -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail placeholder
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 60, height: 45)
                .overlay(
                    Image(systemName: "photo.stack")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                )

            // Name and info
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isNameFocused)
                        .onSubmit {
                            isEditing = false
                        }
                } else {
                    Text(name)
                        .font(.body)
                        .onTapGesture(count: 2) {
                            isEditing = true
                            isNameFocused = true
                        }
                }
                Text("\(layers) layers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Load button
            Button(action: onLoad) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.5))
        )
    }
}

// MARK: - Range Slider Mockup

/// Visual mockup of a double-thumb range slider.
/// For real implementation, use: https://github.com/spacenation/swiftui-sliders
/// RangeSlider(range: $range, in: bounds, distance: minDistance...maxDistance)
struct RangeSliderMockup: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    let minDistance: Double

    private var lowerPercent: Double {
        (range.lowerBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
    }

    private var upperPercent: Double {
        (range.upperBound - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbSize: CGFloat = 16
            let trackHeight: CGFloat = 4

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: trackHeight)

                // Highlighted track between thumbs
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: CGFloat(upperPercent - lowerPercent) * (width - thumbSize) + thumbSize,
                           height: trackHeight)
                    .offset(x: CGFloat(lowerPercent) * (width - thumbSize))

                // Lower thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(radius: 2)
                    .offset(x: CGFloat(lowerPercent) * (width - thumbSize))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newPercent = max(0, min(value.location.x / (width - thumbSize), 1))
                                let newValue = bounds.lowerBound + newPercent * (bounds.upperBound - bounds.lowerBound)
                                let maxLower = range.upperBound - minDistance
                                range = min(newValue, maxLower)...range.upperBound
                            }
                    )

                // Upper thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(radius: 2)
                    .offset(x: CGFloat(upperPercent) * (width - thumbSize))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newPercent = max(0, min(value.location.x / (width - thumbSize), 1))
                                let newValue = bounds.lowerBound + newPercent * (bounds.upperBound - bounds.lowerBound)
                                let minUpper = range.lowerBound + minDistance
                                range = range.lowerBound...max(newValue, minUpper)
                            }
                    )
            }
        }
        .frame(height: 20)
    }
}

// MARK: - Previews

#Preview("Settings Sidebar") {
    LeftSidebarMockup()
}

#Preview("Favorites Popover") {
    FavoritesPopoverMockup()
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
}
