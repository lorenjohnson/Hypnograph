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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Hypnograph Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Version \(versionText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    let liveModeEnabled = state.settings.liveModeEnabled
                    settingsDeviceRow(
                        title: liveModeEnabled ? "Audio Output Device (Preview)" : "Audio Output Device",
                        description: liveModeEnabled
                            ? "Select the audio output device used for preview playback."
                            : "Select the audio output device.",
                        selection: Binding(
                            get: { dream.previewAudioDevice },
                            set: { dream.previewAudioDevice = $0 }
                        )
                    )

                    if liveModeEnabled {
                        Divider()

                        settingsDeviceRow(
                            title: "Audio Output Device (Live)",
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
                        buttonTitle: "Clear",
                        isDestructive: true
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
        .background(SettingsWindowPresentationConfigurator())
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
        isDestructive: Bool = false,
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
            if isDestructive {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
            }
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
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 260, alignment: .trailing)
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

private struct SettingsWindowPresentationConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configure(using: nsView)
    }

    final class Coordinator {
        private let minimumWidth: CGFloat = 420
        private let maximumWidth: CGFloat = 560
        private weak var window: NSWindow?
        private var closeObserver: NSObjectProtocol?
        private var originalLevel: NSWindow.Level = .normal
        private var isModalRunning = false

        deinit {
            teardown()
        }

        func configure(using view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }

                // Keep Settings chrome minimal and make this panel visually modal.
                window.title = ""
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                if self.window !== window {
                    self.teardown()
                    self.window = window
                    self.originalLevel = window.level
                    self.closeObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.willCloseNotification,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in
                        self?.teardown()
                    }
                }

                window.level = .modalPanel
                window.contentMinSize = NSSize(width: self.minimumWidth, height: 380)
                window.contentMaxSize = NSSize(width: self.maximumWidth, height: .greatestFiniteMagnitude)
                let currentWidth = window.contentLayoutRect.width
                let clampedWidth = min(max(currentWidth, self.minimumWidth), self.maximumWidth)
                if abs(currentWidth - clampedWidth) > 1 {
                    window.setContentSize(
                        NSSize(
                            width: clampedWidth,
                            height: max(380, window.contentLayoutRect.height)
                        )
                    )
                }

                guard !self.isModalRunning else { return }
                self.isModalRunning = true
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)

                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, self.window === window else { return }
                    NSApp.runModal(for: window)
                    self.isModalRunning = false
                }
            }
        }

        private func teardown() {
            if let window,
               NSApp.modalWindow === window {
                NSApp.stopModal()
            }
            isModalRunning = false

            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
                self.closeObserver = nil
            }

            if let window {
                window.level = originalLevel
            }
            window = nil
        }
    }
}
