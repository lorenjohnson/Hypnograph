import SwiftUI
import HypnoCore

struct EffectDefinitionRowView: View {
    @ObservedObject var main: Studio

    let layer: Int
    let effectIndex: Int
    let effect: EffectDefinition

    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    private var displayName: String {
        EffectRegistry.formatEffectTypeName(effect.type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if isExpanded {
                paramsEditor
                    .padding(.leading, 12)
                    .opacity(effect.isEnabled ? 1.0 : 0.5)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .contextMenu {
            Button("Reset to Defaults") {
                resetEffectToDefaults()
            }

            Button("Randomize Parameters") {
                randomizeEffectParameters()
            }
        }
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

            Button {
                resetEffectToDefaults()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Reset effect to defaults")

            Button {
                randomizeEffectParameters()
            } label: {
                Image(systemName: "dice")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Randomize effect parameters")

            PanelToggleView(isOn: Binding(
                get: { effect.isEnabled },
                set: { enabled in
                    main.activeEffectManager.setEffectEnabled(for: layer, effectDefIndex: effectIndex, enabled: enabled)
                }
            ))
            .fixedSize()

            Button(role: .destructive) {
                main.activeEffectManager.removeEffectFromChain(for: layer, effectDefIndex: effectIndex)
            } label: {
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
                            main.activeEffectManager.updateEffectParameter(
                                for: layer,
                                effectDefIndex: effectIndex,
                                key: row.key,
                                value: newValue
                            )
                        }
                    )
                }
            }
        }
    }

    private func resetEffectToDefaults() {
        let specs = EffectRegistry.parameterSpecs(for: effect.type)
        for (key, spec) in specs {
            guard key != "_enabled" else { continue }
            main.activeEffectManager.updateEffectParameter(
                for: layer,
                effectDefIndex: effectIndex,
                key: key,
                value: spec.defaultValue
            )
        }
    }

    private func randomizeEffectParameters() {
        let specs = EffectRegistry.parameterSpecs(for: effect.type)
        for (key, spec) in specs {
            guard key != "_enabled", key.lowercased() != "opacity" else { continue }
            main.activeEffectManager.updateEffectParameter(
                for: layer,
                effectDefIndex: effectIndex,
                key: key,
                value: spec.randomValue()
            )
        }
    }
}
