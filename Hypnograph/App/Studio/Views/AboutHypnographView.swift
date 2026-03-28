import SwiftUI
import AppKit

struct AboutHypnographView: View {
    private var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(shortVersion) (\(build))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 10) {
                Text("Hypnograph")
                    .font(.title.weight(.semibold))

                Text("Version \(versionText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("An app to wander your own media archive with less friction and more curiosity, surfacing unexpected patterns and emotional links so the past can be integrated and the present can feel clearer, wiser, and more open. It also offers a visual language for sharing that evolving story as it emerges, dream-like, over time.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Authored by Loren Johnson")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 720, height: 245, alignment: .topLeading)
    }
}
