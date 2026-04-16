import SwiftUI

struct PanelLayoutInvalidator {
    var invalidate: (Bool) -> Void = { _ in }

    func callAsFunction(resetScrollToTop: Bool = false) {
        invalidate(resetScrollToTop)
    }
}

private struct PanelLayoutInvalidatorKey: EnvironmentKey {
    static let defaultValue = PanelLayoutInvalidator()
}

extension EnvironmentValues {
    var panelLayoutInvalidator: PanelLayoutInvalidator {
        get { self[PanelLayoutInvalidatorKey.self] }
        set { self[PanelLayoutInvalidatorKey.self] = newValue }
    }
}
