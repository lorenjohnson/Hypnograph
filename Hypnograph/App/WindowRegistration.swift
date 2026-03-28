//
//  WindowRegistration.swift
//  Hypnograph
//
//  Automatic window registration system for WindowState.
//  Windows self-register on first appearance without manual boilerplate.
//

import SwiftUI

/// ViewModifier that automatically registers a window with WindowState on first appearance
struct WindowRegistrationModifier: ViewModifier {
    let windowID: String
    let defaultVisible: Bool
    @ObservedObject var controller: WindowStateController

    @State private var hasRegistered = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Register once on first appearance
                if !hasRegistered {
                    controller.registerWindow(windowID, defaultVisible: defaultVisible)
                    hasRegistered = true
                }
            }
    }
}

extension View {
    /// Register this view as a window with the given ID
    /// Automatically registers the window with WindowState on first appearance
    ///
    /// - Parameters:
    ///   - windowID: Unique string identifier for this window (e.g., "hud", "effectsEditor")
    ///   - defaultVisible: Whether the window should be visible by default on first registration
    ///   - controller: The WindowStateController instance to register with
    ///
    /// - Returns: A view that automatically registers itself as a window
    ///
    /// Example usage:
    /// ```swift
    /// HUDView(...)
    ///     .registerWindow("hud", defaultVisible: false, controller: studio.windows)
    /// ```
    func registerWindow(_ windowID: String, defaultVisible: Bool = false, controller: WindowStateController) -> some View {
        modifier(WindowRegistrationModifier(windowID: windowID, defaultVisible: defaultVisible, controller: controller))
    }
}
