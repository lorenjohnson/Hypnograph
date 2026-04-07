import SwiftUI

// MARK: - Right Sidebar Mockup

/// Design mockup for right sidebar with Layers and Effect Chains tabs.
/// Uses Liquid Glass styling (iOS 18/macOS 15 design language).

struct RightSidebarMockup: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Composition").tag(0)
                Text("Effect Chains").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            LiquidGlassDivider()

            // Tab content
            switch selectedTab {
            case 0:
                LayersTabMockup()
            case 1:
                EffectsTabMockup()
            default:
                EmptyView()
            }
        }
        .frame(width: 300)
        .liquidGlass(cornerRadius: 16)
    }
}

// MARK: - Layers Tab

struct LayersTabMockup: View {
    @State private var globalExpanded = true
    @State private var showingAddMenu = false
    @State private var clipLength: Double = 15.0

    // Layer selection state - nil means Global is selected, index means that layer
    @State private var selectedLayerIndex: Int? = nil

    // Layer data with full effect chain model
    @State private var layers: [LayerDataMockup] = [
        LayerDataMockup(
            title: "beach_sunset.mp4",
            subtitle: "Aug 15, 2024 · Malibu, CA",
            blendMode: "Normal",
            opacity: 1.0,
            effectChain: EffectChainMockup(
                name: "Dreamy Glow",
                effects: [
                    EffectDefinitionMockup(type: "BloomEffect", params: [
                        "intensity": .double(0.6),
                        "radius": .double(0.4)
                    ]),
                    EffectDefinitionMockup(type: "GaussianBlurEffect", params: [
                        "radius": .double(0.2)
                    ])
                ]
            )
        ),
        LayerDataMockup(
            title: "IMG_4823.mov",
            subtitle: "Dec 3, 2023 · Berlin",
            blendMode: "Overlay",
            opacity: 0.7,
            effectChain: EffectChainMockup(
                name: "Custom",
                effects: [
                    EffectDefinitionMockup(type: "ColorInvertEffect", params: [
                        "intensity": .double(1.0)
                    ])
                ]
            )
        ),
        LayerDataMockup(
            title: "city_lights.mp4",
            subtitle: "Jan 20, 2024",
            blendMode: "Screen",
            opacity: 0.5,
            effectChain: nil
        )
    ]

    // Global effect chain
    @State private var compositionEffectChain = EffectChainMockup(
        name: "Vintage Look",
        effects: [
            EffectDefinitionMockup(type: "ChromaticAberrationEffect", params: [
                "offset": .double(0.3),
                "angle": .double(0.0)
            ]),
            EffectDefinitionMockup(type: "BloomEffect", params: [
                "intensity": .double(0.5),
                "radius": .double(0.3)
            ])
        ]
    )

    /// Selection label for UI feedback (layers only, Global is always accessible)
    private var selectedLayerLabel: String? {
        guard let index = selectedLayerIndex else { return nil }
        return layers[index].title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // MARK: Global Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Global")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    // Clip Length
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Clip Length")
                                .font(.callout)
                            Spacer()
                            Text("\(Int(clipLength))s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $clipLength, in: 1...60, step: 1)
                    }
                    .padding(.horizontal, 4)

                    CompositionEffectChainRowMockup(
                        chain: $compositionEffectChain,
                        isExpanded: $globalExpanded
                    )
                }

                LiquidGlassDivider()
                    .padding(.vertical, 4)

                // MARK: Layers Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Layers")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Button {
                                // Select source
                            } label: {
                                Label("Select Source...", systemImage: "photo.on.rectangle")
                            }
                            Button {
                                // Random source
                            } label: {
                                Label("Random Source", systemImage: "dice")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.medium))
                        }
                        .menuStyle(.borderlessButton)
                    }
                    .padding(.horizontal, 4)

                    // Layer rows
                    ForEach(Array(layers.enumerated()), id: \.element.id) { index, _ in
                        LayerRowMockup(
                            layer: $layers[index],
                            isSelected: selectedLayerIndex == index,
                            onSelect: { selectedLayerIndex = index }
                        )
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Layer Data Model

/// Data model for a layer in the Layers tab
struct LayerDataMockup: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var blendMode: String
    var opacity: Double
    var isExpanded: Bool = false
    var effectChainExpanded: Bool = false
    var isVisible: Bool = true
    var isSolo: Bool = false
    var effectChain: EffectChainMockup?
}

struct LayerRowMockup: View {
    @Binding var layer: LayerDataMockup
    let isSelected: Bool
    let onSelect: () -> Void

    private let blendModes = ["Normal", "Overlay", "Screen", "Multiply", "Soft Light", "Hard Light"]

