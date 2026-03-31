import SwiftUI

struct PanelSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
            .padding(.top, 4)
            .padding(.bottom, 1)
    }
}

struct PanelInlineFieldRow<Trailing: View>: View {
    let title: String
    var valueText: String?
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        valueText: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.valueText = valueText
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.primary)

            Spacer(minLength: 10)

            if let valueText {
                Text(valueText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PanelFieldRow<Control: View>: View {
    let title: String
    var valueText: String?
    @ViewBuilder let control: Control

    init(
        title: String,
        valueText: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.valueText = valueText
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)

                Spacer(minLength: 10)

                if let valueText {
                    Text(valueText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            control
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
