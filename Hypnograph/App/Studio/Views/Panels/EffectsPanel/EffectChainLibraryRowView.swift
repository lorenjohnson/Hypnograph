import SwiftUI
import UniformTypeIdentifiers
import HypnoCore
import HypnoUI

struct EffectChainLibraryRowView: View {
    @ObservedObject var main: Studio
    @ObservedObject var session: EffectsSession

    let chainIndex: Int
    let chain: EffectChain

    let isExpanded: Bool
    @Binding var expandedEffectIndices: Set<Int>
    let onToggleExpanded: () -> Void

    let isRenaming: Bool
    @Binding var renameText: String
    let onInteractionOutsideRename: () -> Void
    let onRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @FocusState private var isNameFieldFocused: Bool

    private var displayName: String { chain.name ?? "Unnamed" }

    private var currentTargetLayer: Int {
        main.activePlayer.currentLayerIndex
    }

    private var currentTargetLabel: String {
        currentTargetLayer < 0 ? "Composition" : "Layer \(currentTargetLayer + 1)"
    }

    private func applyToCurrentSelection() {
        if isRenaming {
            onCommitRename()
        }
        main.activeEffectManager.applyTemplate(chain, to: currentTargetLayer)
        AppNotifications.show("Applied to \(currentTargetLabel)", flash: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            .contextMenu {
                Button(action: applyToCurrentSelection) {
                    Label("Apply to \(currentTargetLabel)", systemImage: "square.stack.3d.up")
                }

                Divider()

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }

                Button(action: onRename) {
                    Label("Rename...", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }

            if isExpanded {
                expandedContent
                .padding(.leading, 12)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Button(action: toggleExpandedFromChevron) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            rowMainTapArea

            actionButtons
        }
    }

    private var rowMainTapArea: some View {
        HStack(spacing: 6) {
            nameView

            Spacer()

            Text("\(chain.effects.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard !isRenaming else { return }
            applyToCurrentSelection()
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                onInteractionOutsideRename()
            }
        )
    }

    @ViewBuilder
    private var nameView: some View {
        if isRenaming {
            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .focused($isNameFieldFocused)
                .onSubmit(onCommitRename)
                .onExitCommand(perform: onCancelRename)
                .onAppear {
                    DispatchQueue.main.async {
                        isNameFieldFocused = true
                    }
                }
                .onChange(of: isNameFieldFocused) { _, focused in
                    if !focused, isRenaming {
                        onCommitRename()
                    }
                }
        } else {
            Text(displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .onLongPressGesture(minimumDuration: 0.4, perform: onRename)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            iconActionButton(
                systemImage: "plus.square.on.square",
                help: "Duplicate",
                action: duplicateChain
            )

            iconActionButton(
                systemImage: "trash",
                help: "Delete",
                role: .destructive,
                action: deleteChain
            )
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(chain.effects.enumerated()), id: \.offset) { index, effect in
                EffectRowView(
                    effect: effect,
                    isExpanded: expandedEffectIndices.contains(index),
                    onToggleExpanded: {
                        if expandedEffectIndices.contains(index) {
                            expandedEffectIndices.remove(index)
                        } else {
                            expandedEffectIndices.insert(index)
                        }
                    },
                    onSetEnabled: { enabled in
                        session.setEffectEnabled(chainIndex: chainIndex, effectIndex: index, enabled: enabled)
                    },
                    onRemove: {
                        session.removeEffectFromChain(chainIndex: chainIndex, effectIndex: index)
                    },
                    onUpdateParameter: { key, newValue in
                        session.updateParameter(chainIndex: chainIndex, effectIndex: index, key: key, value: newValue)
                    },
                    horizontalPadding: 8,
                    verticalPadding: 4,
                    parameterLeadingPadding: 16,
                    backgroundFill: Color.white.opacity(0.08)
                )
                .animation(.easeInOut(duration: 0.15), value: expandedEffectIndices)
            }

            Menu {
                ForEach(EffectRegistry.availableEffectTypes, id: \.type) { entry in
                    Button(entry.displayName) {
                        session.addEffectToChain(chainIndex: chainIndex, effectType: entry.type)
                    }
                }
            } label: {
                Label("Add Effect", systemImage: "plus")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func toggleExpandedFromChevron() {
        if isRenaming {
            onCommitRename()
        }
        onToggleExpanded()
    }

    private func duplicateChain() {
        if isRenaming {
            onCommitRename()
        }
        onDuplicate()
    }

    private func deleteChain() {
        if isRenaming {
            onCommitRename()
        }
        onDelete()
    }

    @ViewBuilder
    private func iconActionButton(
        systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(role == .destructive ? .red.opacity(isDisabled ? 0.35 : 0.8) : .secondary.opacity(isDisabled ? 0.35 : 0.9))
        .help(help)
        .disabled(isDisabled)
        .onTapGesture { }
    }
}