    /// Subtitle with blend mode appended (unless Normal)
    private var subtitleWithBlend: String {
        if layer.blendMode == "Normal" {
            return layer.subtitle
        } else {
            return "\(layer.subtitle) · \(layer.blendMode)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                // Thumbnail placeholder
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 56, height: 42)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    )

                // Title and subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(subtitleWithBlend)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Solo button
                Button {
                    layer.isSolo.toggle()
                } label: {
                    Text("S")
                        .font(.caption.weight(.bold))
                        .frame(width: 20, height: 20)
                        .background(layer.isSolo ? Color.yellow : Color.clear)
                        .foregroundStyle(layer.isSolo ? .black : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                // Visibility button
                Button {
                    layer.isVisible.toggle()
                } label: {
                    Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                        .font(.caption)
                        .foregroundStyle(layer.isVisible ? .primary : .tertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelected {
                    // Already selected - toggle expand/collapse
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layer.isExpanded.toggle()
                    }
                } else {
                    // Not selected - just select (don't toggle expand)
                    onSelect()
                }
            }
            .contextMenu {
                Button {
                    // Reveal in Finder / Photos
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Divider()
                Button(role: .destructive) {
                    // Delete layer
                } label: {
                    Label("Delete Layer", systemImage: "trash")
                }
            }

            // Expanded content
            if layer.isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Blend Mode
                        HStack {
                            Text("Blend")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $layer.blendMode) {
                                ForEach(blendModes, id: \.self) { mode in
                                    Text(mode).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                        }

                        // Opacity
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Opacity")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(layer.opacity * 100))%")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $layer.opacity, in: 0...1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                    Divider()
                        .padding(.horizontal, 8)

                    // Effect Chain section with full parameter editing
                    EffectChainSectionMockup(
                        chain: Binding(
                            get: { layer.effectChain },
                            set: { layer.effectChain = $0 }
                        ),
                        isExpanded: $layer.effectChainExpanded
                    )
                    .padding(8)
                }
            }
        }
        .background(
            Group {
                if isSelected {
                    // Liquid Glass selected card style
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.1), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                } else {
                    // Liquid Glass card style
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.05))
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.08), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.6)
                        : .white.opacity(0.1),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.15) : .clear,
            radius: 4, y: 2
        )
    }
}

// MARK: - Reusable Effect Chain Section

/// Reusable effect chain component used in both Global section and within Layers.
/// Shows chain name (or "No Effect"), expandable list of effects with full parameter editing.
struct EffectChainSectionMockup: View {
    @Binding var chain: EffectChainMockup?
    @Binding var isExpanded: Bool
    @State private var isEnabled: Bool = true

    // Sample available effect types for the Add Effect menu
    private let availableEffectTypes = [
        "BloomEffect", "BlurEffect", "ChromaticAberrationEffect", "ColorInvertEffect",
        "GaussianBlurEffect", "HueShiftEffect", "NoiseEffect", "PixellateEffect",
        "RippleEffect", "SepiaEffect", "TwirlEffect", "VignetteEffect"
    ]

    /// Display name for the chain
    private var displayName: String {
        chain?.name ?? "No Effect"
    }

