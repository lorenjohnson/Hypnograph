import SwiftUI

extension View {
    func colorEffect(_ effect: GlobalEffect) -> some View {
        switch effect {
        case .none:
            return AnyView(self)

        case .monochrome:
            return AnyView(self.saturation(0))

        case .noir:
            return AnyView(self
                .saturation(0)
                .contrast(1.3)
            )

        case .sepia:
            return AnyView(self
                .colorMultiply(.brown)
            )

        case .bloom:
            return AnyView(self
                .blur(radius: 2)
                .brightness(0.05)
            )

        case .invert:
            return AnyView(self.colorInvert())
        }
    }
}