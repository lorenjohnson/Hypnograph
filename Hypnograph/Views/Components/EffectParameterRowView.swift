import SwiftUI
import HypnoCore

/// Parameter row styled to match Sidebar UI Redesign mockups (EffectDefinitionRowMockup).
struct EffectParameterRowView: View {
    let name: String
    let value: AnyCodableValue
    let spec: ParameterSpec?
    let onChange: (AnyCodableValue) -> Void

    private var label: String { Self.formatCamelCase(name) }

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
            if let options = spec?.choiceOptions {
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
            numericRow(value: d, isInt: false)

        case .int(let i):
            numericRow(value: Double(i), isInt: true)
        }
    }

    @ViewBuilder
    private func numericRow(value: Double, isInt: Bool) -> some View {
        let range = spec?.rangeAsDoubles ?? (0...1).asTuple
        let minValue = range.min
        let maxValue = range.max

        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { value.clamped(to: minValue...maxValue) },
                    set: { newValue in
                        if isInt || spec?.step == 1 {
                            onChange(.int(Int(newValue.rounded())))
                        } else {
                            onChange(.double(newValue))
                        }
                    }
                ),
                in: minValue...maxValue
            )

            Text(trailingValueText(value: value, min: minValue, max: maxValue))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
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