    /// Whether there's an actual chain with effects
    private var hasChain: Bool {
        chain != nil && !(chain?.effects.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row - clickable anywhere except toggle and menu
            HStack(spacing: 8) {
                // Chevron + chain name
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(displayName)
                    .font(.callout.weight(hasChain ? .medium : .regular))
                    .foregroundStyle(hasChain ? .primary : .secondary)

                Spacer()

                if hasChain {
                    // Enable/disable toggle
                    Toggle("", isOn: $isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .onTapGesture { } // Absorb tap
                } else {
                    // No effect - show Add button
                    Menu {
                        ForEach(availableEffectTypes, id: \.self) { effectType in
                            Button(formatEffectType(effectType)) {
                                if chain == nil {
                                    chain = EffectChainMockup(name: "Custom", effects: [])
                                }
                                chain?.effects.append(EffectDefinitionMockup(
                                    type: effectType,
                                    params: ["intensity": .double(0.5)]
                                ))
                            }
                        }
                    } label: {
                        Text("Add...")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .contextMenu {
                Button {
                    // Save to library
                } label: {
                    Label("Save to Library", systemImage: "square.and.arrow.down")
                }
                Button {
                    // Load from library
                } label: {
                    Label("Load from Library...", systemImage: "folder")
                }
                Divider()
                Button(role: .destructive) {
                    chain = nil
                } label: {
                    Label("Clear Effect", systemImage: "trash")
                }
            }

            // Expanded: list of effects with full parameter editing
            if isExpanded, let binding = Binding($chain) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(binding.effects) { $effect in
                        EffectDefinitionRowMockup(
                            effect: $effect,
                            onRemove: {
                                chain?.effects.removeAll { $0.id == effect.id }
                            }
                        )
                    }

                    // Add effect button
                    Menu {
                        ForEach(availableEffectTypes, id: \.self) { effectType in
                            Button(formatEffectType(effectType)) {
                                chain?.effects.append(EffectDefinitionMockup(
                                    type: effectType,
                                    params: ["intensity": .double(0.5)]
                                ))
                            }
                        }
                    } label: {
                        Label("Add Effect", systemImage: "plus")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.leading, 16)
                .padding(.top, 4)
                .opacity(isEnabled ? 1.0 : 0.5)
            }
        }
    }

    /// Format effect type for display: "BloomEffect" -> "Bloom"
    private func formatEffectType(_ type: String) -> String {
        type.replacingOccurrences(of: "Effect", with: "")
    }
}

// MARK: - Global Effect Chain Row

/// Wrapper for Global section that adds the card background.
/// Global doesn't have selection state - it's always accessible.
struct CompositionEffectChainRowMockup: View {
    @Binding var chain: EffectChainMockup
    @Binding var isExpanded: Bool

    var body: some View {
        EffectChainSectionMockup(
            chain: Binding(
                get: { chain },
                set: { if let newChain = $0 { chain = newChain } }
            ),
            isExpanded: $isExpanded
        )
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Effects Tab (Library)

/// Effects Library tab showing saved effect chains.
/// Each entry displays like the Global/Layer effect chains with add/remove capability.
struct EffectsTabMockup: View {
    // Sample library of saved effect chains (mirrors EffectChain structure)
    @State private var libraryChains: [EffectChainMockup] = [
        EffectChainMockup(
            name: "Vintage Look",
            effects: [
                EffectDefinitionMockup(type: "ChromaticAberrationEffect", params: [
                    "offset": .double(0.3),
                    "angle": .double(0.0)
                ]),
                EffectDefinitionMockup(type: "BloomEffect", params: [
                    "intensity": .double(0.5),
                    "radius": .double(0.3)
                ]),
                EffectDefinitionMockup(type: "SepiaEffect", params: [
                    "intensity": .double(0.4)
                ])
            ]
        ),
        EffectChainMockup(
            name: "Dreamy Glow",
            effects: [
                EffectDefinitionMockup(type: "BloomEffect", params: [
                    "intensity": .double(0.6),
                    "radius": .double(0.5)
                ]),
                EffectDefinitionMockup(type: "GaussianBlurEffect", params: [
                    "radius": .double(0.2)
                ])
            ]
        ),
        EffectChainMockup(
            name: "Cyberpunk",
            effects: [
                EffectDefinitionMockup(type: "ChromaticAberrationEffect", params: [
                    "offset": .double(0.7),
                    "angle": .double(0.25)
                ]),
                EffectDefinitionMockup(type: "ColorInvertEffect", params: [
                    "intensity": .double(0.3)
                ]),
                EffectDefinitionMockup(type: "PixellateEffect", params: [
                    "scale": .double(0.1)
                ])
            ]
        ),
        EffectChainMockup(
            name: "Film Grain",
            effects: [
                EffectDefinitionMockup(type: "NoiseEffect", params: [
                    "amount": .double(0.4),
                    "size": .double(0.5)
                ]),
                EffectDefinitionMockup(type: "VignetteEffect", params: [
                    "intensity": .double(0.5),
                    "radius": .double(0.3)
                ])
            ]
        ),
        EffectChainMockup(
            name: "Underwater",
            effects: [
                EffectDefinitionMockup(type: "RippleEffect", params: [
                    "amplitude": .double(0.3),
                    "frequency": .double(0.5)
                ]),
                EffectDefinitionMockup(type: "HueShiftEffect", params: [
                    "shift": .double(0.2)
                ]),
                EffectDefinitionMockup(type: "BlurEffect", params: [
                    "radius": .double(0.15)
                ])
            ]
        ),
        // Example with LUT dropdown picker
        EffectChainMockup(
            name: "Cinematic Grade",
            effects: [
                EffectDefinitionMockup(type: "LUTEffect", params: [
                    "lutName": .string("Teal & Orange"),
                    "intensity": .double(0.8)
                ]),
                EffectDefinitionMockup(type: "VignetteEffect", params: [
                    "intensity": .double(0.4),
                    "radius": .double(0.5)
                ])
            ]
        ),
        // Example with toggle checkboxes
        EffectChainMockup(
            name: "Datamosh Chaos",
            effects: [
                EffectDefinitionMockup(type: "DatamoshEffect", params: [
                    "intensity": .double(0.6),
                    "preserveKeyframes": .bool(true),
                    "randomSeed": .bool(false)
                ]),
                EffectDefinitionMockup(type: "GlitchBlocksEffect", params: [
                    "blockSize": .double(0.3),
                    "intensity": .double(0.5),
                    "colorShift": .bool(true),
                    "horizontal": .bool(false)
                ])
            ]
        )
    ]

    // Sample available effect types for the Add Effect menu
    private let availableEffectTypes = [
        "BloomEffect", "BlurEffect", "ChromaticAberrationEffect", "ColorInvertEffect",
        "GaussianBlurEffect", "HueShiftEffect", "NoiseEffect", "PixellateEffect",
        "RippleEffect", "SepiaEffect", "TwirlEffect", "VignetteEffect"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Library section header
                Text("Library")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach($libraryChains) { $chain in
                    EffectChainLibraryRowMockup(
                        chain: $chain,
                        availableEffectTypes: availableEffectTypes
                    )
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Library Models
// These mirror the real models in HypnoCore/Renderer/Effects/Core/EffectConfigSchema.swift

/// Mockup of EffectChain - a named container for 0-n effects
struct EffectChainMockup: Identifiable {
    let id = UUID()
    var sourceTemplateId: UUID?  // Links back to library template if originated from one
    var name: String?
    var effects: [EffectDefinitionMockup]
    var params: [String: AnyCodableValueMockup]?  // Chain-level params (future)
}

/// Mockup of EffectDefinition - a single effect with type + params
struct EffectDefinitionMockup: Identifiable {
    let id = UUID()
    var name: String?  // Optional display name
    var type: String   // e.g., "BloomEffect", "ChromaticAberrationEffect"
    var params: [String: AnyCodableValueMockup]?

    /// Whether this effect is enabled (checks _enabled param, defaults to true)
    var isEnabled: Bool {
        params?["_enabled"]?.boolValue ?? true
    }
}

/// Mockup of AnyCodableValue - type-erased codable value for mixed parameter types
enum AnyCodableValueMockup {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}

/// Parameter metadata for mockup - defines how a param should be rendered
/// In real app, this comes from EffectRegistry.parameterSpecs
struct ParameterSpecMockup {
    enum ParamType {
        case slider(min: Double, max: Double)
        case toggle
        case picker(options: [String])
    }
    let type: ParamType
    let label: String
}

/// Sample parameter specs for mockup effects
/// Maps effectType -> paramName -> spec
let mockupParameterSpecs: [String: [String: ParameterSpecMockup]] = [
    "LUTEffect": [
        "lutName": ParameterSpecMockup(type: .picker(options: ["Cinematic", "Vintage Film", "Bleach Bypass", "Cross Process", "Teal & Orange"]), label: "LUT"),
        "intensity": ParameterSpecMockup(type: .slider(min: 0, max: 1), label: "Intensity")
    ],
    "DatamoshEffect": [
        "intensity": ParameterSpecMockup(type: .slider(min: 0, max: 1), label: "Intensity"),
        "preserveKeyframes": ParameterSpecMockup(type: .toggle, label: "Preserve Keyframes"),
        "randomSeed": ParameterSpecMockup(type: .toggle, label: "Random Seed")
    ],
    "GlitchBlocksEffect": [
        "blockSize": ParameterSpecMockup(type: .slider(min: 0, max: 1), label: "Block Size"),
        "intensity": ParameterSpecMockup(type: .slider(min: 0, max: 1), label: "Intensity"),
        "colorShift": ParameterSpecMockup(type: .toggle, label: "Color Shift"),
        "horizontal": ParameterSpecMockup(type: .toggle, label: "Horizontal")
    ],
    "BloomEffect": [
        "intensity": ParameterSpecMockup(type: .slider(min: 0, max: 1), label: "Intensity"),
        "radius": ParameterSpecMockup(type: .slider(min: 0, max: 1), label: "Radius")
    ],
    "ChromaticAberrationEffect": [
        "offset": ParameterSpecMockup(type: .slider(min: 0, max: 1), label: "Offset"),
        "angle": ParameterSpecMockup(type: .slider(min: 0, max: 1), label: "Angle")
    ]
]

// MARK: - Library Row

/// Library row showing a saved effect chain (same visual style as Global/Layer chains)
/// Supports adding and removing effects when expanded.
struct EffectChainLibraryRowMockup: View {
    @Binding var chain: EffectChainMockup
    let availableEffectTypes: [String]
    @State private var isExpanded: Bool = false

    /// Display name for the chain (falls back to "Unnamed" if nil)
    private var displayName: String {
        chain.name ?? "Unnamed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                // Chevron + chain name
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(displayName)
                    .font(.callout.weight(.medium))

                Spacer()

                // Effect count badge
                Text("\(chain.effects.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.quaternary)
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .contextMenu {
                Button {
                    // Apply to Global
                } label: {
                    Label("Apply to Global", systemImage: "globe")
                }
                Button {
                    // Apply to selected layer
                } label: {
                    Label("Apply to Selected Layer", systemImage: "square.stack.3d.up")
                }
                Divider()
                Button {
                    // Duplicate
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    // Rename
                } label: {
                    Label("Rename...", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    // Delete from library
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            // Expanded: show effects in chain with add/remove
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach($chain.effects) { $effect in
                        EffectDefinitionRowMockup(
                            effect: $effect,
                            onRemove: {
                                chain.effects.removeAll { $0.id == effect.id }
                            }
                        )
                    }

                    // Add Effect button
                    Menu {
                        ForEach(availableEffectTypes, id: \.self) { effectType in
                            Button(formatEffectType(effectType)) {
                                chain.effects.append(EffectDefinitionMockup(
                                    type: effectType,
                                    params: ["intensity": .double(0.5)]
                                ))
                            }
                        }
                    } label: {
                        Label("Add Effect", systemImage: "plus")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    /// Format effect type for display: "BloomEffect" -> "Bloom"
    private func formatEffectType(_ type: String) -> String {
        type.replacingOccurrences(of: "Effect", with: "")
    }
}

/// Individual effect row within a library chain, expandable to show parameters
struct EffectDefinitionRowMockup: View {
    @Binding var effect: EffectDefinitionMockup
    let onRemove: () -> Void

    @State private var isExpanded: Bool = false

    /// Format effect type for display: "BloomEffect" -> "Bloom"
    private var displayType: String {
        effect.type.replacingOccurrences(of: "Effect", with: "")
    }

    /// Sorted parameter keys (excluding internal params like _enabled)
    private var paramKeys: [String] {
        (effect.params ?? [:])
            .keys
            .filter { !$0.hasPrefix("_") }
            .sorted()
    }

    /// Get parameter spec for this effect type (if available)
    private func spec(for key: String) -> ParameterSpecMockup? {
        mockupParameterSpecs[effect.type]?[key]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack {
                // Expand for parameters
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(displayType)
                            .font(.callout)
                            .foregroundStyle(effect.isEnabled ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { effect.isEnabled },
                    set: { newValue in
                        if effect.params == nil { effect.params = [:] }
                        effect.params?["_enabled"] = .bool(newValue)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }

            // Expanded: show parameters
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(paramKeys, id: \.self) { key in
                        parameterRow(for: key)
                    }
                }
                .padding(.leading, 16)
                .opacity(effect.isEnabled ? 1.0 : 0.5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
        )
    }

    /// Render appropriate control based on parameter type
    @ViewBuilder
    private func parameterRow(for key: String) -> some View {
        let paramSpec = spec(for: key)
        let label = paramSpec?.label ?? key

        if let spec = paramSpec {
            switch spec.type {
            // Picker/dropdown for string options
            case .picker(let options):
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { effect.params?[key]?.stringValue ?? options.first ?? "" },
                        set: { effect.params?[key] = .string($0) }
                    )) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

            // Toggle/checkbox for booleans
            case .toggle:
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { effect.params?[key]?.boolValue ?? false },
                        set: { effect.params?[key] = .bool($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }

            // Slider for numeric values
            case .slider(let min, let max):
                sliderRow(key: key, label: label, min: min, max: max)
            }
        } else {
            // Fallback: render based on value type
            if let value = effect.params?[key] {
                switch value {
                case .bool(let boolVal):
                    HStack {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { boolVal },
                            set: { effect.params?[key] = .bool($0) }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                case .string(let strVal):
                    HStack {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(strVal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .double, .int:
                    sliderRow(key: key, label: label, min: 0, max: 1)
                }
            }
        }
    }

    /// Slider row for numeric parameters
    @ViewBuilder
    private func sliderRow(key: String, label: String, min: Double, max: Double) -> some View {
        if let value = effect.params?[key]?.doubleValue {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { value },
                        set: { effect.params?[key] = .double($0) }
                    ),
                    in: min...max
                )
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    RightSidebarMockup()
}
