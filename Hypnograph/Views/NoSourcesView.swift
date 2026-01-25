import SwiftUI
import AppKit
import HypnoCore

struct NoSourcesView: View {
    @ObservedObject var state: HypnographState

    @State private var isRequestingPhotos = false
    @State private var lastPhotosStatus: ApplePhotos.AuthorizationStatus = ApplePhotos.shared.status

    private var canReadPhotos: Bool { ApplePhotos.shared.status.canRead }

    var body: some View {
        VStack(spacing: 16) {
            Text("No media sources available")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            Text(messageText)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            HStack(spacing: 12) {
                Button("Add Folder Source…") {
                    addFolderSources()
                }

                Button(isRequestingPhotos ? "Requesting Photos Access…" : photosButtonTitle) {
                    requestPhotosAccess()
                }
                .disabled(isRequestingPhotos || canReadPhotos)

                Button("Show Settings Folder") {
                    Environment.showSettingsFolderInFinder()
                }
            }
            .buttonStyle(.borderedProminent)

            Text(statusFooter)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            ApplePhotos.shared.refreshStatus()
            lastPhotosStatus = ApplePhotos.shared.status
        }
    }

    private var messageText: String {
        """
        Hypnograph couldn’t find any usable media in your configured sources.
        Add a folder source, or allow access to Apple Photos.
        """
    }

    private var photosButtonTitle: String {
        canReadPhotos ? "Photos Access Enabled" : "Request Photos Access"
    }

    private var statusFooter: String {
        let status = ApplePhotos.shared.status
        return "Photos authorization: \(String(describing: status))"
    }

    private func requestPhotosAccess() {
        isRequestingPhotos = true
        Task { @MainActor in
            let status = await ApplePhotos.shared.requestAuthorization()
            ApplePhotos.shared.refreshStatus()
            lastPhotosStatus = status
            isRequestingPhotos = false

            if status.canRead {
                await state.activatePhotosAllIfAvailable()
                await state.refreshAvailableLibraries()
            }
        }
    }

    private func addFolderSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folder(s) to add as Hypnograph sources."

        let result = panel.runModal()
        guard result == .OK else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let selectedPaths: [String] = panel.urls.map { url in
            let p = url.path
            return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
        }

        state.settingsStore.update { settings in
            var libs = settings.sources.libraries
            var paths = libs["default"] ?? []
            for p in selectedPaths where !paths.contains(p) {
                paths.append(p)
            }
            libs["default"] = paths
            settings.sources = .dictionary(libs)

            if settings.activeLibraries.isEmpty {
                settings.activeLibraries = ["default"]
            }
        }

        Task { @MainActor in
            await state.rebuildLibrary()
            await state.refreshAvailableLibraries()
        }
    }
}

