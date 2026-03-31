import SwiftUI

struct KeyboardHintBar: View {
    var body: some View {
        HStack(spacing: 18) {
            KeyboardHint(key: "Tab", action: "Toggle Panels")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassPanel(cornerRadius: 12)
    }
}

private struct KeyboardHint: View {
    let key: String
    let action: String

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                )

            Text(action)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
