//
//  ParameterSliderRow.swift
//  Hypnograph
//
//  Reusable slider row for editing effect parameters.
//  Supports numeric (int/double), boolean, string, color, choice, and file picker parameters.
//

import SwiftUI
import AppKit
import HypnoCore

/// A row displaying a parameter name and appropriate editor control
struct ParameterSliderRow: View {
    let name: String
    let value: AnyCodableValue
    let effectType: String?
    let spec: ParameterSpec?
    let onChange: (AnyCodableValue) -> Void

    @State private var textValue: String = ""
    @State private var sliderValue: Double = 0
    /// Track last known external value to detect actual user changes vs. re-render
    @State private var lastExternalValue: Double = 0
    @FocusState private var isTextFieldFocused: Bool

    /// Convert camelCase to readable title: "maxHistoryOffset" -> "Max History Offset"
    private var displayName: String {
        Self.formatCamelCase(name)
    }

    /// Convert camelCase string to "Title Case With Spaces"
    static func formatCamelCase(_ input: String) -> String {
        guard !input.isEmpty else { return input }

        var result = ""
        for (index, char) in input.enumerated() {
            if char.isUppercase && index > 0 {
                result += " "
            }
            result += index == 0 ? String(char).uppercased() : String(char)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label row with reset button right-aligned
            HStack {
                Text(displayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button(action: resetToDefault) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.borderless)
                .help("Reset to default")
            }

            HStack(spacing: 8) {
                switch value {
                case .double:
                    numericSlider(isInt: false)
                    compactTextField(onSubmit: {
                        if let d = Double(textValue) {
                            sliderValue = d
                            onChange(.double(d))
                        }
                    })

                case .int:
                    // Check if this should really be treated as a double (has decimal range in registry)
                    let treatAsDouble = shouldTreatIntAsDouble
                    numericSlider(isInt: !treatAsDouble)
                    compactTextField(onSubmit: {
                        if treatAsDouble, let d = Double(textValue) {
                            sliderValue = d
                            onChange(.double(d))
                        } else if let i = Int(textValue) {
                            sliderValue = Double(i)
                            onChange(.int(i))
                        }
                    })

                case .bool(let b):
                    Toggle("", isOn: Binding(
                        get: { b },
                        set: { onChange(.bool($0)) }
                    ))
                    .toggleStyle(.darkModeCheckbox)
                    .labelsHidden()

                case .string(let s):
                    // Check if this is a color parameter
                    if spec?.isColor == true {
                        colorPicker(currentHex: s)
                    } else if let options = spec?.choiceOptions {
                        // Check if this is a choice parameter
                        choicePicker(currentValue: s, options: options)
                    } else if spec?.isFile == true {
                        // File picker parameter
                        filePicker(currentValue: s, spec: spec!)
                    } else {
                        // Use textValue @State to buffer input and prevent focus loss
                        // textValue is initialized from s in onAppear/onChange
                        TextField("", text: $textValue)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(isTextFieldFocused ? Color.white : Color.white.opacity(0.1))
                            .foregroundColor(isTextFieldFocused ? .black : .white)
                            .cornerRadius(3)
                            .focused($isTextFieldFocused)
                            .onChange(of: textValue) { _, newValue in
                                // Update the model when text changes
                                onChange(.string(newValue))
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .focusable()  // Makes this row participate in Tab navigation
        .onAppear {
            initializeValues()
        }
        .onChange(of: value) { _, newValue in
            // Re-initialize when value changes externally
            initializeFromValue(newValue)
        }
    }

    private func initializeValues() {
        initializeFromValue(value)
    }

    private func initializeFromValue(_ val: AnyCodableValue) {
        switch val {
        case .double(let d):
            // Set lastExternalValue BEFORE sliderValue to prevent spurious onChange triggers
            lastExternalValue = d
            sliderValue = d
            textValue = String(format: "%.2f", d)
        case .int(let i):
            // Set lastExternalValue BEFORE sliderValue to prevent spurious onChange triggers
            lastExternalValue = Double(i)
            sliderValue = Double(i)
            textValue = "\(i)"
        case .string(let s):
            // Only initialize if not currently focused (preserve typing)
            if !isTextFieldFocused {
                textValue = s
            }
        default:
            break
        }
    }

    /// Get the default value for this parameter from the registry
    private var defaultValue: AnyCodableValue? {
        if let type = effectType {
            return EffectRegistry.defaults(for: type)[name]
        }
        return spec?.defaultValue
    }

    /// Reset the parameter to its default value
    private func resetToDefault() {
        guard let defaultVal = defaultValue else { return }
        switch defaultVal {
        case .double(let d):
            sliderValue = d
            lastExternalValue = d
            textValue = String(format: "%.2f", d)
            onChange(.double(d))
        case .int(let i):
            sliderValue = Double(i)
            lastExternalValue = Double(i)
            textValue = "\(i)"
            onChange(.int(i))
        case .bool(let b):
            onChange(.bool(b))
        case .string(let s):
            onChange(.string(s))
        }
    }

    /// Creates a slider without the step parameter to avoid slow tick mark layout
    /// Step values are enforced programmatically in onChange instead
    @ViewBuilder
    private func numericSlider(isInt: Bool) -> some View {
        let range = sliderRange
        let step = safeSliderStep(isInt: isInt, range: range)

        // NOTE: Do NOT use Slider(step:) - it causes AppKit to create tick marks
        // which triggers extremely slow layout calculations (1+ seconds per slider).
        // Instead, we snap values to step in the onChange handler.
        Slider(value: $sliderValue, in: range)
            .frame(minWidth: 100)
            .onChange(of: sliderValue) { _, newVal in
                // Snap to step if we have one
                let snappedVal: Double
                if let step = step, step > 0 {
                    snappedVal = (newVal / step).rounded() * step
                } else {
                    snappedVal = newVal
                }

                // Only trigger onChange if value actually changed from external value
                guard abs(snappedVal - lastExternalValue) > 0.0001 else { return }

                if isInt {
                    textValue = "\(Int(snappedVal))"
                    onChange(.int(Int(snappedVal)))
                } else {
                    textValue = String(format: "%.2f", snappedVal)
                    onChange(.double(snappedVal))
                }
            }
    }

    /// Compact text field - shows white background only when focused
    @ViewBuilder
    private func compactTextField(onSubmit: @escaping () -> Void) -> some View {
        TextField("", text: $textValue)
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .frame(width: 50)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isTextFieldFocused ? Color.white : Color.white.opacity(0.1))
            .foregroundColor(isTextFieldFocused ? .black : .white)
            .cornerRadius(3)
            .focused($isTextFieldFocused)
            .onSubmit(onSubmit)
    }

    /// Choice picker for enum-style parameters
    @ViewBuilder
    private func choicePicker(currentValue: String, options: [(key: String, label: String)]) -> some View {
        Picker("", selection: Binding(
            get: { currentValue },
            set: { onChange(.string($0)) }
        )) {
            ForEach(options, id: \.key) { option in
                Text(option.label).tag(option.key)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Color picker for hex color parameters
    @ViewBuilder
    private func colorPicker(currentHex: String) -> some View {
        let nsColor = NSColor.fromHex(currentHex) ?? .white
        let swiftUIColor = Color(nsColor: nsColor)

        ColorPicker("", selection: Binding(
            get: { swiftUIColor },
            set: { newColor in
                // Convert SwiftUI Color back to hex
                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                    let r = Int(components.redComponent * 255)
                    let g = Int(components.greenComponent * 255)
                    let b = Int(components.blueComponent * 255)
                    let hex = String(format: "#%02X%02X%02X", r, g, b)
                    onChange(.string(hex))
                }
            }
        ))
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// File picker for file-based parameters (e.g., LUT files)
    @ViewBuilder
    private func filePicker(currentValue: String, spec: ParameterSpec) -> some View {
        let files = spec.availableFiles

        if files.isEmpty {
            // No files found - show placeholder with directory info
            HStack {
                Text("No files found")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                if let info = spec.filePickerInfo {
                    Button(action: {
                        NSWorkspace.shared.open(info.directory)
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Open \(info.directory.lastPathComponent) folder")

                    Button(action: {
                        ParameterSpec.clearFileListCache()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh file list")
                }
            }
        } else {
            HStack(spacing: 4) {
                Picker("", selection: Binding(
                    get: { currentValue },
                    set: { onChange(.string($0)) }
                )) {
                    Text("Select file...").tag("")
                    ForEach(files, id: \.key) { file in
                        Text(file.label).tag(file.key)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                // Refresh button to rescan for new files
                Button(action: {
                    ParameterSpec.clearFileListCache()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Refresh file list")
            }
        }
    }

    /// Safe slider step - returns nil if step would be invalid
    private func safeSliderStep(isInt: Bool, range: ClosedRange<Double>) -> Double? {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return nil }

        // For ints, default to step of 1
        if isInt {
            let step = sliderStep ?? 1
            // Ensure step is positive and less than or equal to span
            if step > 0 && step <= span {
                return step
            }
            // Fall back: if span >= 1, use 1, otherwise no step
            return span >= 1 ? 1 : nil
        }

        // For doubles, use registry step if valid
        guard let step = sliderStep, step > 0, step < span else {
            return nil
        }
        return step
    }

    /// Slider range - from registry if available, else heuristic
    /// Always returns a valid range where min < max
    private var sliderRange: ClosedRange<Double> {
        // Prefer explicit schema range when provided
        if let range = spec?.rangeAsDoubles, range.min < range.max {
            return range.min...range.max
        }

        // Try to get range from registry
        if let type = effectType, let range = EffectRegistry.range(for: type, param: name) {
            // Ensure valid range (min < max)
            if range.min < range.max {
                return range.min...range.max
            }
        }

        // Fallback: use value heuristics
        let initialValue: Double
        switch value {
        case .double(let d): initialValue = d
        case .int(let i): initialValue = Double(i)
        default: return 0...100
        }

        if initialValue == 0 {
            return 0...100
        } else if initialValue < 0 {
            return (initialValue * 2)...abs(initialValue * 2)
        } else if initialValue <= 1 {
            return 0...2
        } else if initialValue <= 10 {
            return 0...20
        } else if initialValue <= 100 {
            return 0...(initialValue * 3)
        } else {
            return 0...(initialValue * 3)
        }
    }

    /// Slider step - from registry if available, must be positive and less than range
    private var sliderStep: Double? {
        if let step = spec?.step, step > 0 {
            let span = sliderRange.upperBound - sliderRange.lowerBound
            return step < span ? step : nil
        }

        guard let type = effectType,
              let range = EffectRegistry.range(for: type, param: name),
              let step = range.step,
              step > 0 else {
            return nil
        }
        // Ensure step is less than range span
        let span = sliderRange.upperBound - sliderRange.lowerBound
        guard step < span else { return nil }
        return step
    }

    /// Check if an int value should be treated as a double based on registry range
    /// (e.g., contrast: 1 should be treated as 1.0 with decimal range 0.5-2.0)
    private var shouldTreatIntAsDouble: Bool {
        guard let type = effectType,
              let range = EffectRegistry.range(for: type, param: name) else {
            return false
        }
        // If registry has non-integer bounds, treat as double
        return range.min != floor(range.min) || range.max != floor(range.max) || range.step == nil
    }
}
