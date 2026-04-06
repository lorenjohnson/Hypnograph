import SwiftUI
import HypnoCore

struct EffectRowView: View {
    let effect: EffectDefinition

    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onSetEnabled: (Bool) -> Void
    let onRemove: () -> Void
    let onUpdateParameter: (String, AnyCodableValue) -> Void
    var onResetDefaults: (() -> Void)? = nil
    var onRandomizeParameters: (() -> Void)? = nil
    var horizontalPadding: CGFloat = 7
    var verticalPadding: CGFloat = 3
    var parameterLeadingPadding: CGFloat = 12
    var backgroundFill: Color = Color.white.opacity(0.07)

    private var displayName: String {
        EffectRegistry.formatEffectTypeName(effect.type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if isExpanded {
                paramsEditor
                    .opacity(effect.isEnabled ? 1.0 : 0.5)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundFill)
        )
        .modifier(EffectDefinitionRowContextMenu(
            onResetDefaults: onResetDefaults,
            onRandomizeParameters: onRandomizeParameters
        ))
    }

    private var header: some View {
        HStack {
            Button(action: onToggleExpanded) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(displayName)
                        .font(.callout)
                        .foregroundStyle(effect.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if let onResetDefaults {
                Button(action: onResetDefaults) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Reset effect to defaults")
            }

            if let onRandomizeParameters {
                Button(action: onRandomizeParameters) {
                    Image(systemName: "dice")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Randomize effect parameters")
            }

            PanelToggleView(isOn: Binding(
                get: { effect.isEnabled },
                set: onSetEnabled
            ))
            .fixedSize()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
    }

    private var paramsEditor: some View {
        let specs = EffectRegistry.parameterSpecs(for: effect.type)
        let parameterRows = EffectRegistry.parameterNames(for: effect.type)
            .filter { $0 != "_enabled" }
            .map { key in
                (
                    key: key,
                    spec: specs[key],
                    value: effect.params?[key] ?? specs[key]?.defaultValue ?? .double(0)
                )
            }

        return VStack(alignment: .leading, spacing: 5) {
            if parameterRows.isEmpty {
                Text("No parameters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(parameterRows, id: \.key) { row in
                    EffectParameterRowView(
                        name: row.key,
                        value: row.value,
                        effectType: effect.type,
                        spec: row.spec,
                        onChange: { newValue in
                            onUpdateParameter(row.key, newValue)
                        }
                    )
                }
            }
        }
        .padding(.leading, parameterLeadingPadding)
    }
}

private struct EffectDefinitionRowContextMenu: ViewModifier {
    let onResetDefaults: (() -> Void)?
    let onRandomizeParameters: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if onResetDefaults != nil || onRandomizeParameters != nil {
            content.contextMenu {
                if let onResetDefaults {
                    Button("Reset to Defaults", action: onResetDefaults)
                }

                if let onRandomizeParameters {
                    Button("Randomize Parameters", action: onRandomizeParameters)
                }
            }
        } else {
            content
        }
    }
}
