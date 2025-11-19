import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var session: HypnogramState
    @ObservedObject var renderQueue: RenderQueue

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Live multi-layer preview: AVFoundation + custom compositor.
            MontagePreviewView(
                layers: session.layersForPreview(),
                currentLayerIndex: session.currentLayer,
                currentLayerTime: Binding(
                    get: { session.currentCandidateStartOverride },
                    set: { session.currentCandidateStartOverride = $0 }
                ),
                outputSize: session.outputSize,
                outputDuration: session.outputDuration
            )
            // Respect the configured target size by constraining aspect ratio.
            .aspectRatio(
                session.outputSize.width / max(session.outputSize.height, 1),
                contentMode: .fit
            )
            .ignoresSafeArea()

            // HUD
            if session.isHUDVisible {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hypnograph")
                        .font(.headline)
                        .padding(.bottom, 8)

                    if renderQueue.activeJobs > 0 {
                        Text("Queue: \(renderQueue.activeJobs)")
                            .font(.subheadline)
                            .padding(.bottom, 8)
                    } else {
                        Text("Queue: 0")
                            .font(.caption)
                            .padding(.bottom, 8)
                    }

                    Text("Layer \(session.currentLayer + 1) of \(session.maxLayers)")
                        .font(.caption)

                    Text("Blend mode: \(session.currentBlendModeName)")
                        .font(.caption)
                        .padding(.bottom, 16)

                    Text("Space = Next Candidate this layer")
                        .font(.caption)
                    Text("Return = Accept Candidate")
                        .font(.caption)
                    Text("Delete = Delete current layer")
                        .font(.caption)
                    Text("1-5 Switch to layer")
                        .font(.caption)
                    Text("M = Blend Mode")
                        .font(.caption)
                        .padding(.bottom, 16)

                    Text("Cmd-N = New random Hypnogram")
                        .font(.caption)
                    Text("Cmd-S = Save Hypnogram")
                        .font(.caption)
                    Text("Cmd-R = Reload Settings and Restart")
                        .font(.caption)
                    Text("Shift-Cmd-S = Show Settings Folder")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding()
            }
        }
        // extra safety: whole scene black
        .background(Color.black)
    }
}
