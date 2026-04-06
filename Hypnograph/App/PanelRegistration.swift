//
//  PanelRegistration.swift
//  Hypnograph
//
//  Automatic panel registration system for shared panel visibility state.
//  Auxiliary views self-register on first appearance without manual boilerplate.
//

import SwiftUI

/// ViewModifier that automatically registers a panel with shared panel visibility state on first appearance.
struct PanelRegistrationModifier: ViewModifier {
    let panelID: String
    let defaultVisible: Bool
    @ObservedObject var controller: PanelStateController

    @State private var hasRegistered = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !hasRegistered {
                    controller.registerPanel(panelID, defaultVisible: defaultVisible)
                    hasRegistered = true
                }
            }
    }
}

extension View {
    /// Register this view as an auxiliary panel with the given ID.
    /// Automatically registers the panel with shared panel visibility state on first appearance.
    ///
    /// - Parameters:
    ///   - panelID: Unique string identifier for this panel (e.g., "hudPanel", "livePreviewPanel")
    ///   - defaultVisible: Whether the panel should be visible by default on first registration
    ///   - controller: The PanelStateController instance to register with
    ///
    /// - Returns: A view that automatically registers itself as a panel
    ///
    /// Example usage:
    /// ```swift
    /// HUDView(...)
    ///     .registerPanel("hudPanel", defaultVisible: false, controller: studio.panels)
    /// ```
    func registerPanel(_ panelID: String, defaultVisible: Bool = false, controller: PanelStateController) -> some View {
        modifier(PanelRegistrationModifier(panelID: panelID, defaultVisible: defaultVisible, controller: controller))
    }
}
