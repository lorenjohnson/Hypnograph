import SwiftUI
import HypnoCore

struct SourcesWindowView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    @State private var isRequestingPhotos = false

    private struct FolderLibraryRow: Identifiable {
        let key: String
        let displayName: String
        let paths: [String]
        let assetCount: Int

        var id: String { key }
    }

    private var folderAssetCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: state.availableLibraries.map { ($0.id, $0.assetCount) })
    }

    private var folderLibraryRows: [FolderLibraryRow] {
        state.settings.sourceLibraryOrder.compactMap { key in
            guard let paths = state.settings.sourceLibraries[key] else { return nil }

            let displayName: String
            if key == "default", let firstPath = paths.first {
                displayName = URL(fileURLWithPath: (firstPath as NSString).expandingTildeInPath).lastPathComponent
            } else {
                displayName = key
            }

            return FolderLibraryRow(
                key: key,
                displayName: displayName,
                paths: paths,
                assetCount: folderAssetCounts[key] ?? 0
            )
        }
    }

    private var photosLibraries: [SourceLibraryInfo] {
        state.availableLibraries.filter { $0.type == .applePhotos }
    }

    private var canReadPhotos: Bool {
        main.photosAuthorizationStatus.canRead
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                sectionTitle("Sources")

                Text("Manage the media pool used for random clip generation, and keep source setup out of the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                mediaTypesSection
                folderLibrariesSection
                photosSection
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            Color.black.opacity(0.96)
                .ignoresSafeArea()
        )
        .onAppear {
            Task {
                await state.refreshAvailableLibraries()
            }
        }
    }

    private var mediaTypesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionDivider()
            sectionTitle("Media Types")

            HStack(spacing: 16) {
                Toggle("Images", isOn: Binding(
                    get: { state.isMediaTypeActive(.images) },
                    set: { _ in state.toggleMediaType(.images) }
                ))

                Toggle("Videos", isOn: Binding(
                    get: { state.isMediaTypeActive(.videos) },
                    set: { _ in state.toggleMediaType(.videos) }
                ))
            }

            Text("Current eligible pool: \(state.library.assetCount) item\(state.library.assetCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var folderLibrariesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionDivider()
            HStack(alignment: .center, spacing: 8) {
                sectionTitle("File & Folder Sources")
                Spacer(minLength: 8)

                Button {
                    main.addSourceLibrariesFromPanel()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Add Files or Folders")
            }

            if folderLibraryRows.isEmpty {
                emptyState("No file or folder sources configured yet.")
            } else {
                ForEach(folderLibraryRows) { row in
                    folderLibraryRow(row)
                }
            }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionDivider()
            HStack(alignment: .center, spacing: 8) {
                sectionTitle("Apple Photos")
                Spacer(minLength: 8)

                Button {
                    state.showPhotosPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(!canReadPhotos)
                .help("Pick Custom Photos")
            }

            if canReadPhotos {
                if let allItems = photosLibraries.first(where: { $0.id == ApplePhotosLibraryKeys.photosAll }) {
                    sourceToggleRow(
                        title: allItems.name,
                        trailingText: "\(allItems.assetCount)",
                        isOn: Binding(
                            get: { state.isLibraryActive(key: allItems.id) },
                            set: { _ in state.toggleLibrary(key: allItems.id) }
                        )
                    )
                }

                customPhotosRow

                ForEach(photosLibraries.filter { $0.id != ApplePhotosLibraryKeys.photosAll && $0.id != ApplePhotosLibraryKeys.photosCustom }) { library in
                    sourceToggleRow(
                        title: library.name,
                        trailingText: "\(library.assetCount)",
                        isOn: Binding(
                            get: { state.isLibraryActive(key: library.id) },
                            set: { _ in state.toggleLibrary(key: library.id) }
                        )
                    )
                }

                if photosLibraries.isEmpty {
                    emptyState("No Photos scopes available yet.")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Photos access is not enabled.")
                        .foregroundStyle(.secondary)

                    Button(isRequestingPhotos ? "Requesting Photos Access…" : "Request Photos Access") {
                        requestPhotosAccess()
                    }
                    .disabled(isRequestingPhotos)
                }
            }
        }
    }

    private func folderLibraryRow(_ row: FolderLibraryRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { state.isLibraryActive(key: row.key) },
                set: { _ in state.toggleLibrary(key: row.key) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(row.displayName)
                    .font(.body.weight(.medium))

                Text(row.paths.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Text("\(row.assetCount) eligible item\(row.assetCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                main.removeFolderLibrary(row.key)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove folder library")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var customPhotosRow: some View {
        let count = state.customPhotosAssetIds.count
        let isActive = state.isLibraryActive(key: ApplePhotosLibraryKeys.photosCustom)
        let trailingText = count > 0 ? "\(count)" : "Edit"

        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isActive },
                set: { newValue in
                    if newValue {
                        state.showPhotosPicker = true
                    } else {
                        state.toggleLibrary(key: ApplePhotosLibraryKeys.photosCustom)
                    }
                }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text("Custom Selection")
                    .font(.body.weight(.medium))
            }

            Spacer(minLength: 8)

            Button(trailingText) {
                state.showPhotosPicker = true
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func sourceToggleRow(title: String, trailingText: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: isOn)
                .labelsHidden()

            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(trailingText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func requestPhotosAccess() {
        isRequestingPhotos = true
        Task { @MainActor in
            _ = await main.requestPhotosAccess()
            isRequestingPhotos = false
        }
    }

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sectionDivider() -> some View {
        GlassDivider()
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
            )
    }
}
