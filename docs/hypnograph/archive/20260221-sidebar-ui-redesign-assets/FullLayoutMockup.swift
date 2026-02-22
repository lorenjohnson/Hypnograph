import SwiftUI

// MARK: - Full Layout Mockup

/// Combined view showing both sidebars overlaid on a video placeholder.
/// This represents the target UI layout for Hypnograph.

struct FullLayoutMockup: View {
    @State private var showLeftSidebar = true
    @State private var showRightSidebar = true
    @State private var mode = 0  // 0 = Preview, 1 = Live

    var body: some View {
        ZStack {
            // Video placeholder (black background)
            Color.black
                .ignoresSafeArea()

            // Simulated video content
            ZStack {
                LinearGradient(
                    colors: [.purple.opacity(0.3), .blue.opacity(0.2), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Text("Video Content Area")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .ignoresSafeArea()

            // Sidebars overlay
            HStack(spacing: 0) {
                // Left sidebar
                if showLeftSidebar {
                    LeftSidebarMockup()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Spacer()

                // Right sidebar
                if showRightSidebar {
                    RightSidebarMockup()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.25), value: showLeftSidebar)
            .animation(.easeInOut(duration: 0.25), value: showRightSidebar)

            // Mode indicator (top center)
            VStack {
                HStack(spacing: 0) {
                    Spacer()

                    // Mode switcher with Liquid Glass styling
                    Picker("Mode", selection: $mode) {
                        Text("Preview").tag(0)
                        Text("Live").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .liquidGlass(cornerRadius: 10)

                    Spacer()
                }
                .padding(.top, 12)

                Spacer()
            }

            // Keyboard hints (bottom) with Liquid Glass styling
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    KeyboardHint(key: "[", action: "Toggle Left")
                    KeyboardHint(key: "]", action: "Toggle Right")
                    KeyboardHint(key: "Tab", action: "Toggle Windows")
                }
                .padding(12)
                .liquidGlass(cornerRadius: 10)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 1200, minHeight: 800)
    }
}

struct KeyboardHint: View {
    let key: String
    let action: String

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
            Text(action)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Compact Layout Variation

/// Alternative layout with narrower sidebars for smaller windows.

struct CompactLayoutMockup: View {
    @State private var showLeftSidebar = true
    @State private var showRightSidebar = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Compact sidebars (icons only when collapsed)
            HStack(spacing: 0) {
                if showLeftSidebar {
                    CompactLeftSidebarMockup()
                            .transition(.move(edge: .leading))
                }

                Spacer()

                if showRightSidebar {
                    CompactRightSidebarMockup()
                        .transition(.move(edge: .trailing))
                }
            }
            .padding(12)
            .animation(.easeInOut(duration: 0.2), value: showLeftSidebar)
            .animation(.easeInOut(duration: 0.2), value: showRightSidebar)
        }
        .frame(width: 900, height: 600)
    }
}

struct CompactLeftSidebarMockup: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Icon-only tabs
            HStack(spacing: 4) {
                TabIconButton(icon: "photo.stack", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabIconButton(icon: "gearshape", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                TabIconButton(icon: "star", isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
            }
            .padding(8)

            Divider()

            // Compact content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    switch selectedTab {
                    case 0:
                        CompactSourcesList()
                    case 1:
                        CompactSettingsList()
                    case 2:
                        CompactFavoritesList()
                    default:
                        EmptyView()
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct TabIconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 32, height: 28)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : .secondary)
    }
}

struct CompactSourcesList: View {
    @State private var imagesOn = true
    @State private var videosOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Images", isOn: $imagesOn)
                .toggleStyle(.switch)
                .controlSize(.small)
            Toggle("Videos", isOn: $videosOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

struct CompactSettingsList: View {
    @State private var maxLayers = 3
    @State private var rate = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("Layers: \(maxLayers)", value: $maxLayers, in: 1...9)
                .controlSize(.small)
            HStack {
                Text("Rate")
                Slider(value: $rate, in: 0.25...4)
            }
        }
    }
}

struct CompactFavoritesList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Summer Vibes").font(.callout)
            Text("Night Mode").font(.callout)
            Text("Vintage").font(.callout)
        }
    }
}

struct CompactRightSidebarMockup: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                TabIconButton(icon: "square.3.layers.3d", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabIconButton(icon: "wand.and.stars", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
            }
            .padding(8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if selectedTab == 0 {
                        Text("Global").font(.callout.weight(.medium))
                        Text("Layer 1").font(.callout)
                        Text("Layer 2").font(.callout)
                    } else {
                        Text("Chromatic").font(.callout)
                        Text("Bloom").font(.callout)
                        Text("Blur").font(.callout)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Preview

#Preview {
    FullLayoutMockup()
}
