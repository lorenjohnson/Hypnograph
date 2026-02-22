import SwiftUI

// MARK: - Liquid Glass Style

/// Apple's Liquid Glass design language (iOS 18/macOS 15)
/// Adds depth, edge highlights, and subtle gradients to glass surfaces.

extension View {
    /// Apply Liquid Glass styling to a container view.
    /// Use for sidebars, cards, and floating panels.
    func liquidGlass(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial)
            .background(
                // Gradient overlay for light refraction effect
                LinearGradient(
                    colors: [.white.opacity(0.12), .white.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            .overlay(
                // Edge highlight - bright line at top/left edges
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.1), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }

    /// Apply Liquid Glass styling to inner card elements (less prominent).
    /// Use for layer rows, effect chain sections, etc.
    func liquidGlassCard(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
            .background(
                // Subtle inner gradient
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.08), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
    }

    /// Apply Liquid Glass styling to selected/active card elements.
    /// Use for selected layers, active states.
    func liquidGlassCardSelected(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.1), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
            )
            .shadow(color: Color.accentColor.opacity(0.2), radius: 4, y: 2)
    }
}

// MARK: - Liquid Glass Divider

/// A subtle gradient divider for Liquid Glass UIs
struct LiquidGlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

// MARK: - Component Mockups

/// Individual control experiments for testing different SwiftUI native controls.
/// Use these to compare control styles and find what works best.

// MARK: - Slider Variations

struct SliderVariationsMockup: View {
    @State private var value1: Double = 0.5
    @State private var value2: Double = 0.7
    @State private var value3: Double = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Slider Styles")
                .font(.title2.weight(.semibold))

            // Standard slider with label
            VStack(alignment: .leading, spacing: 4) {
                Text("Standard with value label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Intensity")
                    Slider(value: $value1)
                    Text("\(Int(value1 * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            // Slider with step marks
            VStack(alignment: .leading, spacing: 4) {
                Text("With step values (0.25 increments)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Rate")
                    Slider(value: $value2, in: 0...2, step: 0.25)
                    Text(String(format: "%.2fx", value2))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }

            // Compact slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Compact (smaller control size)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Opacity")
                        .font(.callout)
                    Slider(value: $value3)
                        .controlSize(.small)
                    Text("\(Int(value3 * 100))%")
                        .font(.callout)
                        .monospacedDigit()
                }
            }
        }
        .padding(20)
        .frame(width: 350)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Toggle Variations

struct ToggleVariationsMockup: View {
    @State private var toggle1 = true
    @State private var toggle2 = false
    @State private var toggle3 = true
    @State private var toggle4 = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Toggle Styles")
                .font(.title2.weight(.semibold))

            // Standard toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("Standard switch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Auto-advance", isOn: $toggle1)
            }

            // Checkbox style
            VStack(alignment: .leading, spacing: 4) {
                Text("Checkbox style")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Include images", isOn: $toggle2)
                    .toggleStyle(.checkbox)
            }

            // Small switch
            VStack(alignment: .leading, spacing: 4) {
                Text("Small control size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Shuffle", isOn: $toggle3)
                    .controlSize(.small)
            }

            // Button style toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("Button style (pressed = on)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Loop", isOn: $toggle4)
                    .toggleStyle(.button)
            }
        }
        .padding(20)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Picker Variations

struct PickerVariationsMockup: View {
    @State private var selection1 = "Normal"
    @State private var selection2 = 0
    @State private var selection3 = "Color"

    private let blendModes = ["Normal", "Overlay", "Screen", "Multiply", "Soft Light"]
    private let categories = ["All", "Color", "Distortion", "Blur", "Stylize"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Picker Styles")
                .font(.title2.weight(.semibold))

            // Menu picker (dropdown)
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu style (dropdown)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Blend Mode")
                    Spacer()
                    Picker("", selection: $selection1) {
                        ForEach(blendModes, id: \.self) { mode in
                            Text(mode).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            // Segmented picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Segmented (tabs)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Mode", selection: $selection2) {
                    Text("Preview").tag(0)
                    Text("Live").tag(1)
                }
                .pickerStyle(.segmented)
            }

            // Inline picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Inline (radio buttons)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Category", selection: $selection3) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.inline)
                .frame(height: 120)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Stepper Variations

struct StepperVariationsMockup: View {
    @State private var value1 = 3
    @State private var value2 = 5
    @State private var value3: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Stepper Styles")
                .font(.title2.weight(.semibold))

            // Standard stepper
            VStack(alignment: .leading, spacing: 4) {
                Text("Standard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Max Layers: \(value1)", value: $value1, in: 1...9)
            }

            // Compact stepper
            VStack(alignment: .leading, spacing: 4) {
                Text("Small control size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Count: \(value2)", value: $value2, in: 1...20)
                    .controlSize(.small)
            }

            // Decimal stepper
            VStack(alignment: .leading, spacing: 4) {
                Text("With decimal step")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(
                    "Duration: \(String(format: "%.1f", value3))s",
                    value: $value3,
                    in: 0.5...10.0,
                    step: 0.5
                )
            }
        }
        .padding(20)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Button Variations

struct ButtonVariationsMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Button Styles")
                .font(.title2.weight(.semibold))

            // Standard buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Standard styles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Default") { }
                    Button("Bordered") { }
                        .buttonStyle(.bordered)
                    Button("Borderless") { }
                        .buttonStyle(.borderless)
                }
            }

            // Prominent button
            VStack(alignment: .leading, spacing: 8) {
                Text("Prominent (colored)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply Effect") { }
                    .buttonStyle(.borderedProminent)
            }

            // Control sizes
            VStack(alignment: .leading, spacing: 8) {
                Text("Control sizes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Mini") { }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    Button("Small") { }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Regular") { }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }

            // Icon buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon buttons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button { } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.bordered)

                    Button { } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button { } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Text Field Variations

struct TextFieldVariationsMockup: View {
    @State private var text1 = ""
    @State private var text2 = "Saved Preset"
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Text Field Styles")
                .font(.title2.weight(.semibold))

            // Standard text field
            VStack(alignment: .leading, spacing: 4) {
                Text("Standard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Enter name...", text: $text1)
                    .textFieldStyle(.roundedBorder)
            }

            // Plain text field
            VStack(alignment: .leading, spacing: 4) {
                Text("Plain (no border)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Preset name", text: $text2)
                    .textFieldStyle(.plain)
            }

            // Search field style
            VStack(alignment: .leading, spacing: 4) {
                Text("Search field pattern")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search effects...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                )
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Material Backgrounds

struct MaterialBackgroundsMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Material Backgrounds")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)

            HStack(spacing: 12) {
                MaterialSample(name: "Ultra Thin", material: .ultraThinMaterial)
                MaterialSample(name: "Thin", material: .thinMaterial)
                MaterialSample(name: "Regular", material: .regularMaterial)
                MaterialSample(name: "Thick", material: .thickMaterial)
            }
        }
        .padding(20)
    }
}

struct MaterialSample<M: ShapeStyle>: View {
    let name: String
    let material: M

    var body: some View {
        VStack {
            Text(name)
                .font(.caption)
        }
        .frame(width: 80, height: 60)
        .background(material)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - All Components Gallery

struct ComponentsGalleryMockup: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SliderVariationsMockup()
                ToggleVariationsMockup()
                PickerVariationsMockup()
                StepperVariationsMockup()
                ButtonVariationsMockup()
                TextFieldVariationsMockup()
            }
            .padding(20)
        }
    }
}

// MARK: - Preview

#Preview {
    ComponentsGalleryMockup()
}
