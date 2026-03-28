import SwiftUI
import HypnoCore

struct EffectChainLibraryRowView: View {
    let chain: EffectChain
    let isSelected: Bool

    let onSelect: () -> Void
    let onApplyToGlobal: () -> Void
    let onApplyToSelectedLayer: (() -> Void)?
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(chain.name?.isEmpty == false ? (chain.name ?? "") : "Untitled")
                    .lineLimit(1)

                Spacer()

                Text("\(chain.effects.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.08))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.0 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onApplyToGlobal()
            } label: {
                Label("Apply to Composition", systemImage: "globe")
            }

            Button {
                onApplyToSelectedLayer?()
            } label: {
                Label("Apply to Selected Layer", systemImage: "square.3.layers.3d")
            }
            .disabled(onApplyToSelectedLayer == nil)

            Divider()

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
