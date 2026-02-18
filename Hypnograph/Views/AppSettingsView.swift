import SwiftUI
import AppKit
import HypnoCore

struct AppSettingsView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream
    @StateObject private var audioManager = AudioDeviceManager.shared
    @State private var selectedTab: SettingsTab = .general

    private enum SettingsTab: CaseIterable {
        case general
        case advanced

        var title: String {
            switch self {
            case .general:
                return "General"
            case .advanced:
                return "Advanced"
            }
        }

        var iconName: String {
            switch self {
            case .general:
                return "gearshape"
            case .advanced:
                return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                settingsTabButton(for: .general)
                settingsTabButton(for: .advanced)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            ScrollView {
                VStack(spacing: 0) {
                    switch selectedTab {
                    case .general:
                        generalSettingsRows
                    case .advanced:
                        advancedSettingsRows
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
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsWindowPresentationConfigurator())
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    @ViewBuilder
    private var generalSettingsRows: some View {
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

        settingsFolderRow(
            title: "Snapshot Folder",
            description: "Where camera snapshots are saved.",
            path: state.settings.snapshotsFolder
        ) {
            chooseSnapshotsFolder()
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
    }

    @ViewBuilder
    private var advancedSettingsRows: some View {
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
    }

    @ViewBuilder
    private func settingsTabButton(for tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 15, weight: .semibold))
                Text(tab.title)
                    .font(.caption)
            }
            .frame(width: 86, height: 52)
            .contentShape(Rectangle())
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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

    private func chooseSnapshotsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.title = "Choose Snapshot Folder"
        panel.directoryURL = state.settings.snapshotsURL

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        state.settingsStore.update { settings in
            settings.snapshotsFolder = storagePath(from: folderURL)
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
        private var didBecomeKeyObserver: NSObjectProtocol?
        private var didBecomeMainObserver: NSObjectProtocol?
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
                        self?.handleWindowWillClose()
                    }
                    self.didBecomeKeyObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.didBecomeKeyNotification,
                        object: window,
                        queue: .main
                    ) { [weak self, weak window] _ in
                        guard let self, let window else { return }
                        self.ensureModalPresentation(for: window)
                    }
                    self.didBecomeMainObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.didBecomeMainNotification,
                        object: window,
                        queue: .main
                    ) { [weak self, weak window] _ in
                        guard let self, let window else { return }
                        self.ensureModalPresentation(for: window)
                    }
                }

                self.ensureModalPresentation(for: window)
            }
        }

        private func ensureModalPresentation(for window: NSWindow) {
            window.level = .modalPanel
            window.contentMinSize = NSSize(width: minimumWidth, height: 380)
            window.contentMaxSize = NSSize(width: maximumWidth, height: .greatestFiniteMagnitude)

            let currentWidth = window.contentLayoutRect.width
            let clampedWidth = min(max(currentWidth, minimumWidth), maximumWidth)
            if abs(currentWidth - clampedWidth) > 1 {
                window.setContentSize(
                    NSSize(
                        width: clampedWidth,
                        height: max(380, window.contentLayoutRect.height)
                    )
                )
            }

            guard !isModalRunning else { return }
            isModalRunning = true
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)

            DispatchQueue.main.async { [weak self, weak window] in
                guard let self else { return }
                guard let window, self.window === window else {
                    self.isModalRunning = false
                    return
                }
                NSApp.runModal(for: window)
                self.isModalRunning = false
            }
        }

        private func handleWindowWillClose() {
            if let window,
               NSApp.modalWindow === window {
                NSApp.stopModal()
            }
            isModalRunning = false
            window?.level = originalLevel
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
            if let didBecomeKeyObserver {
                NotificationCenter.default.removeObserver(didBecomeKeyObserver)
                self.didBecomeKeyObserver = nil
            }
            if let didBecomeMainObserver {
                NotificationCenter.default.removeObserver(didBecomeMainObserver)
                self.didBecomeMainObserver = nil
            }

            if let window {
                window.level = originalLevel
            }
            window = nil
        }
    }
}
