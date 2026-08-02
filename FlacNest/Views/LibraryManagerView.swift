import AppKit
import SwiftUI

struct LibraryManagerView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @EnvironmentObject private var playerWindowTracker: PlayerWindowTracker
    @EnvironmentObject private var barcodeEject: BarcodeEjectController
    @State private var editingAlbum: LibraryAlbum?
    @State private var selectedAlbumID: String?

    private var selectedAlbum: LibraryAlbum? {
        guard let id = selectedAlbumID else { return nil }
        return libraryVM.library.albums.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            libraryList
            if !playerWindowTracker.isOpen {
                Divider()
                playerStrip
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .toolbar {
            ToolbarItemGroup {
                sortGroupMenu

                if libraryVM.isScanning {
                    Button("Cancel Scan") {
                        libraryVM.cancelScan()
                    }
                } else {
                    Button {
                        libraryVM.refreshLibrary()
                    } label: {
                        Label("Refresh Library", systemImage: "arrow.clockwise")
                    }
                    .disabled(AppSettings.libraryRootURL == nil)
                }
            }
        }
        .sheet(item: $editingAlbum) { album in
            AlbumMetadataEditorView(album: album)
                .environmentObject(libraryVM)
                .environmentObject(playback)
        }
        .flacNestFocusedCommands(
            playback: playback,
            libraryVM: libraryVM,
            onEditMetadata: {
                if let album = selectedAlbum {
                    editingAlbum = album
                }
            }
        )
        .onChange(of: selectedAlbumID) { _, newValue in
            libraryVM.selectedAlbumID = newValue
        }
        .onAppear {
            libraryVM.loadFromDisk()
            playerWindowTracker.refresh()
        }
        .barcodeEjectSheet()
    }

    private var libraryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if libraryVM.isScanning {
                scanProgressView
            } else if let message = libraryVM.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(libraryVM.displayedSections) { section in
                            if libraryVM.groupMode == .none {
                                ForEach(section.albums) { album in
                                    albumListRow(album)
                                        .id(album.id)
                                }
                            } else {
                                Section {
                                    ForEach(section.albums) { album in
                                        albumListRow(album)
                                            .id(album.id)
                                    }
                                } header: {
                                    sectionHeader(section.title)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    focusPlayingAlbum(using: scrollProxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                    guard let window = notification.object as? NSWindow,
                          PlayerWindowSizing.isLibraryWindow(window) else { return }
                    focusPlayingAlbum(using: scrollProxy)
                }
                .onChange(of: playback.currentAlbum?.id) { _, albumID in
                    guard albumID != nil else { return }
                    focusPlayingAlbum(using: scrollProxy)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!libraryVM.isScanning)

            HStack {
                Button("Play Selected") {
                    if let album = selectedAlbum {
                        beginPlayback(for: album)
                    }
                }
                .disabled(selectedAlbum == nil || libraryVM.isScanning)

                Button("Edit Metadata…") {
                    if let album = selectedAlbum {
                        editingAlbum = album
                    }
                }
                .disabled(selectedAlbum == nil || libraryVM.isScanning)

                Spacer()
            }
            .padding(12)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(.bar)
    }

    private var sortGroupMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(LibrarySortMode.allCases) { mode in
                    Button {
                        libraryVM.setSortMode(mode)
                    } label: {
                        if libraryVM.sortMode == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            }

            Section("Group By") {
                ForEach(LibraryGroupMode.allCases) { mode in
                    Button {
                        libraryVM.setGroupMode(mode)
                    } label: {
                        if libraryVM.groupMode == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            }
        } label: {
            Label("Sort & Group", systemImage: "arrow.up.arrow.down.circle")
        }
        .disabled(libraryVM.isScanning)
        .help("Sort and group albums in the library list")
    }

    private func albumListRow(_ album: LibraryAlbum) -> some View {
        albumRow(album)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(for: album))
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded { beginPlayback(for: album) }
                    .exclusively(before: TapGesture(count: 1).onEnded {
                        selectedAlbumID = album.id
                    })
            )
            .contextMenu {
                Button("Play") { beginPlayback(for: album) }
                Button("Edit Metadata…") { editingAlbum = album }
            }
    }

    private func rowBackground(for album: LibraryAlbum) -> some View {
        let isSelected = selectedAlbumID == album.id
        let isPlayingAlbum = playback.currentAlbum?.id == album.id

        return ZStack {
            if isPlayingAlbum {
                Color.accentColor.opacity(0.12)
            }
            if isSelected {
                Color.accentColor.opacity(0.22)
            }
        }
    }

    private func albumRow(_ album: LibraryAlbum) -> some View {
        HStack(alignment: .center, spacing: 10) {
            albumArtwork(for: album)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Text(album.performer)
                    if let date = album.date, !date.isEmpty {
                        Text("·")
                        Text(date)
                    }
                    Text("·")
                    Text("\(album.tracks.count) tracks")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if playback.currentAlbum?.id == album.id {
                Image(systemName: playback.isPlaying ? "speaker.wave.2.fill" : "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func albumArtwork(for album: LibraryAlbum) -> some View {
        Group {
            if let url = libraryVM.artworkURL(for: album), let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .highQualityScaled(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.2))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var scanProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(libraryVM.scanProgress.title)
                    .font(.subheadline)
                Spacer()
                if libraryVM.scanProgress.phase == .processing, libraryVM.scanProgress.total > 0 {
                    Text(libraryVM.scanProgress.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if libraryVM.scanProgress.phase == .processing, libraryVM.scanProgress.total > 0 {
                ProgressView(value: libraryVM.scanProgress.fractionCompleted)
            } else {
                ProgressView()
            }

            if !libraryVM.scanProgress.currentItem.isEmpty {
                Text(libraryVM.scanProgress.currentItem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let message = libraryVM.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private var playerStrip: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                NowPlayingMetadataView(
                    album: playback.currentAlbum,
                    track: playback.currentTrack,
                    artworkURL: playback.currentAlbum.flatMap { libraryVM.artworkURL(for: $0) },
                    isPlaying: playback.isPlaying
                )
                PlaybackProgressView(playback: playback)
                TransportControls(playback: playback) {
                    barcodeEject.presentEject()
                }
            }
            .padding(16)

            Button {
                PlayerWindowSizing.detach(openWindow: openWindow, tracker: playerWindowTracker)
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.borderless)
            .help("Detach Player")
            .padding(12)
        }
        .background(.bar)
    }

    private func beginPlayback(for album: LibraryAlbum) {
        selectedAlbumID = album.id
        playback.load(album: album)
        playback.play()
    }

    private func focusPlayingAlbum(using scrollProxy: ScrollViewProxy) {
        guard let playingAlbumID = playback.currentAlbum?.id else { return }
        selectedAlbumID = playingAlbumID
        libraryVM.selectedAlbumID = playingAlbumID
        DispatchQueue.main.async {
            withAnimation {
                scrollProxy.scrollTo(playingAlbumID, anchor: .center)
            }
        }
    }
}
