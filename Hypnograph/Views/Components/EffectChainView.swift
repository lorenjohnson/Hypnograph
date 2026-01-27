import SwiftUI
import HypnoCore
import HypnoUI

struct EffectChainView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream

    /// -1 = global, 0+ = layer index
    let layer: Int
    let title: String
    var isCollapsible: Bool = true

    @State private var isExpanded: Bool = true
    @State private var expandedEffectIndices: Set<Int> = []

    private var chain: EffectChain {
        dream.activeEffectManager.effectChain(for: layer) ?? EffectChain()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if isExpanded, !chain.effects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(chain.effects.enumerated()), id: \.offset) { index, effect in
                        EffectDefinitionRowView(
                            dream: dream,
                            layer: layer,
                            effectIndex: index,
                            effect: effect,
                            isExpanded: expandedEffectIndices.contains(index),
                            onToggleExpanded: {
                                toggleEffectExpanded(index)
                            }
                        )
                        .animation(.easeInOut(duration: 0.15), value: expandedEffectIndices)
                    }

                    Menu {
                        ForEach(EffectRegistry.availableEffectTypes, id: \.type) { entry in
                            Button(entry.displayName) {
                                dream.activeEffectManager.addEffectToChain(for: layer, effectType: entry.type)
                            }
                        }
                    } label: {
                        Label("Add Effect", systemImage: "plus")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
    }

    private var headerRow: some View {
        let hasChain = !chain.effects.isEmpty
        let displayName = chain.name ?? (hasChain ? "Custom" : "No Effect")

        return HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(displayName)
                .font(.callout.weight(hasChain ? .medium : .regular))
                .foregroundStyle(hasChain ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            if hasChain {
                Toggle("", isOn: Binding(
                    get: { chain.effects.contains(where: { $0.isEnabled }) },
                    set: { enabled in
                        for idx in chain.effects.indices {
                            dream.activeEffectManager.setEffectEnabled(for: layer, effectDefIndex: idx, enabled: enabled)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .onTapGesture { }
            } else {
                Menu {
                    ForEach(EffectRegistry.availableEffectTypes, id: \.type) { entry in
                        Button(entry.displayName) {
                            dream.activeEffectManager.addEffectToChain(for: layer, effectType: entry.type)
                            isExpanded = true
                        }
                    }
                } label: {
                    Text("Add...")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .onTapGesture { }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isCollapsible else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            Button {
                let current = chain
                _ = dream.effectsLibrarySession.addTemplate(from: current, name: current.name)
                AppNotifications.show("Saved to library", flash: true)
            } label: {
                Label("Save as New Template...", systemImage: "square.and.arrow.down")
            }

            Button {
                AppNotifications.show("Use Effect Chains tab to load templates", flash: true, duration: 1.25)
            } label: {
                Label("Load from Library...", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive) {
                dream.activeEffectManager.clearEffect(for: layer)
                expandedEffectIndices.removeAll()
            } label: {
                Label("Clear Effect", systemImage: "trash")
            }
        }
    }

    private func toggleEffectExpanded(_ index: Int) {
        if expandedEffectIndices.contains(index) {
            expandedEffectIndices.remove(index)
        } else {
            expandedEffectIndices.insert(index)
        }
    }
}
