//
//  LivePreviewPanel.swift
//  Hypnograph
//
//  Preview panel for live display shown in sidebar.
//  Shows current live player output with button to toggle external window.
//

import SwiftUI
import AppKit
import HypnoCore

/// Preview of live display content, shown as panel in main window
struct LivePreviewPanel: View {
    @ObservedObject var livePlayer: LivePlayer
    let onClose: () -> Void

    /// Check if external monitors are available
    private var hasExternalMonitor: Bool {
        NSScreen.screens.count > 1
    }

    /// Whether the separate window is currently shown
    private var isWindowVisible: Bool {
        livePlayer.isVisible
    }

    /// Aspect ratio used for the preview panel.
    /// If the player is set to Fill Window, pick a reasonable default based on the live target screen
    /// (external monitor if present, otherwise main).
    private var previewAspectRatio: CGFloat {
        let ar = livePlayer.aspectRatio
        if !ar.isFillWindow {
            return ar.value
        }

        let target = NSScreen.screens.first(where: { $0 != NSScreen.main }) ?? NSScreen.main
        guard let frame = target?.frame, frame.height > 0 else {
            return 16.0 / 9.0
        }
        return frame.width / frame.height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Title and control buttons
            HStack {
                Text("Preview")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                // Reset button
                Button(action: {
                    livePlayer.reset()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.6))
                .cornerRadius(4)

                // Toggle external/window button
                Button(action: {
                    livePlayer.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: hasExternalMonitor ? "display" : "macwindow")
                        Text(isWindowVisible ? "Hide Window" : (hasExternalMonitor ? "External" : "Window"))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isWindowVisible ? Color.green.opacity(0.5) : Color.blue.opacity(0.6))
                .cornerRadius(4)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            // Preview content - always show player if available
            ZStack {
                Color.black

                if livePlayer.hasContent {
                    // Show Metal mirror of live display content
                    LiveContentViewWrapper(livePlayer: livePlayer)
                } else {
                    // Placeholder when no source assigned
                    VStack(spacing: 8) {
                        Image(systemName: "play.display")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No Source")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Text("Press ⌘Return to send")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .cornerRadius(6)
            .clipped()

            // Status bar
            HStack {
                if livePlayer.isTransitioning {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.cyan)
                    Text("Transitioning...")
                } else if
                    !livePlayer.currentRecipeDescription.isEmpty,
                    livePlayer.currentRecipeDescription != "Ready"
                {
                    Text(livePlayer.currentRecipeDescription)
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer()

                if isWindowVisible {
                    Text(hasExternalMonitor ? "On external" : "Windowed")
                        .foregroundColor(.green.opacity(0.8))
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
            .padding(.top, 8)
        }
        .foregroundColor(.white)
        .padding(20)
        .frame(width: 500)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
