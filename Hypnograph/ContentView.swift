import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var state: HypnogramState
    @ObservedObject var renderQueue: RenderQueue
    let mode: HypnographMode

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Mode-driven display: ContentView has no idea which concrete view this is.
            mode.makeDisplayView(state: state, renderQueue: renderQueue)
                // Respect the configured target size by constraining aspect ratio.
                .aspectRatio(
                    state.outputSize.width / max(state.outputSize.height, 1),
                    contentMode: .fit
                )
                .ignoresSafeArea()

            // HUD
            if state.isHUDVisible {
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

                    Text("Layer \(state.currentLayerIndex + 1) of \(state.maxLayers)")
                        .font(.caption)

                    Text("Blend mode: \(state.currentBlendModeName)")
                        .font(.caption)
                        .padding(.bottom, 16)

                    Text("N = Next Candidate this layer")
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

                    Text("Space = New random Hypnogram")
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
