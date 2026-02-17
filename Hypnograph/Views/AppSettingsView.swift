import SwiftUI
import AppKit
import HypnoCore

struct AppSettingsView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream
    @StateObject private var audioManager = AudioDeviceManager.shared

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
                Text("Configure feature availability, keyboard behavior, audio routing, and maintenance actions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    settingsDeviceRow(
                        title: "Preview Audio Output",
                        description: "Select the audio output device used for preview playback.",
                        selection: Binding(
                            get: { dream.previewAudioDevice },
                            set: { dream.previewAudioDevice = $0 }
                        )
                    )

                    if state.settings.liveModeEnabled {
                        Divider()

                        settingsDeviceRow(
                            title: "Live Audio Output",
                            description: "Select the audio output device used when sending audio to Live.",
                            selection: Binding(
                                get: { dream.liveAudioDevice },
                                set: { dream.liveAudioDevice = $0 }
                            )
                        )
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
                    Divider()

                    settingsFolderRow(
                        title: "Render Output Folder",
                        description: "Where rendered videos are saved.",
                        path: state.settings.outputFolder
                    ) {
                        chooseOutputFolder()
                    }
                    Divider()

                    settingsActionRow(
                        title: "Clear Clip History",
                        description: "Removes all previous clips from history and keeps your current clip selected.",
                        buttonTitle: "Clear"
                    ) {
                        dream.clearClipHistory()
                    }
                    Divider()

                    settingsStepperRow(
                        title: "History Limit",
                        description: "Max clips in history.",
                        value: Binding(
                            get: { max(1, state.settings.historyLimit) },
                            set: { newValue in
                                state.settingsStore.update { $0.historyLimit = max(1, newValue) }
                            }
                        ),
                        range: 1...5000
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
    private func settingsFolderRow(
        title: String,
        description: String,
        path: String,
        onChoose: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayPath(path))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.top, 2)
            }
            Spacer(minLength: 12)
            Button("Choose…", action: onChoose)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func settingsStepperRow(
        title: String,
        description: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
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
            HStack(spacing: 8) {
                Text("\(value.wrappedValue)")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 48, alignment: .trailing)
                Stepper("", value: value, in: range)
                    .labelsHidden()
            }
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

    @ViewBuilder
    private func settingsDeviceRow(
        title: String,
        description: String,
        selection: Binding<AudioOutputDevice?>
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
            Picker("", selection: selection) {
                ForEach(audioManager.outputDevices) { device in
                    Text(device.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .tag(device as AudioOutputDevice?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.title = "Choose Render Output Folder"
        panel.directoryURL = state.settings.outputURL

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        state.settingsStore.update { settings in
            settings.outputFolder = storagePath(from: folderURL)
        }
    }

    private func displayPath(_ path: String) -> String {
        ((path as NSString).expandingTildeInPath as NSString).abbreviatingWithTildeInPath
    }

    private func storagePath(from url: URL) -> String {
        let expandedPath = url.path
        let homePath = NSHomeDirectory()
        if expandedPath.hasPrefix(homePath) {
            return "~" + expandedPath.dropFirst(homePath.count)
        }
        return expandedPath
    }
}
