import SwiftUI

struct MobileLibraryView: View {
    @Environment(MobileLibraryStore.self) private var libraryStore
    var usesSplitSelection: Bool
    var onOpenSettings: (() -> Void)?

    var body: some View {
        @Bindable var libraryStore = libraryStore

        Group {
            if libraryStore.isLoadingLibrary && libraryStore.package == nil {
                loadingState
            } else if libraryStore.package == nil {
                emptyState
            } else {
                libraryContent
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Sort", selection: $libraryStore.sortMode) {
                        ForEach(LibrarySortMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Picker("Group", selection: $libraryStore.groupMode) {
                        ForEach(PortableLibraryGroupMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Toggle("Favorites only", isOn: $libraryStore.showFavoritesOnly)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading library…")
                .font(.subheadline)
                .mobileSecondaryForeground()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mobileThemedScreenBackground()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Library Loaded", systemImage: "folder")
        } description: {
            Text("Copy the export folder from your Mac via USB into the app Documents folder, or choose a library folder in Settings.")
        } actions: {
            if let onOpenSettings {
                Button("Open Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .mobileThemedScreenBackground()
    }

    private var libraryContent: some View {
        List {
            if let status = libraryStore.statusMessage {
                Text(status)
                    .font(.caption)
                    .mobileSecondaryForeground()
            }

            if let error = libraryStore.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(libraryStore.displayedSections) { section in
                if !section.title.isEmpty {
                    Section(section.title) {
                        albumRows(section.albums)
                    }
                } else {
                    albumRows(section.albums)
                }
            }
        }
        .mobileThemedListSurface()
        .navigationDestination(for: String.self) { albumID in
            if let album = libraryStore.package?.albums.first(where: { $0.id == albumID }) {
                MobileAlbumDetailView(album: album)
            }
        }
    }

    @ViewBuilder
    private func albumRows(_ albums: [MobileLibraryAlbum]) -> some View {
        ForEach(albums) { album in
            if usesSplitSelection {
                Button {
                    libraryStore.openAlbum(album)
                } label: {
                    MobileAlbumRow(album: album, isSelected: libraryStore.selectedAlbumID == album.id)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: album.id) {
                    MobileAlbumRow(album: album, isSelected: libraryStore.selectedAlbumID == album.id)
                }
            }
        }
    }
}

private struct MobileAlbumRow: View {
    @Environment(MobileLibraryStore.self) private var libraryStore
    let album: MobileLibraryAlbum
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            MobileArtworkThumbnail(url: libraryStore.artworkURL(for: album), size: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(album.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    if album.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(album.sortArtist)
                    .font(.subheadline)
                    .mobileSecondaryForeground()
                    .lineLimit(1)
                Text("\(album.tracks.count) tracks")
                    .font(.caption)
                    .mobileSecondaryForeground()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.14) : nil)
    }
}

struct MobileArtworkThumbnail: View {
    let url: URL?
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .mobileSecondaryForeground()
            }
        }
        .frame(width: size, height: size)
        .mobileThemedPlaceholderSurface(cornerRadius: cornerRadius)
        .task(id: url?.path) {
            guard let url else {
                image = nil
                return
            }
            image = await Task.detached(priority: .utility) {
                MobileArtworkImageCache.image(for: url, maxPixelSize: max(size * 2, 96))
            }.value
        }
    }
}
