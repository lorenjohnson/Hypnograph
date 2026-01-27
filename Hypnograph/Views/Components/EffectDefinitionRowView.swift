import SwiftUI
import HypnoCore

struct EffectDefinitionRowView: View {
    @ObservedObject var dream: Dream

    let layer: Int
    let effectIndex: Int
    let effect: EffectDefinition

    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    private var displayName: String {
        EffectRegistry.formatEffectTypeName(effect.type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if isExpanded {
                paramsEditor
                    .padding(.leading, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onToggleExpanded()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { effect.isEnabled },
                set: { enabled in
                    dream.activeEffectManager.setEffectEnabled(for: layer, effectDefIndex: effectIndex, enabled: enabled)
                }
            ))
            .toggleStyle(.darkModeCheckbox)
            .labelsHidden()

            Text(displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                dream.activeEffectManager.randomizeEffect(for: layer, effectDefIndex: effectIndex)
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Randomize")

            Button {
                dream.activeEffectManager.resetEffectToDefaults(for: layer, effectDefIndex: effectIndex)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reset")

            Button(role: .destructive) {
                dream.activeEffectManager.removeEffectFromChain(for: layer, effectDefIndex: effectIndex)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
    }

    private var paramsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            let specs = EffectRegistry.parameterSpecs(for: effect.type)
            let keys = EffectRegistry.parameterNames(for: effect.type).filter { $0 != "_enabled" }

            if keys.isEmpty {
                Text("No parameters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(keys, id: \.self) { key in
                    let spec = specs[key]
                    let value = effect.params?[key] ?? spec?.defaultValue ?? .double(0)
                    ParameterSliderRow(
                        name: key,
                        value: value,
                        effectType: effect.type,
                        spec: spec,
                        onChange: { newValue in
                            dream.activeEffectManager.updateEffectParameter(
                                for: layer,
                                effectDefIndex: effectIndex,
                                key: key,
                                value: newValue
                            )
                        }
                    )
                }
            }
        }
    }
}

