//
//  LiveModePlayerView.swift
//  Hypnograph
//
//  Full-screen player view for Live mode - mirrors the Performance Display player.
//  Used as the main preview when in Live performance mode.
//

import SwiftUI
import AVKit
import AppKit

/// Full-screen player view that mirrors Performance Display content
/// Used as the main preview when in Live mode (Cmd-P)
struct LiveModePlayerView: View {
    @ObservedObject var performanceDisplay: PerformanceDisplay

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if performanceDisplay.hasContent {
                LiveModeAVPlayerView(performanceDisplay: performanceDisplay)
                    .ignoresSafeArea()
            } else {
                // Placeholder when no content
                VStack(spacing: 12) {
                    Image(systemName: "play.display")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No Performance Content")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Send content with ⌘Return")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
    }
}

/// NSViewRepresentable wrapper for AVPlayerView that mirrors Performance Display
struct LiveModeAVPlayerView: NSViewRepresentable {
    @ObservedObject var performanceDisplay: PerformanceDisplay

    func makeNSView(context: Context) -> AVPlayerView {
        // Use HitTransparentPlayerView so keyboard shortcuts still work
        let playerView = HitTransparentPlayerView()
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.player = performanceDisplay.activeAVPlayer
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

