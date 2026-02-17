import SwiftUI
import HypnoCore

/// Parameter row styled to match Sidebar UI Redesign mockups (EffectDefinitionRowMockup).
struct EffectParameterRowView: View {
    let name: String
    let value: AnyCodableValue
    let spec: ParameterSpec?
    let onChange: (AnyCodableValue) -> Void

    @State private var didRefreshFileList = false
    @State private var fileListRefreshNonce = UUID()
    @State private var sliderValue: Double = 0
    @State private var lastExternalNumericValue: Double = 0

    private var label: String {
        // Mockup fidelity: LUT selection should read "LUT" (not "Lut File").
        if name == "lutFile" { return "LUT" }
        return Self.formatCamelCase(name)
    }

    var body: some View {
        switch value {
        case .bool(let b):
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { b },
                    set: { onChange(.bool($0)) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

        case .string(let s):
            if spec?.isFile == true, let spec {
                filePicker(currentValue: s, spec: spec)
            } else if let options = spec?.choiceOptions {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { s },
                        set: { onChange(.string($0)) }
                    )) {
                        ForEach(options, id: \.key) { option in
                            Text(option.label).tag(option.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160, alignment: .trailing)
                }
            } else {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(s)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

        case .double(let d):
            numericRow(value: d, isInt: shouldUseIntegerSlider)

        case .int(let i):
            numericRow(value: Double(i), isInt: shouldUseIntegerSlider)
        }
    }

    /// Use parameter spec as source of truth for integer-vs-continuous numeric controls.
    /// This avoids float params getting stuck on integer steps when persisted as `.int(0)`.
    private var shouldUseIntegerSlider: Bool {
        guard let spec else {
            if case .int = value { return true }
            return false
        }
        if case .int = spec { return true }
        return false
    }

    @ViewBuilder
    private func numericRow(value: Double, isInt: Bool) -> some View {
        let range = spec?.rangeAsDoubles ?? (0...1).asTuple
        let minValue = range.min
        let maxValue = range.max
        let sliderRange = minValue...maxValue

        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(
                value: $sliderValue,
                in: sliderRange
            )
            .onAppear {
                syncSliderFromExternal(value: value, in: sliderRange)
            }
            .onChange(of: value) { _, newValue in
                syncSliderFromExternal(value: newValue, in: sliderRange)
            }
            .onChange(of: sliderValue) { _, newValue in
                let clampedValue = newValue.clamped(to: sliderRange)
                if isInt || spec?.step == 1 {
                    let intValue = Int(clampedValue.rounded())
                    let numericValue = Double(intValue)
                    guard abs(numericValue - lastExternalNumericValue) > 0.0001 else { return }
                    onChange(.int(intValue))
                } else {
                    guard abs(clampedValue - lastExternalNumericValue) > 0.0001 else { return }
                    onChange(.double(clampedValue))
                }
            }

            Text(trailingValueText(value: sliderValue, min: minValue, max: maxValue))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func syncSliderFromExternal(value: Double, in range: ClosedRange<Double>) {
        let clamped = value.clamped(to: range)
        lastExternalNumericValue = clamped

        guard abs(sliderValue - clamped) > 0.0001 else { return }
        sliderValue = clamped
    }

    private func trailingValueText(value: Double, min: Double, max: Double) -> String {
        // Mockups show % for common 0-1 parameters.
        if min >= 0, max <= 1.0 {
            return "\(Int((value.clamped(to: 0...1)) * 100))%"
        }

        if (max - min) <= 10 {
            return String(format: "%.2f", value)
        }
        return "\(Int(value.rounded()))"
    }

    @ViewBuilder
    private func filePicker(currentValue: String, spec: ParameterSpec) -> some View {
        let _ = fileListRefreshNonce
        let files = spec.availableFiles

        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            if files.isEmpty {
                Text("No LUTs found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("", selection: Binding(
                    get: { currentValue },
                    set: { onChange(.string($0)) }
                )) {
                    Text("Select LUT…").tag("")
                    ForEach(files, id: \.key) { file in
                        Text(file.label).tag(file.key)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160, alignment: .trailing)
            }
        }
        .onAppear {
            guard !didRefreshFileList else { return }
            ParameterSpec.clearFileListCache()
            didRefreshFileList = true
            fileListRefreshNonce = UUID()
        }
    }

    private static func formatCamelCase(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var result = ""
        for (index, char) in input.enumerated() {
            if char.isUppercase && index > 0 { result += " " }
            result += index == 0 ? String(char).uppercased() : String(char)
        }
        return result
    }
}

private extension ClosedRange where Bound == Double {
    var asTuple: (min: Double, max: Double) { (lowerBound, upperBound) }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
