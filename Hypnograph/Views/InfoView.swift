//
//  InfoView.swift
//  Hypnograph
//
//  Displays current source file paths in a small tool window.
//

import SwiftUI
import AppKit

struct InfoView: View {
    let sources: [HypnogramSource]
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with close button
            HStack {
                Text("Sources (\(sources.count))")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Source list
            if sources.isEmpty {
                Text("No sources loaded")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                            SourceRow(index: index, source: source)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 500, height: 300)
        .background(.ultraThinMaterial)
    }
}

struct SourceRow: View {
    let index: Int
    let source: HypnogramSource
    
    private var filePath: String {
        switch source.clip.file.source {
        case .url(let url):
            return url.path
        case .photos(let identifier):
            return "photos://\(identifier)"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1).")
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
            
            Text(filePath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Window Controller

final class InfoWindowController {
    static let shared = InfoWindowController()
    
    private var window: NSWindow?
    private var hostingView: NSHostingView<InfoView>?
    
    private init() {}
    
    func show(sources: [HypnogramSource]) {
        if let existingWindow = window {
            existingWindow.orderFront(nil)
            updateContent(sources: sources)
            return
        }
        
        let infoView = InfoView(sources: sources) { [weak self] in
            self?.close()
        }
        
        let hostingView = NSHostingView(rootView: infoView)
        self.hostingView = hostingView
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Hypnograph Info"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
    
    func updateContent(sources: [HypnogramSource]) {
        let infoView = InfoView(sources: sources) { [weak self] in
            self?.close()
        }
        hostingView?.rootView = infoView
    }
    
    func close() {
        window?.close()
        window = nil
        hostingView = nil
    }
    
    var isVisible: Bool {
        window?.isVisible ?? false
    }
    
    func toggle(sources: [HypnogramSource]) {
        if isVisible {
            close()
        } else {
            show(sources: sources)
        }
    }
}

