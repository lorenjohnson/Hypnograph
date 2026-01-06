import SwiftUI
import PhotosUI

/// Wraps PHPickerViewController to support preselected assets
struct PhotosPickerSheet: View {
    @Binding var isPresented: Bool
    let preselectedIdentifiers: [String]
    let onSelection: ([String]) -> Void

    var body: some View {
        PHPickerRepresentable(
            preselectedIdentifiers: preselectedIdentifiers,
            onSelection: { identifiers in
                onSelection(identifiers)
                isPresented = false
            }
        )
        .frame(minWidth: 800, idealWidth: 900, minHeight: 600, idealHeight: 700)
        .background(WindowResizer())
    }
}

/// Makes the sheet window resizable by finding and modifying its NSWindow
struct WindowResizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        tryMakeResizable(view: view, attempts: 10)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func tryMakeResizable(view: NSView, attempts: Int) {
        guard attempts > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let window = view.window {
                window.styleMask.insert(.resizable)
                window.minSize = NSSize(width: 600, height: 400)
            } else {
                tryMakeResizable(view: view, attempts: attempts - 1)
            }
        }
    }
}

/// The actual PHPickerViewController wrapper
struct PHPickerRepresentable: NSViewControllerRepresentable {
    let preselectedIdentifiers: [String]
    let onSelection: ([String]) -> Void

    func makeNSViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0
        config.filter = .any(of: [.images, .videos])
        config.preselectedAssetIdentifiers = preselectedIdentifiers

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateNSViewController(_ nsViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onSelection: ([String]) -> Void

        init(onSelection: @escaping ([String]) -> Void) {
            self.onSelection = onSelection
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let identifiers = results.compactMap { $0.assetIdentifier }
            onSelection(identifiers)
        }
    }
}
