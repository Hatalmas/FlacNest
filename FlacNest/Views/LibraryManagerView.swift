import AppKit
import SwiftUI

struct LibraryManagerView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(PlaybackController.self) private var playback
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @EnvironmentObject private var playerWindowTracker: PlayerWindowTracker
    @EnvironmentObject private var barcodeEject: BarcodeEjectController
    @AppStorage(AppSettings.libraryMetadataPreviewVisibleKey) private var showInspector = false
    @AppStorage(LibraryViewMode.storageKey) private var viewMode: LibraryViewMode = .grid
    @State private var editingAlbum: LibraryAlbum?
    @State private var albumPendingRemoval: LibraryAlbum?
    @State private var selectedAlbumID: String?
    @State private var sidebarFilter: LibrarySidebarFilter = .allAlbums
    @State private var scrollTarget: String?
    @State private var gridColumnCount = 1
    @FocusState private var contentFocused: Bool

    private var selectedAlbum: LibraryAlbum? {
        guard let id = selectedAlbumID else { return nil }
        return libraryVM.library.albums.first { $0.id == id }
    }

    private var sections: [LibraryAlbumSection] {
        libraryVM.filteredDisplayedSections
    }

    private var displayedAlbums: [LibraryAlbum] {
        sections.flatMap(\.albums)
    }

    private var albumCountSubtitle: String {
        let count = displayedAlbums.count
        let noun = count == 1 ? "album" : "albums"
        if libraryVM.filterText.isEmpty {
            return "\(count) \(noun)"
        }
        return "\(count) \(noun) matching “\(libraryVM.filterText)”"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            libraryContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !playerWindowTracker.isOpen {
                        LibraryNowPlayingBar(
                            playback: playback,
                            artworkURL: playback.currentAlbum.flatMap { libraryVM.artworkURL(for: $0) },
                            onReveal: revealPlayingAlbum,
                            onOpenPlayer: {
                                PlayerWindowSizing.detach(openWindow: openWindow, tracker: playerWindowTracker)
                            }
                        )
                    }
                }
                .navigationSubtitle(albumCountSubtitle)
                .searchable(
                    text: $libraryVM.filterText,
                    placement: .toolbar,
                    prompt: "Albums, artists, or tracks"
                )
                .toolbar { toolbarContent }
                .inspector(isPresented: $showInspector) {
                    AlbumMetadataPreviewView(
                        album: selectedAlbum,
                        onEdit: { album in editingAlbum = album }
                    )
                    .inspectorColumnWidth(
                        min: NestMacMetrics.inspectorMinWidth,
                        ideal: NestMacMetrics.inspectorIdealWidth,
                        max: NestMacMetrics.inspectorMaxWidth
                    )
                }
                .nestMacWindowChrome()
        }
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: sidebarFilter) { _, filter in
            libraryVM.setShowFavoritesOnly(filter == .favorites)
        }
        .onChange(of: libraryVM.showFavoritesOnly) { _, showFavorites in
            sidebarFilter = showFavorites ? .favorites : .allAlbums
        }
        .onAppear {
            sidebarFilter = libraryVM.showFavoritesOnly ? .favorites : .allAlbums
            playerWindowTracker.refresh()
            contentFocused = true
            if selectedAlbumID == nil {
                revealPlayingAlbum()
            }
        }
        .onChange(of: playback.currentAlbum?.id) { previousID, albumID in
            guard albumID != nil, selectedAlbumID == nil || selectedAlbumID == previousID else { return }
            revealPlayingAlbum()
        }
        .onChange(of: selectedAlbumID) { _, newValue in
            libraryVM.selectedAlbumID = newValue
        }
        .sheet(item: $editingAlbum) { album in
            NavigationStack {
                AlbumMetadataEditorView(album: album)
                    .environmentObject(libraryVM)
                    .environment(playback)
            }
        }
        .confirmationDialog(
            "Remove “\(albumPendingRemoval?.displayTitle ?? "")” from the library?",
            isPresented: Binding(
                get: { albumPendingRemoval != nil },
                set: { if !$0 { albumPendingRemoval = nil } }
            ),
            presenting: albumPendingRemoval
        ) { album in
            Button("Remove from Library", role: .destructive) {
                removeAlbum(album)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The album’s files stay on disk. Refresh or scan the folder to add it again.")
        }
        .flacNestFocusedCommands(
            playback: playback,
            libraryVM: libraryVM,
            onEditMetadata: {
                if let album = selectedAlbum {
                    editingAlbum = album
                }
            },
            onEject: { barcodeEject.presentEject() }
        )
        .barcodeEjectSheet()
        .background(MainWindowLifecycleMonitor())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarFilter) {
            Section("Library") {
                ForEach(LibrarySidebarFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .badge(albumCount(for: filter))
                        .tag(filter)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarStatus
        }
        .navigationSplitViewColumnWidth(
            min: NestMacMetrics.sidebarMinWidth,
            ideal: NestMacMetrics.sidebarIdealWidth,
            max: 260
        )
    }

    @ViewBuilder
    private var sidebarStatus: some View {
        if libraryVM.isScanning {
            VStack(alignment: .leading, spacing: 6) {
                Text(libraryVM.scanProgress.title)
                    .font(.caption.weight(.medium))
                    .nestPrimaryForeground()
                if libraryVM.scanProgress.total > 0 {
                    ProgressView(value: libraryVM.scanProgress.fractionCompleted)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let message = libraryVM.statusMessage, !libraryVM.isLibraryBusy {
            Text(message)
                .font(.caption)
                .nestSecondaryForeground()
                .lineLimit(3)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func albumCount(for filter: LibrarySidebarFilter) -> Int {
        switch filter {
        case .allAlbums:
            return libraryVM.library.albums.count
        case .favorites:
            return libraryVM.library.albums.reduce(0) { $0 + ($1.isFavorite ? 1 : 0) }
        }
    }

    // MARK: - Content

    private var libraryContent: some View {
        Group {
            if displayedAlbums.isEmpty && !libraryVM.isLibraryBusy {
                libraryEmptyState
            } else {
                switch viewMode {
                case .grid: albumGrid
                case .list: albumList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(!libraryVM.isLibraryBusy)
        .overlay {
            if libraryVM.isLibraryBusy {
                LibraryBusyOverlay(
                    isScanning: libraryVM.isScanning,
                    isPreparingLibraryUI: libraryVM.isPreparingLibraryUI,
                    scanProgress: libraryVM.scanProgress,
                    statusMessage: libraryVM.statusMessage
                )
            }
        }
        .onDeleteCommand {
            if let album = selectedAlbum, !libraryVM.isLibraryBusy {
                albumPendingRemoval = album
            }
        }
    }

    private var albumList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedAlbumID) {
                ForEach(sections) { section in
                    if libraryVM.groupMode == .none {
                        listRows(for: section.albums)
                    } else {
                        Section(section.title) {
                            listRows(for: section.albums)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .nestThemedScrollSurface()
            .focused($contentFocused)
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let album = album(withID: id) {
                    albumMenu(for: album)
                }
            } primaryAction: { ids in
                if let id = ids.first, let album = album(withID: id) {
                    beginPlayback(for: album)
                }
            }
            .onChange(of: scrollTarget) { _, target in
                scroll(proxy, to: target)
            }
            .onAppear { scroll(proxy, to: scrollTarget) }
        }
    }

    private func listRows(for albums: [LibraryAlbum]) -> some View {
        ForEach(albums) { album in
            LibraryAlbumListRow(
                album: album,
                artworkURL: libraryVM.artworkURL(for: album),
                playbackState: playbackState(for: album),
                onToggleFavorite: { toggleFavorite(for: album) }
            )
            .tag(album.id)
            .id(album.id)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: NestMacMetrics.gridItemMinWidth, maximum: NestMacMetrics.gridItemMaxWidth),
            spacing: NestMacMetrics.gridSpacing,
            alignment: .top
        )]
    }

    private var albumGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: gridColumns,
                    alignment: .leading,
                    spacing: NestMacMetrics.gridSpacing + 4,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(sections) { section in
                        if libraryVM.groupMode == .none {
                            gridCells(for: section.albums)
                        } else {
                            Section {
                                gridCells(for: section.albums)
                            } header: {
                                gridSectionHeader(section.title)
                            }
                        }
                    }
                }
                .padding(.horizontal, NestMacMetrics.contentPadding + 4)
                .padding(.vertical, NestMacMetrics.contentPadding)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { updateGridColumnCount(for: geometry.size.width) }
                        .onChange(of: geometry.size.width) { _, width in
                            updateGridColumnCount(for: width)
                        }
                }
            }
            .focusable()
            .focused($contentFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .pageUp, .pageDown]) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                let columns = max(1, gridColumnCount)
                switch press.key {
                case .leftArrow: moveSelection(by: -1)
                case .rightArrow: moveSelection(by: 1)
                case .upArrow: moveSelection(by: -columns)
                case .downArrow: moveSelection(by: columns)
                case .pageUp: moveSelection(by: -columns * 4)
                case .pageDown: moveSelection(by: columns * 4)
                default: return .ignored
                }
                return .handled
            }
            .onChange(of: scrollTarget) { _, target in
                scroll(proxy, to: target)
            }
            .onAppear { scroll(proxy, to: scrollTarget) }
        }
    }

    private func gridCells(for albums: [LibraryAlbum]) -> some View {
        ForEach(albums) { album in
            LibraryAlbumGridCell(
                album: album,
                artworkURL: libraryVM.artworkURL(for: album),
                isSelected: selectedAlbumID == album.id,
                playbackState: playbackState(for: album)
            )
            .id(album.id)
            .onTapGesture(count: 2) { beginPlayback(for: album) }
            .simultaneousGesture(TapGesture().onEnded {
                selectedAlbumID = album.id
                contentFocused = true
            })
            .contextMenu { albumMenu(for: album) }
        }
    }

    private func gridSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .nestPrimaryForeground()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .background(.bar)
    }

    private func updateGridColumnCount(for width: CGFloat) {
        let available = width - (NestMacMetrics.contentPadding + 4) * 2
        let count = Int((available + NestMacMetrics.gridSpacing) / (NestMacMetrics.gridItemMinWidth + NestMacMetrics.gridSpacing))
        gridColumnCount = max(1, count)
    }

    @ViewBuilder
    private func albumMenu(for album: LibraryAlbum) -> some View {
        Button("Play") { beginPlayback(for: album) }
        Button(album.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            toggleFavorite(for: album)
        }
        Divider()
        Button("Edit Metadata…") { editingAlbum = album }
        Button("Show in Finder") { revealInFinder(album) }
        Divider()
        Button("Remove from Library…", role: .destructive) {
            albumPendingRemoval = album
        }
        .disabled(libraryVM.isLibraryBusy)
    }

    @ViewBuilder
    private var libraryEmptyState: some View {
        if AppSettings.libraryRootURL == nil {
            NestMacEmptyState(
                title: "Choose a Library Folder",
                message: "FlacNest scans CUE and FLAC files under your library home folder.",
                systemImage: "folder.badge.questionmark",
                actionTitle: "Open Settings…",
                action: { openSettings() }
            )
        } else if !libraryVM.filterText.isEmpty {
            ContentUnavailableView.search(text: libraryVM.filterText)
        } else if libraryVM.showFavoritesOnly {
            NestMacEmptyState(
                title: "No Favorites Yet",
                message: "Star albums in your library to collect them here.",
                systemImage: "star",
                actionTitle: "Show All Albums",
                action: { sidebarFilter = .allAlbums }
            )
        } else {
            NestMacEmptyState(
                title: "No Albums in Library",
                message: "Refresh the library or scan a subfolder to import CUE/FLAC albums.",
                systemImage: "music.note.list",
                actionTitle: "Refresh Library",
                action: { libraryVM.refreshLibrary() }
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("View", selection: $viewMode) {
                ForEach(LibraryViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Show albums as a grid or a list")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if let album = selectedAlbum {
                    beginPlayback(for: album)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .disabled(selectedAlbum == nil || libraryVM.isLibraryBusy)
            .help("Play selected album (Return)")

            sortGroupMenu

            if libraryVM.isScanning {
                Button {
                    libraryVM.cancelScan()
                } label: {
                    Label("Cancel Scan", systemImage: "xmark.circle")
                }
                .help("Cancel scan (Esc)")
            } else {
                libraryActionsMenu
            }

            Button {
                showInspector.toggle()
            } label: {
                Label(showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(showInspector ? "Hide inspector (⌥⌘I)" : "Show inspector (⌥⌘I)")
        }
    }

    private var libraryActionsMenu: some View {
        Menu {
            Button("Refresh Library", systemImage: "arrow.clockwise") {
                libraryVM.refreshLibrary()
            }
            Button("Scan Subfolder…", systemImage: "folder.badge.plus") {
                libraryVM.scanSubfolder()
            }
            Divider()
            Button("Prepare Export…", systemImage: "square.and.arrow.up") {
                openWindow(id: "prepareExport")
            }
            .disabled(libraryVM.library.albums.isEmpty)
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        } primaryAction: {
            libraryVM.refreshLibrary()
        }
        .disabled(AppSettings.libraryRootURL == nil || libraryVM.isLibraryBusy)
        .help("Refresh library (⌘R) — click and hold for more")
    }

    private var sortGroupMenu: some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { libraryVM.sortMode },
                set: { libraryVM.setSortMode($0) }
            )) {
                ForEach(LibrarySortMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Picker("Group By", selection: Binding(
                get: { libraryVM.groupMode },
                set: { libraryVM.setGroupMode($0) }
            )) {
                ForEach(LibraryGroupMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort & Group", systemImage: "arrow.up.arrow.down")
        }
        .disabled(libraryVM.isLibraryBusy)
        .help("Sort and group albums")
    }

    // MARK: - Actions

    private func album(withID id: String) -> LibraryAlbum? {
        displayedAlbums.first { $0.id == id }
    }

    private func playbackState(for album: LibraryAlbum) -> LibraryAlbumPlaybackState {
        guard playback.currentAlbum?.id == album.id else { return .none }
        return playback.isPlaying ? .playing : .paused
    }

    private func toggleFavorite(for album: LibraryAlbum) {
        do {
            try libraryVM.toggleFavorite(for: album.id)
        } catch {
            libraryVM.statusMessage = "Could not update favorite: \(error.localizedDescription)"
        }
    }

    private func removeAlbum(_ album: LibraryAlbum) {
        do {
            if playback.currentAlbum?.id == album.id {
                playback.stop()
            }
            if selectedAlbumID == album.id {
                selectedAlbumID = nil
            }
            try libraryVM.removeAlbum(withID: album.id)
        } catch {
            libraryVM.statusMessage = "Could not remove album: \(error.localizedDescription)"
        }
    }

    private func revealInFinder(_ album: LibraryAlbum) {
        guard let root = AppSettings.libraryRootURL else { return }
        let cueURL = root.appendingPathComponent(album.cueRelativePath)
        NSWorkspace.shared.activateFileViewerSelecting([cueURL])
    }

    private func beginPlayback(for album: LibraryAlbum) {
        selectedAlbumID = album.id
        playback.load(album: album)
        playback.play()
    }

    private func revealPlayingAlbum() {
        guard let playingAlbumID = playback.currentAlbum?.id else { return }
        selectedAlbumID = playingAlbumID
        scrollTarget = playingAlbumID
    }

    private func scroll(_ proxy: ScrollViewProxy, to target: String?) {
        guard let target else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(target, anchor: .center)
            }
            scrollTarget = nil
        }
    }

    private func moveSelection(by delta: Int) {
        guard !libraryVM.isLibraryBusy else { return }

        let albums = displayedAlbums
        guard !albums.isEmpty else { return }

        let currentIndex: Int
        if let selectedAlbumID, let index = albums.firstIndex(where: { $0.id == selectedAlbumID }) {
            currentIndex = index
        } else {
            currentIndex = delta >= 0 ? -1 : albums.count
        }

        let newIndex = min(albums.count - 1, max(0, currentIndex + delta))
        let album = albums[newIndex]
        selectedAlbumID = album.id
        scrollTarget = album.id
    }
}

// MARK: - Album cells

enum LibraryAlbumPlaybackState {
    case none
    case playing
    case paused

    var systemImage: String? {
        switch self {
        case .none: return nil
        case .playing: return "speaker.wave.2.fill"
        case .paused: return "pause.fill"
        }
    }
}

private struct LibraryAlbumListRow: View {
    let album: LibraryAlbum
    let artworkURL: URL?
    let playbackState: LibraryAlbumPlaybackState
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            LibraryArtworkView(url: artworkURL, size: NestMacMetrics.listArtworkSize, cornerRadius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.displayTitle)
                    .font(.body.weight(.medium))
                    .nestPrimaryForeground()
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .nestSecondaryForeground()
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let symbol = playbackState.systemImage {
                Image(systemName: symbol)
                    .font(.callout)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(playbackState == .playing ? "Now playing" : "Paused")
            }

            Button(action: onToggleFavorite) {
                Image(systemName: album.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(album.isFavorite ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.borderless)
            .help(album.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(album.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts = [album.performer]
        if let date = album.date, !date.isEmpty { parts.append(date) }
        parts.append(album.tracks.count == 1 ? "1 track" : "\(album.tracks.count) tracks")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct LibraryAlbumGridCell: View {
    let album: LibraryAlbum
    let artworkURL: URL?
    let isSelected: Bool
    let playbackState: LibraryAlbumPlaybackState

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryArtworkView(url: artworkURL, size: nil, cornerRadius: 8)
                .shadow(color: .black.opacity(isHovering ? 0.22 : 0.14), radius: isHovering ? 10 : 6, y: isHovering ? 5 : 3)
                .overlay(alignment: .bottomLeading) {
                    if let symbol = playbackState.systemImage {
                        Image(systemName: symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor, in: Circle())
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if album.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .padding(8)
                    }
                }
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .opacity(isSelected ? 1 : 0)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(album.displayTitle)
                    .font(.callout.weight(.medium))
                    .nestPrimaryForeground()
                    .lineLimit(1)
                Text(album.performer)
                    .font(.callout)
                    .nestSecondaryForeground()
                    .lineLimit(1)
            }
            .padding(.horizontal, 3)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help("\(album.displayTitle) — \(album.performer)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Now playing bar

private struct LibraryNowPlayingBar: View {
    var playback: PlaybackController
    let artworkURL: URL?
    let onReveal: () -> Void
    let onOpenPlayer: () -> Void

    private var hasAlbum: Bool { playback.currentAlbum != nil }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 20) {
                nowPlayingInfo
                    .frame(minWidth: 180, maxWidth: 300, alignment: .leading)

                transport

                progress
                    .frame(maxWidth: .infinity)

                Button(action: onOpenPlayer) {
                    Label("Open Player Window", systemImage: "macwindow.on.rectangle")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Open the player in its own window")
            }
            .padding(.horizontal, NestMacMetrics.contentPadding)
            .padding(.vertical, 10)
        }
        .nestSurfaceBackground()
    }

    private var nowPlayingInfo: some View {
        Button(action: onReveal) {
            HStack(spacing: 10) {
                LibraryArtworkView(url: artworkURL, size: 44, cornerRadius: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.currentTrack?.title ?? "Not Playing")
                        .font(.callout.weight(.medium))
                        .nestPrimaryForeground()
                        .lineLimit(1)
                    if let error = playback.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else {
                        Text(subtitle)
                            .font(.caption)
                            .nestSecondaryForeground()
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasAlbum)
        .help("Reveal the playing album in the library")
    }

    private var subtitle: String {
        guard let album = playback.currentAlbum else { return "Double-click an album to play" }
        let performer = playback.currentTrack?.performer.flatMap { $0.isEmpty ? nil : $0 } ?? album.performer
        return [performer, album.displayTitle].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Button { playback.previousTrack() } label: {
                Label("Previous Track", systemImage: "backward.fill")
            }
            .help("Previous track (⌘←)")

            Button { playback.togglePlayPause() } label: {
                Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 28)
            }
            .help(playback.isPlaying ? "Pause (Space)" : "Play (Space)")

            Button { playback.nextTrack() } label: {
                Label("Next Track", systemImage: "forward.fill")
            }
            .help("Next track (⌘→)")
        }
        .font(.title3)
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .nestPrimaryForeground()
        .disabled(!hasAlbum)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            Text(TrackTimeFormatting.formatClock(playback.trackElapsed))
                .frame(minWidth: 36, alignment: .trailing)
            SeekableProgressBar(progress: playback.trackProgress, height: 4) { fraction in
                playback.seekToTrackProgress(fraction)
            }
            .frame(minWidth: 80)
            Text(TrackTimeFormatting.formatClock(playback.trackDuration))
                .frame(minWidth: 36, alignment: .leading)
        }
        .font(.caption.monospacedDigit())
        .nestSecondaryForeground()
        .disabled(!hasAlbum)
    }
}

private struct LibraryBusyOverlay: View {
    @Environment(\.nestThemePalette) private var palette

    let isScanning: Bool
    let isPreparingLibraryUI: Bool
    let scanProgress: ScanProgress
    let statusMessage: String?

    var body: some View {
        ZStack {
            overlayBackground
                .ignoresSafeArea()

            VStack(spacing: 18) {
                SpinningCDView(isSpinning: true, size: 104)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)

                Text(title)
                    .font(.headline)
                    .nestPrimaryForeground()

                if isScanning {
                    if scanProgress.phase == .processing, scanProgress.total > 0 {
                        ProgressView(value: scanProgress.fractionCompleted)
                            .frame(maxWidth: 240)
                        Text(scanProgress.detail)
                            .font(.caption.monospacedDigit())
                            .nestSecondaryForeground()
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if !scanProgress.currentItem.isEmpty {
                        Text(scanProgress.currentItem)
                            .font(.caption)
                            .nestSecondaryForeground()
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 280)
                    }
                } else if let statusMessage {
                    Text(statusMessage)
                        .font(.subheadline)
                        .nestSecondaryForeground()
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }
            .padding(28)
        }
    }

    private var title: String {
        if isScanning {
            return scanProgress.title
        }
        if isPreparingLibraryUI {
            return "Preparing Library"
        }
        return "Loading Library"
    }

    private var overlayBackground: Color {
        if let palette {
            return palette.background.opacity(0.92)
        }
        return Color(nsColor: .windowBackgroundColor).opacity(0.92)
    }
}
