import SwiftUI
import HypnoCore

struct PhotosAccessRequiredView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.04, green: 0.04, blue: 0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))

                    VStack(spacing: 10) {
                        Text("Apple Photos Access Denied")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("This composition uses Apple Photos as one of its sources.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    ApplePhotosAccessStatusView(
                        authorizationStatus: state.photosAuthorizationStatus,
                        presentation: .prominent,
                        showsStatusLine: false,
                        contentAlignment: .centered,
                        onRequestAccess: requestPhotosAccess,
                        onOpenSystemSettings: main.openApplePhotosPrivacySettings
                    )
                }
                .frame(maxWidth: min(620, max(320, proxy.size.width - 64)))
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
        }
    }

    private func requestPhotosAccess() {
        Task { @MainActor in
            _ = await main.requestPhotosAccess()
        }
    }
}
