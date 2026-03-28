import SwiftUI
import HypnoCore
import HypnoUI

struct EffectChainView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    /// -1 = global, 0+ = layer index
    let layer: Int
    let title: String
    var isCollapsible: Bool = true

    @State private var isExpanded: Bool = true
    @State private var expandedEffectIndices: Set<Int> = []
    @State private var draggingEffectIndex: Int?

    private var chain: EffectChain {
        main.activeEffectManager.effectChain(for: layer) ?? EffectChain()
    }

    private var availableLibraryChains: [EffectChain] {
        main.effectsLibrarySession.chains
            .filter { !$0.effects.isEmpty }
            .sorted { lhs, rhs in
                templateDisplayName(lhs).localizedCaseInsensitiveCompare(templateDisplayName(rhs)) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if isExpanded, !chain.effects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(chain.effects.enumerated()), id: \.offset) { index, effect in
                        EffectDefinitionRowView(
                            main: main,
                            layer: layer,
                            effectIndex: index,
                            effect: effect,
                            isExpanded: expandedEffectIndices.contains(index),
                            onToggleExpanded: {
                                toggleEffectExpanded(index)
                            }
                        )
                        .opacity(draggingEffectIndex == index ? 0.5 : 1.0)
                        .onDrag {
                            draggingEffectIndex = index
                            return NSItemProvider(object: String(index) as NSString)
                        }
                        .onDrop(of: [.text], delegate: EffectDropDelegate(
                            currentIndex: index,
                            draggingIndex: $draggingEffectIndex,
                            onReorder: { from, to in
                                main.activeEffectManager.reorderEffectsInChain(
                                    for: layer,
                                    fromIndex: from,
                                    toIndex: to
                                )
                            }
                        ))
                        .animation(.easeInOut(duration: 0.15), value: expandedEffectIndices)
                    }

                    Menu {
                        addEffectMenuContent
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
                            main.activeEffectManager.setEffectEnabled(for: layer, effectDefIndex: idx, enabled: enabled)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .onTapGesture { }
            } else {
                Menu {
                    addEffectMenuContent
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
                _ = main.effectsLibrarySession.addTemplate(from: current, name: current.name)
                AppNotifications.show("Saved to library", flash: true)
            } label: {
                Label("Save to Library", systemImage: "square.and.arrow.down")
            }

            Button {
                let current = chain
                let baseName = templateDisplayName(current)
                let uniqueName = uniqueTemplateName(from: baseName)
                _ = main.effectsLibrarySession.addTemplate(from: current, name: uniqueName)
                AppNotifications.show("Saved as \(uniqueName)", flash: true)
            } label: {
                Label("Save as New Template...", systemImage: "square.and.arrow.down")
            }

            Button {
                randomizeChainParameters()
                AppNotifications.show("Randomized chain parameters", flash: true, duration: 1.1)
            } label: {
                Label("Randomize Parameters", systemImage: "dice")
            }
            .disabled(!hasChain)

            Divider()

            Button(role: .destructive) {
                main.activeEffectManager.clearEffect(for: layer)
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

    @ViewBuilder
    private var addEffectMenuContent: some View {
        if !availableLibraryChains.isEmpty {
            Section("Effect Chains") {
                ForEach(availableLibraryChains, id: \.id) { libraryChain in
                    Button(templateDisplayName(libraryChain)) {
                        main.activeEffectManager.applyTemplate(libraryChain, to: layer)
                        isExpanded = true
                    }
                }
            }
        }

        Section("FX") {
            ForEach(EffectRegistry.availableEffectTypes, id: \.type) { entry in
                Button(entry.displayName) {
                    main.activeEffectManager.addEffectToChain(for: layer, effectType: entry.type)
                    isExpanded = true
                }
            }
        }
    }

    private func templateDisplayName(_ chain: EffectChain) -> String {
        let trimmed = chain.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return chain.effects.isEmpty ? "Untitled" : "Custom"
    }

    private func uniqueTemplateName(from baseName: String) -> String {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackBase = trimmedBase.isEmpty ? "Untitled" : trimmedBase
        let existing = Set(
            main.effectsLibrarySession.chains.compactMap { chain in
                let name = chain.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty ? nil : name
            }
        )

        guard existing.contains(fallbackBase) else { return fallbackBase }

        var suffix = 1
        while existing.contains("\(fallbackBase) (\(suffix))") {
            suffix += 1
        }
        return "\(fallbackBase) (\(suffix))"
    }

    private func randomizeChainParameters() {
        let effects = chain.effects
        guard !effects.isEmpty else { return }

        for (effectIndex, effectDef) in effects.enumerated() {
            let specs = EffectRegistry.parameterSpecs(for: effectDef.type)
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
}
