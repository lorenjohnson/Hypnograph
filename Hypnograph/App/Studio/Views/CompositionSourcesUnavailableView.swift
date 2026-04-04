import SwiftUI

struct CompositionSourcesUnavailableView: View {
    @ObservedObject var main: Studio

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Text("This composition couldn’t load its sources")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(messageText)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            HStack(spacing: 12) {
                Button("Try Again") {
                    main.retryCurrentCompositionLoad()
                }
                .buttonStyle(.borderedProminent)

                Button("Configure Sources") {
                    main.revealSourcesWindow()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var messageText: String {
        """
        Hypnograph couldn’t load any of the source media required for this composition.
        One or more files or folders may be missing or unavailable.
        """
    }
}
