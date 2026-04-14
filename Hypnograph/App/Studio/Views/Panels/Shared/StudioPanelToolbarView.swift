import SwiftUI

struct StudioPanelToolbarItem: Identifiable {
    let descriptor: StudioPanelDescriptor

    var id: String { descriptor.id }
}

struct StudioPanelToolbarView: View {
    private enum LayoutMode {
        case expanded
        case compact
    }

    let items: [StudioPanelToolbarItem]
    let isPanelVisible: (String) -> Bool
    let onTogglePanel: (String) -> Void
    @Binding var panelOpacity: Double
    var liveModeSelection: Binding<Int>? = nil

    var body: some View {
        GeometryReader { proxy in
            toolbarContent(
                mode: layoutMode(for: proxy.size.width),
                showsShortcutText: showsShortcutText(for: proxy.size.width),
                showsSliderLabel: false
            )
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func toolbarContent(
        mode: LayoutMode,
        showsShortcutText: Bool,
        showsSliderLabel: Bool
    ) -> some View {
        let toolbarShape = RoundedRectangle(cornerRadius: 13, style: .continuous)

        HStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    panelToggleButton(item, mode: mode, showsShortcutText: showsShortcutText)
                }
            }

            Spacer(minLength: 0)

            Divider()
                .frame(height: 22)

            HStack(spacing: 8) {
                if showsSliderLabel {
                    Text("Panels")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                PanelSliderView(value: $panelOpacity, bounds: 0.32...0.92)
                    .frame(width: mode == .compact ? 88 : 110)
                    .help("Adjust all Studio panel transparency.")
            }

            if let liveModeSelection {
                Divider()
                    .frame(height: 22)

                Picker("", selection: liveModeSelection) {
                    Text("Edit").tag(0)
                    Text("Live").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: mode == .compact ? 136 : 170)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            toolbarShape
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            toolbarShape
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .contentShape(toolbarShape)
        .allowsHitTesting(true)
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private func panelToggleButton(
        _ item: StudioPanelToolbarItem,
        mode: LayoutMode,
        showsShortcutText: Bool
    ) -> some View {
        let descriptor = item.descriptor
        let isVisible = isPanelVisible(descriptor.panelID)

        if isVisible {
            Button {
                onTogglePanel(descriptor.panelID)
            } label: {
                panelToggleLabel(descriptor, mode: mode, showsShortcutText: showsShortcutText)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("\(descriptor.title) (\(descriptor.shortcutLabel))")
        } else {
            Button {
                onTogglePanel(descriptor.panelID)
            } label: {
                panelToggleLabel(descriptor, mode: mode, showsShortcutText: showsShortcutText)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("\(descriptor.title) (\(descriptor.shortcutLabel))")
        }
    }

    @ViewBuilder
    private func panelToggleLabel(
        _ descriptor: StudioPanelDescriptor,
        mode: LayoutMode,
        showsShortcutText: Bool
    ) -> some View {
        switch mode {
        case .expanded:
            Label(buttonText(for: descriptor, showsShortcutText: showsShortcutText), systemImage: descriptor.systemImage)
        case .compact:
            Image(systemName: descriptor.systemImage)
                .frame(width: 18, height: 18)
        }
    }

    private func buttonText(for descriptor: StudioPanelDescriptor, showsShortcutText: Bool) -> String {
        if showsShortcutText {
            return "\(descriptor.title) (\(descriptor.shortcutLabel))"
        }
        return descriptor.title
    }

    private func layoutMode(for width: CGFloat) -> LayoutMode {
        width >= 1080 ? .expanded : .compact
    }

    private func showsShortcutText(for width: CGFloat) -> Bool {
        width >= 1320
    }
}
