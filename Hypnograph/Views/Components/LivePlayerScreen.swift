//
//  LivePlayerScreen.swift
//  Hypnograph
//
//  Full-screen player screen for Live mode - mirrors the Live Display player.
//  Used as the main preview when in Live mode.
//

import SwiftUI
import AVKit
import AppKit

/// Full-screen player screen that mirrors Live Display content
/// Used as the main preview when in Live mode (Cmd-P)
struct LivePlayerScreen: View {
    @ObservedObject var livePlayer: LivePlayer

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if livePlayer.hasContent {
                LiveModeAVPlayerView(livePlayer: livePlayer)
                    .ignoresSafeArea()
            } else {
                // Placeholder when no content
                VStack(spacing: 12) {
                    Image(systemName: "play.display")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No Live Content")
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

/// NSViewRepresentable wrapper for AVPlayerView that mirrors Live Display
struct LiveModeAVPlayerView: NSViewRepresentable {
    @ObservedObject var livePlayer: LivePlayer

    func makeNSView(context: Context) -> AVPlayerView {
        // Use HitTransparentPlayerView so keyboard shortcuts still work
        let playerView = HitTransparentPlayerView()
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.player = livePlayer.activeAVPlayer
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Mirror the active player from live display
        nsView.player = livePlayer.activeAVPlayer
    }

    /// AVPlayerView that forwards mouse/keyboard events so SwiftUI and menu shortcuts still work
    private final class HitTransparentPlayerView: AVPlayerView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

