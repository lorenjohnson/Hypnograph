import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream

    private var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(shortVersion) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hypnograph Settings")
                    .font(.title3.weight(.semibold))
                Text("Version \(versionText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Configure feature availability, keyboard behavior, and maintenance actions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                settingsToggleRow(
                    title: "Live/Performance mode options",
                    description: "Enables controls for live preview, live mode, and external monitor output.",
                    isOn: Binding(
                        get: { state.settings.liveModeEnabled },
                        set: { newValue in
                            state.settingsStore.update { $0.liveModeEnabled = newValue }
                        }
                    )
                )
                Divider()

                settingsToggleRow(
                    title: "Override Keyboard Accessibility Keys (Space, Tab)",
                    description: "When enabled, Space controls Play/Pause and Tab toggles Clean Screen.",
                    isOn: Binding(
                        get: { state.settings.keyboardAccessibilityOverridesEnabled },
                        set: { newValue in
                            state.settingsStore.update { $0.keyboardAccessibilityOverridesEnabled = newValue }
                        }
                    )
                )
                Divider()

                settingsActionRow(
                    title: "Clear Clip History",
                    description: "Removes all previous clips from history and keeps your current clip selected.",
                    buttonTitle: "Clear"
                ) {
                    dream.clearClipHistory()
                }
                Divider()

                settingsActionRow(
                    title: "Show Settings Folder",
                    description: "Opens your Hypnograph settings directory in Finder."
                ) {
                    Environment.showSettingsFolderInFinder()
                }
                Divider()

                settingsActionRow(
                    title: "Install hypnograph CLI and Finder Action",
                    description: "Installs command-line and Finder integration helpers."
                ) {
                    Environment.installCLI()
                    Environment.installAutomatorQuickAction()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func settingsToggleRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func settingsActionRow(
        title: String,
        description: String,
        buttonTitle: String = "Run",
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
