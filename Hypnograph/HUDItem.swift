//
//  HUDItem.swift
//  Hypnograph
//
//  Created by Loren Johnson on 20.11.25.
//

import SwiftUI

/// Represents a single item in the HUD overlay.
/// Items are ordered by their `order` value, allowing modes to inject
/// items between global items (e.g., global items at 10, 20, 30; mode items at 15, 25).
struct HUDItem {
    let order: Int
    let content: Content
    
    enum Content {
        /// A text line with optional font style
        case text(String, font: Font = .caption)
        
        /// A spacer/padding of specified height
        case padding(CGFloat)
        
        /// A custom SwiftUI view
        case custom(AnyView)
    }
    
    // Convenience initializers
    static func text(_ text: String, order: Int, font: Font = .caption) -> HUDItem {
        HUDItem(order: order, content: .text(text, font: font))
    }
    
    static func padding(_ height: CGFloat, order: Int) -> HUDItem {
        HUDItem(order: order, content: .padding(height))
    }
    
    static func custom(_ view: AnyView, order: Int) -> HUDItem {
        HUDItem(order: order, content: .custom(view))
    }
}

/// Extension to render HUDItem content as a SwiftUI View
extension HUDItem {
    @ViewBuilder
    func render() -> some View {
        switch content {
        case .text(let string, let font):
            Text(string)
                .font(font)
                .foregroundColor(.white)
        case .padding(let height):
            Spacer()
                .frame(height: height)
        case .custom(let view):
            view
        }
    }
}

