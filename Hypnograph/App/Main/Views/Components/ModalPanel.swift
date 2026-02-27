//
//  ModalPanel.swift
//  Hypnograph
//
//  Reusable modal panel component for overlay UI.
//  Standard pattern for overlay UI (e.g. live preview).
//

import SwiftUI

/// Configuration for modal panel appearance
struct ModalPanelStyle {
    var backgroundColor: Color = Color.black.opacity(0.6)
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 16
    var minWidth: CGFloat? = nil
    var maxWidth: CGFloat? = nil
    var minHeight: CGFloat? = nil
    var maxHeight: CGFloat? = nil
    
    static let livePreview = ModalPanelStyle(
        minWidth: 320,
        maxWidth: 480,
        minHeight: 180,
        maxHeight: 320
    )
}

/// Reusable modal panel container
struct ModalPanel<Content: View>: View {
    let title: String
    let style: ModalPanelStyle
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    
    /// Optional header actions (buttons to the left of close)
    var headerActions: AnyView? = nil
    
    init(
        title: String,
        style: ModalPanelStyle = ModalPanelStyle(),
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.style = style
        self.onClose = onClose
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                if let actions = headerActions {
                    actions
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.bottom, 12)
            
            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.bottom, 12)
            
            // Content
            content()
        }
        .foregroundColor(.white)
        .padding(style.padding)
        .frame(
            minWidth: style.minWidth,
            maxWidth: style.maxWidth,
            minHeight: style.minHeight,
            maxHeight: style.maxHeight
        )
        .background(style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
    }
}

/// Extension to add header actions
extension ModalPanel {
    func headerActions<A: View>(@ViewBuilder _ actions: @escaping () -> A) -> some View {
        var copy = self
        copy.headerActions = AnyView(actions())
        return copy
    }
}

// MARK: - Focusable Section

/// A focusable section within a modal that participates in tab navigation
struct FocusableSection<Content: View>: View {
    let isFocused: Bool
    let focusColor: Color
    @ViewBuilder let content: () -> Content
    
    init(
        isFocused: Bool,
        focusColor: Color = .cyan,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isFocused = isFocused
        self.focusColor = focusColor
        self.content = content
    }
    
    var body: some View {
        content()
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(focusColor.opacity(0.6), lineWidth: isFocused ? 1 : 0)
            )
    }
}
