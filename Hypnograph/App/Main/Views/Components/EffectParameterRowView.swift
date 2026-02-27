import SwiftUI
import HypnoCore

/// Shared effect parameter editor row used by both Main and Effects Studio.
struct EffectParameterRowView: View {
    let name: String
    let value: AnyCodableValue
    let spec: ParameterSpec?
    let onChange: (AnyCodableValue) -> Void

    var body: some View {
        ParameterSliderRow(
            name: name,
            value: value,
            effectType: nil,
            spec: spec,
            onChange: onChange
        )
    }
}
