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
        VStack(alignment: .leading, spacing: 6) {
            header

            if isExpanded {
                paramsEditor
                    .padding(.leading, 16)
                    .opacity(effect.isEnabled ? 1.0 : 0.5)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
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
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(displayName)
                    .font(.callout)
                    .foregroundStyle(effect.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
            }

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

            Toggle("", isOn: Binding(
                get: { effect.isEnabled },
                set: { enabled in
                    main.activeEffectManager.setEffectEnabled(for: layer, effectDefIndex: effectIndex, enabled: enabled)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            Button(role: .destructive) {
                main.activeEffectManager.removeEffectFromChain(for: layer, effectDefIndex: effectIndex)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleExpanded()
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
                    EffectParameterRowView(
                        name: key,
                        value: value,
                        spec: spec,
                        onChange: { newValue in
                            main.activeEffectManager.updateEffectParameter(
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
