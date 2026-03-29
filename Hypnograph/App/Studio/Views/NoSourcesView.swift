import SwiftUI
import HypnoCore

struct NoSourcesView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    @State private var isRequestingPhotos = false

    private var canReadPhotos: Bool { state.photosAuthorizationStatus.canRead }

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
                Button("Open Sources Window") {
                    main.windows.setWindowVisible("sourcesWindow", visible: true)
                }

                Button("Add Folder Source…") {
                    main.addFolderSourcesFromPanel()
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
            Task { @MainActor in
                let status = main.refreshPhotosStatus()
                if status.canRead {
                    await state.refreshPhotosLibrariesAfterAuthorization()
                }
            }
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
        "Photos authorization: \(String(describing: state.photosAuthorizationStatus))"
    }

    private func requestPhotosAccess() {
        isRequestingPhotos = true
        Task { @MainActor in
            _ = await main.requestPhotosAccess()
            isRequestingPhotos = false
        }
    }
}
