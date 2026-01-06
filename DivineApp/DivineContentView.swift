import SwiftUI
import HypnoCore
import HypnoAppShell

struct DivineContentView: View {
    @ObservedObject var state: DivineState
    @ObservedObject var divine: Divine

    var body: some View {
        divine.makeDisplayView()
            .ignoresSafeArea()
            .appNotifications()
            .background(Color.black)
            .sheet(isPresented: $state.showPhotosPicker) {
                PhotosPickerSheet(
                    isPresented: $state.showPhotosPicker,
                    preselectedIdentifiers: state.customPhotosAssetIds,
                    onSelection: { identifiers in
                        state.setCustomPhotosAssets(identifiers)
                        if identifiers.isEmpty {
                            AppNotifications.shared.show("Custom Selection cleared", flash: true)
                        } else {
                            if !state.isLibraryActive(key: ApplePhotosLibraryKeys.photosCustom) {
                                state.toggleLibrary(key: ApplePhotosLibraryKeys.photosCustom)
                            }
                            AppNotifications.shared.show("Custom Selection: \(identifiers.count) items", flash: true)
                        }
                    }
                )
            }
    }
}
