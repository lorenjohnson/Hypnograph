//
//  TooltipManager.swift
//  Hypnograph
//
//  App-wide tooltip management for hover tooltips.
//  Tooltip text is displayed in the Info HUD when visible.
//

import SwiftUI

/// Manages app-wide tooltip state for hover tooltips
/// Tooltip text is published and displayed in the Info HUD
@MainActor
final class TooltipManager: ObservableObject {
    static let shared = TooltipManager()
    
    /// Current tooltip text to display (nil = no tooltip)
    @Published private(set) var currentTooltip: String?
    
    private init() {}
    
    /// Set the current tooltip text
    func setTooltip(_ text: String?) {
        currentTooltip = text
    }
    
    /// Clear the current tooltip
    func clearTooltip() {
        currentTooltip = nil
    }
}

// MARK: - HUDTooltip View Modifier

/// A view modifier that shows tooltip text in the Info HUD on hover
struct HUDTooltipModifier: ViewModifier {
    let tooltip: String
    @State private var isHovering = false
    @State private var lastSetTooltip: String?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    TooltipManager.shared.setTooltip(tooltip)
                    lastSetTooltip = tooltip
                } else {
                    // Clear the tooltip we set (track what we actually set, not current value)
                    if let last = lastSetTooltip, TooltipManager.shared.currentTooltip == last {
                        TooltipManager.shared.clearTooltip()
                    }
                    lastSetTooltip = nil
                }
            }
            .onChange(of: tooltip) { _, newTooltip in
                // If tooltip text changes while hovering, update it
                if isHovering {
                    TooltipManager.shared.setTooltip(newTooltip)
                    lastSetTooltip = newTooltip
                }
            }
    }
}

extension View {
    /// Adds a hover tooltip that displays in the Info HUD
    /// - Parameter tooltip: The tooltip text to display on hover
    func hudTooltip(_ tooltip: String) -> some View {
        self.modifier(HUDTooltipModifier(tooltip: tooltip))
    }
}

