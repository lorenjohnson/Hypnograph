import SwiftUI
import HypnoCore

struct ApplePhotosAccessStatusView: View {
    enum Presentation {
        case inline
        case prominent
    }

    enum ContentAlignment {
        case leading
        case centered
    }

    let authorizationStatus: ApplePhotos.AuthorizationStatus
    var isRequestingPhotos: Bool = false
    var presentation: Presentation = .inline
    var showsAction: Bool = true
    var showsStatusLine: Bool = true
    var contentAlignment: ContentAlignment = .leading
    let onRequestAccess: () -> Void
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: stackAlignment, spacing: presentation == .prominent ? 10 : 6) {
            if showsStatusLine {
                Text(statusLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .multilineTextAlignment(textAlignment)
            }

            Text(message)
                .font(presentation == .prominent ? .body : .callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .multilineTextAlignment(textAlignment)

            if showsAction {
                HStack {
                    if contentAlignment == .centered {
                        Spacer(minLength: 0)
                    }

                    Button {
                        if authorizationStatus == .notDetermined {
                            onRequestAccess()
                        } else {
                            onOpenSystemSettings()
                        }
                    } label: {
                        if authorizationStatus == .notDetermined || isRequestingPhotos {
                            Text(isRequestingPhotos ? "Requesting Photos Access…" : actionTitle)
                        } else {
                            Label(actionTitle, systemImage: "gearshape")
                        }
                    }
                    .disabled(isRequestingPhotos)
                    .buttonStyle(.borderedProminent)
                    .controlSize(presentation == .prominent ? .regular : .small)

                    if contentAlignment == .centered {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, presentation == .prominent ? 6 : 2)
            }
        }
    }

    private var statusLine: String {
        switch authorizationStatus {
        case .authorized:
            return "Access is currently allowed."
        case .limited:
            return "Access is currently limited."
        case .denied:
            return "Access is currently denied."
        case .restricted:
            return "Access is currently restricted."
        case .notDetermined:
            return "Access has not been requested yet."
        }
    }

    private var message: String {
        switch authorizationStatus {
        case .authorized:
            return "Apple Photos access is available."
        case .limited:
            return "To manage or expand Apple Photos access, open System Settings and review Hypnograph in the Privacy & Security > Photos section."
        case .denied:
            return "To re-enable Apple Photos access, open System Settings, go to Privacy & Security, find Hypnograph, and allow access. You’ll need to restart the application."
        case .restricted:
            return "Apple Photos access is restricted by the system. Open System Settings to review whether it can be changed for Hypnograph."
        case .notDetermined:
            return "Request access here if you want to use your Photos library as a source."
        }
    }

    private var statusColor: Color {
        switch authorizationStatus {
        case .denied:
            return .red
        default:
            return .secondary
        }
    }

    private var actionTitle: String {
        authorizationStatus == .notDetermined ? "Request Photos Access" : "Open System Settings"
    }

    private var stackAlignment: HorizontalAlignment {
        contentAlignment == .centered ? .center : .leading
    }

    private var frameAlignment: Alignment {
        contentAlignment == .centered ? .center : .leading
    }

    private var textAlignment: TextAlignment {
        contentAlignment == .centered ? .center : .leading
    }
}
