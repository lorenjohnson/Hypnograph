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

    @State private var chainNameDraft: String = ""
    @FocusState private var isNameFocused: Bool

    private var chain: EffectChain {
        dream.activeEffectManager.effectChain(for: layer) ?? EffectChain()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCollapsible {
                DisclosureGroup(isExpanded: $isExpanded) {
                    content
                        .padding(.top, 6)
                } label: {
                    header
                }
            } else {
                header
                content
            }
        }
        .onAppear {
            if chainNameDraft.isEmpty {
                chainNameDraft = chain.name ?? ""
            }
        }
        .onChange(of: chain.name) { _, newName in
            guard !isNameFocused else { return }
            chainNameDraft = newName ?? ""
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(chainSummary(chain))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            chainNameRow
            addEffectRow

            if chain.effects.isEmpty {
                Text("No effects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
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
                        .animation(.easeInOut(duration: 0.18), value: expandedEffectIndices)
                    }
                }
            }
        }
    }

    private var chainNameRow: some View {
        HStack(spacing: 8) {
            Text("Name")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

            TextField("Optional", text: $chainNameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isNameFocused ? Color.white : Color.white.opacity(0.08))
                .foregroundColor(isNameFocused ? .black : .white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .focused($isNameFocused)
                .onSubmit {
                    dream.activeEffectManager.updateChainName(for: layer, name: chainNameDraft)
                }
                .onChange(of: isNameFocused) { _, focused in
                    if !focused, chainNameDraft != (chain.name ?? "") {
                        dream.activeEffectManager.updateChainName(for: layer, name: chainNameDraft)
                    }
                }

            Button(role: .destructive) {
                dream.activeEffectManager.clearEffect(for: layer)
                expandedEffectIndices.removeAll()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear chain")
            .disabled(chain.effects.isEmpty && (chain.name?.isEmpty ?? true))

            Menu {
                Button("Save as New Template") {
                    _ = dream.effectsLibrarySession.addTemplate(from: chain, name: chain.name)
                    AppNotifications.show("Saved to library", flash: true)
                }

                if let templateId = chain.sourceTemplateId {
                    Button("Update Linked Template") {
                        dream.effectsLibrarySession.updateTemplate(id: templateId, from: chain, preserveName: true)
                        AppNotifications.show("Updated library template", flash: true)
                    }
                }
            } label: {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .help("Library")
            .disabled(chain.effects.isEmpty)

            Button("Edit") {
                state.windowState.set("effectsEditor", visible: true)
                if layer == -1 {
                    dream.activePlayer.selectGlobalLayer()
                } else {
                    dream.activePlayer.selectSource(layer)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var addEffectRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(EffectRegistry.availableEffectTypes, id: \.type) { entry in
                    Button(entry.displayName) {
                        dream.activeEffectManager.addEffectToChain(for: layer, effectType: entry.type)
                    }
                }
            } label: {
                Label("Add Effect", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)

            Spacer()

            Button {
                expandedEffectIndices = Set(0..<chain.effects.count)
            } label: {
                Text("Expand All")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
            .disabled(chain.effects.isEmpty)

            Button {
                expandedEffectIndices.removeAll()
            } label: {
                Text("Collapse")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
            .disabled(expandedEffectIndices.isEmpty)
        }
    }

    private func toggleEffectExpanded(_ index: Int) {
        if expandedEffectIndices.contains(index) {
            expandedEffectIndices.remove(index)
        } else {
            expandedEffectIndices.insert(index)
        }
    }

    private func chainSummary(_ chain: EffectChain) -> String {
        let enabledCount = chain.effects.filter { $0.isEnabled }.count
        if chain.effects.isEmpty { return "None" }
        if enabledCount == chain.effects.count {
            return "\(enabledCount)"
        }
        return "\(enabledCount)/\(chain.effects.count)"
    }
}
