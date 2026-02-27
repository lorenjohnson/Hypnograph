//
//  EffectsEditorHoverRevealControlsRow.swift
//  Hypnograph
//
//  Shared row wrapper that reveals trailing controls on hover/selection.
//

import SwiftUI

struct EffectsEditorHoverRevealControlsRow<Label: View, Controls: View>: View {
    let isSelected: Bool
    let label: Label
    let controls: Controls

    @State private var isHovered = false

    init(isSelected: Bool, @ViewBuilder label: () -> Label, @ViewBuilder controls: () -> Controls) {
        self.isSelected = isSelected
        self.label = label()
        self.controls = controls()
    }

    var body: some View {
        let showControls = isSelected || isHovered
        ZStack(alignment: .trailing) {
            label
            controls
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
        }
        .onHover { isHovered = $0 }
    }
}
