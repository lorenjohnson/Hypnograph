import SwiftUI
import HypnoCore

/// Shared effect parameter editor row used by both Studio and Effects Composer.
struct EffectParameterRowView: View {
    let name: String
    let value: AnyCodableValue
    let effectType: String?
    let spec: ParameterSpec?
    let onChange: (AnyCodableValue) -> Void

    init(
        name: String,
        value: AnyCodableValue,
        effectType: String? = nil,
        spec: ParameterSpec?,
        onChange: @escaping (AnyCodableValue) -> Void
    ) {
        self.name = name
        self.value = value
        self.effectType = effectType
        self.spec = spec
        self.onChange = onChange
    }

    var body: some View {
        ParameterSliderRow(
            name: name,
            value: value,
            effectType: effectType,
            spec: spec,
            onChange: onChange
        )
    }
}
