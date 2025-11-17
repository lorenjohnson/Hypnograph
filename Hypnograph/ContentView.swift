import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var viewModel: ViewModel
    @ObservedObject var renderQueue: RenderQueue

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Live multi-layer preview: selected layers + current candidate.
            MultiLayerPreviewView(
                layers: viewModel.previewLayers,
                currentLayerIndex: viewModel.currentLayerIndex,
                currentLayerTime: Binding(
                    get: { viewModel.currentCandidateStartOverride },
                    set: { viewModel.currentCandidateStartOverride = $0 }
                ),
                outputSize: viewModel.outputSize
            )
            .ignoresSafeArea()

            // HUD
            if viewModel.isHUDVisible {
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

                    Text("Layer \(viewModel.currentLayerIndex + 1) of \(viewModel.maxLayers)")
                        .font(.caption)

                    Text("Blend mode: \(viewModel.currentBlendModeName)")
                        .font(.caption)
                        .padding(.bottom, 16)

                    Text("Space = New Set")
                        .font(.caption)
                    Text("N = Next Candidate this layer")
                        .font(.caption)
                    Text("1-5 Next Candidate per layer X")
                        .font(.caption)
                    Text("Delete = Back a layer")
                        .font(.caption)
                    Text("Return = Accept Candidate")
                        .font(.caption)
                    Text("R = Render Hypnogram")
                        .font(.caption)
                    Text("M = Blend Mode")
                        .font(.caption)
                    Text("E = Toggle Global Effect")
                        .font(.caption)
                        .padding(.bottom, 16)

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
