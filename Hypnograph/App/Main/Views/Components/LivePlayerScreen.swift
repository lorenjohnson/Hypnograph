//
//  LivePlayerScreen.swift
//  Hypnograph
//
//  Full-screen player screen for Live mode - mirrors the Live Display player.
//  Used as the main preview when in Live mode.
//

import SwiftUI
import AppKit
import HypnoCore

/// Full-screen player screen that mirrors Live Display content
/// Used as the main preview when in Live mode (Cmd-P)
struct LivePlayerScreen: View {
    @ObservedObject var livePlayer: LivePlayer

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if livePlayer.hasContent {
                LiveContentViewWrapper(livePlayer: livePlayer)
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

/// NSViewRepresentable wrapper that creates a mirror of the LivePlayer's content
struct LiveContentViewWrapper: NSViewRepresentable {
    @ObservedObject var livePlayer: LivePlayer

    @MainActor
    class Coordinator {
        var mirrorView: PlayerContentMirrorView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = HitTransparentView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator

        // Create mirror view if needed
        if c.mirrorView == nil, let mirror = livePlayer.createMirrorView() {
            c.mirrorView = mirror
            mirror.translatesAutoresizingMaskIntoConstraints = false
            nsView.addSubview(mirror)

            NSLayoutConstraint.activate([
                mirror.topAnchor.constraint(equalTo: nsView.topAnchor),
                mirror.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
                mirror.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                mirror.trailingAnchor.constraint(equalTo: nsView.trailingAnchor)
            ])
        }

        // Sync transition state (handles both active transitions and steady state)
        c.mirrorView?.syncTransitionState()

        // Update content mode
        let contentMode: PlayerView.ContentMode = livePlayer.config.aspectRatio.isFillWindow ? .aspectFill : .aspectFit
        c.mirrorView?.setContentMode(contentMode)
    }

    /// NSView that forwards mouse/keyboard events so SwiftUI and menu shortcuts still work
    private final class HitTransparentView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
