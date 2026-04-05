import SwiftUI

struct PanelLayoutInvalidator {
    var invalidate: () -> Void = {}

    func callAsFunction() {
        invalidate()
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
