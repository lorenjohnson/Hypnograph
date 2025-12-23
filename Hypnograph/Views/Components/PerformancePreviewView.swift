//
//  PerformancePreviewView.swift
//  Hypnograph
//
//  Preview panel for performance display shown in sidebar.
//  Shows current hypnogram playback with button to toggle external window.
//

import SwiftUI
import AVKit
import AppKit

/// Preview of performance display content, shown as panel in main window
struct PerformancePreviewView: View {
    @ObservedObject var performanceDisplay: PerformanceDisplay
    let onClose: () -> Void

    /// Check if external monitors are available
    private var hasExternalMonitor: Bool {
        NSScreen.screens.count > 1
    }

    /// Whether the separate window is currently shown
    private var isWindowVisible: Bool {
        performanceDisplay.isVisible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Performance")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                // Toggle external/window button
                Button(action: {
                    performanceDisplay.toggle()
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

                if performanceDisplay.hasContent {
                    // Show wrapped AVPlayerView from performance display
                    PerformancePlayerWrapper(performanceDisplay: performanceDisplay)
                        .aspectRatio(16/9, contentMode: .fit)
                } else {
                    // Placeholder when no content yet
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                        Text("Loading...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .cornerRadius(6)
            .clipped()

            // Status bar
            HStack {
                if performanceDisplay.isTransitioning {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.cyan)
                    Text("Transitioning...")
                } else if !performanceDisplay.currentRecipeDescription.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(performanceDisplay.currentRecipeDescription)
                } else {
                    Text("Ready")
                        .foregroundColor(.white.opacity(0.4))
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
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// NSViewRepresentable to show current performance player content
struct PerformancePlayerWrapper: NSViewRepresentable {
    @ObservedObject var performanceDisplay: PerformanceDisplay

    func makeNSView(context: Context) -> AVPlayerView {
        // Use HitTransparentPlayerView so keyboard shortcuts still work
        let playerView = HitTransparentPlayerView()
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Mirror the active player from performance display
        nsView.player = performanceDisplay.activeAVPlayer
    }

    /// AVPlayerView that forwards mouse/keyboard events so SwiftUI and menu shortcuts still work
    private final class HitTransparentPlayerView: AVPlayerView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

