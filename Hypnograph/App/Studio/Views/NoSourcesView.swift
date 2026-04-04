import SwiftUI
import HypnoCore

struct NoSourcesView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

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
                Button("Configure Sources") {
                    main.revealSourcesWindow()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var messageText: String {
        return """
        Hypnograph couldn’t find any usable media in your configured sources.
        Configure one or more folder or Apple Photos sources to begin playback.
        """
    }
}
