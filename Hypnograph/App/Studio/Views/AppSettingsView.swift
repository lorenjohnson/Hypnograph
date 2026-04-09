import SwiftUI
import AppKit
import HypnoCore

struct AppSettingsView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio
    @ObservedObject private var settingsStore: StudioSettingsStore
    @StateObject private var audioManager = AudioDeviceManager.shared
    @State private var selectedTab: SettingsTab = .general

    init(state: HypnographState, main: Studio) {
        self.state = state
        self.main = main
        _settingsStore = ObservedObject(initialValue: state.settingsStore)
    }

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
        settingsDeviceRow(
            title: "Audio Output Device",
            description: "Select the audio output device.",
            selection: Binding(
                get: { main.audioDevice },
                set: { main.audioDevice = $0 }
            )
        )

        if settingsStore.value.liveModeEnabled {
            Divider()

            settingsDeviceRow(
                title: "Audio Output Device (Live)",
                description: "Select the audio output device used when sending audio to Live.",
                selection: Binding(
                    get: { main.liveAudioDevice },
                    set: { main.liveAudioDevice = $0 }
                )
            )
        }
        Divider()

        settingsActionRow(
            title: "Show Settings Folder",
            description: "Opens your Hypnograph settings directory in Finder.",
            buttonTitle: "Show"
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

        settingsRenderDestinationRow(
            title: "Rendered Video Destination",
            description: "Choose disk, Photos, or both. Will fall back to disk when Photos write access is unavailable.",
            selection: Binding(
                get: { settingsStore.value.renderVideoSaveDestination },
                set: { newValue in
                    settingsStore.update { $0.renderVideoSaveDestination = newValue }
                }
            )
        )
        Divider()

        settingsFolderRow(
            title: "Render Output Folder",
            description: "Where rendered videos are saved.",
            path: settingsStore.value.outputFolder
        ) {
            main.chooseOutputFolder()
        }
        Divider()

        settingsFolderRow(
            title: "Snapshot Folder",
            description: "Where camera snapshots are saved.",
            path: settingsStore.value.snapshotsFolder
        ) {
            main.chooseSnapshotsFolder()
        }
        Divider()

        settingsActionRow(
            title: "Clear Sequence",
            description: "Removes all previous compositions from the current sequence and keeps your current composition selected.",
            buttonTitle: "Clear",
            isDestructive: true
        ) {
            main.resetDefaultHypnogram()
        }
        Divider()

        settingsStepperRow(
            title: "History Limit",
            description: "Max compositions in history.",
            value: Binding(
                get: { max(1, settingsStore.value.historyLimit) },
                set: { newValue in
                    settingsStore.update { $0.historyLimit = max(1, newValue) }
                }
            ),
            range: 1...5000
        )
    }

    @ViewBuilder
    private var advancedSettingsRows: some View {
        settingsToggleRow(
            title: "Live/Performance mode options",
            description: "Enables controls for the live panel, live mode, and external monitor output.",
            isOn: Binding(
                get: { settingsStore.value.liveModeEnabled },
                set: { newValue in
                    settingsStore.update { $0.liveModeEnabled = newValue }
                }
            )
        )
        Divider()

        settingsToggleRow(
            title: "Enable Effects Composer",
            description: "Shows the Effects Composer command and allows opening the Effects Composer window.",
            isOn: Binding(
                get: { settingsStore.value.effectsComposerEnabled },
                set: { newValue in
                    settingsStore.update { $0.effectsComposerEnabled = newValue }
                }
            )
        )
        Divider()

        settingsToggleRow(
            title: "Override Global Keyboard Controls",
            description: "When enabled, Hypnograph uses direct keyboard controls like Space for Play/Pause and Tab for panel toggle, and suppresses default keyboard focus navigation highlights in Studio panels.",
            isOn: Binding(
                get: { settingsStore.value.keyboardAccessibilityOverridesEnabled },
                set: { newValue in
                    settingsStore.update { $0.keyboardAccessibilityOverridesEnabled = newValue }
                }
            )
        )

        #if DEBUG
        Divider()

        settingsActionRow(
            title: "Reset Debug State and Quit",
            description: "Clears the Hypnograph-Debug application support directory, resets Apple Photos permission for Hypnograph, and then quits. The reset happens on the next debug launch before normal bootstrap.",
            buttonTitle: "Reset",
            isDestructive: true
        ) {
            Environment.queueDebugResetAndQuit()
        }
        #endif
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
            PanelToggleView(isOn: isOn)
                .fixedSize()
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
                Text(PathFormatting.displayPath(path))
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

    @ViewBuilder
    private func settingsRenderDestinationRow(
        title: String,
        description: String,
        selection: Binding<RenderVideoSaveDestination>
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            Picker("", selection: selection) {
                ForEach(RenderVideoSaveDestination.allCases, id: \.self) { destination in
                    Text(destination.displayName).tag(destination)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 240, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

}

private extension RenderVideoSaveDestination {
    var displayName: String {
        switch self {
        case .diskAndPhotosIfAvailable:
            return "Disk + Apple Photos"
        case .photosIfAvailableOtherwiseDisk:
            return "Apple Photos only"
        case .diskOnly:
            return "Disk only"
        }
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

                // Keep settings chrome minimal and make this panel visually modal.
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
