import SwiftUI

struct PlayerView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(PlaybackController.self) private var playback
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @EnvironmentObject private var playerWindowTracker: PlayerWindowTracker
    @EnvironmentObject private var libraryWindowTracker: LibraryWindowTracker
    @EnvironmentObject private var barcodeEject: BarcodeEjectController
    @AppStorage("playerTrackListVisible") private var showTrackList = false
    @AppStorage("showSpinningCDWhilePlaying") private var showSpinningCDWhilePlaying = true
    @State private var artworkSize: CGFloat = 128
    @State private var layoutWidth: CGFloat = PlayerWindowSizing.minWidth
    @State private var hasAppliedStoredArtworkSize = false

    private var showsSpinningCD: Bool {
        showSpinningCDWhilePlaying && playback.currentAlbum != nil
    }

    var body: some View {
        GeometryReader { geometry in
            let maxArtworkSize = PlayerArtworkSizing.maxSize(
                forWidth: geometry.size.width,
                showsSpinningCD: showsSpinningCD
            )

            VStack(spacing: 0) {
                PlayerArtworkHeaderView(
                    artworkURL: playback.currentAlbum.flatMap { libraryVM.artworkURL(for: $0) },
                    isPlaying: playback.isPlaying,
                    hasAlbum: playback.currentAlbum != nil,
                    artworkSize: artworkSize,
                    trailingControls: { playerToolbar }
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .frame(height: artworkSize + PlayerArtworkSizing.headerVerticalPadding + PlayerArtworkSizing.displayPadding * 2)

                PlayerArtworkResizeDivider(
                    artworkSize: $artworkSize,
                    maxSize: maxArtworkSize,
                    onResizeEnded: { persistCurrentPlayerLayout() }
                )

                playbackInfoSection

                if showTrackList {
                    Divider()
                    PlayerTrackListView(playback: playback)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 8)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .onAppear {
                layoutWidth = geometry.size.width
                if !hasAppliedStoredArtworkSize {
                    artworkSize = AppSettings.playerArtworkSize(trackListVisible: showTrackList)
                    hasAppliedStoredArtworkSize = true
                }
                clampArtworkSize(forWidth: geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, width in
                layoutWidth = width
                if !hasAppliedStoredArtworkSize {
                    artworkSize = AppSettings.playerArtworkSize(trackListVisible: showTrackList)
                    hasAppliedStoredArtworkSize = true
                }
                clampArtworkSize(forWidth: width)
            }
        }
        .frame(
            minWidth: PlayerWindowSizing.minWidth,
            minHeight: PlayerWindowSizing.minHeight
        )
        .nestThemedScreenBackground()
        .onAppear {
            artworkSize = AppSettings.playerArtworkSize(trackListVisible: showTrackList)
            PlayerWindowSizing.restoreSize(trackListVisible: showTrackList)
            playerWindowTracker.refresh()
            libraryWindowTracker.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flacNestApplicationWillTerminate)) { _ in
            persistCurrentPlayerLayout()
        }
        .onChange(of: playback.currentAlbum?.id) { _, albumID in
            if albumID == nil {
                showTrackList = false
            }
            clampArtworkSize(forWidth: layoutWidth)
        }
        .onChange(of: showSpinningCDWhilePlaying) { _, _ in
            clampArtworkSize(forWidth: layoutWidth)
        }
        .onChange(of: showTrackList) { wasVisible, isVisible in
            persistCurrentPlayerLayout(trackListVisible: wasVisible)
            PlayerWindowSizing.restoreSize(trackListVisible: isVisible)
            hasAppliedStoredArtworkSize = false
            artworkSize = AppSettings.playerArtworkSize(trackListVisible: isVisible)
            hasAppliedStoredArtworkSize = true
            clampArtworkSize(forWidth: layoutWidth)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  PlayerWindowSizing.isPlayerWindow(window) else { return }
            persistCurrentPlayerLayout()
        }
        .barcodeEjectSheet()
        .background(MainWindowLifecycleMonitor())
    }

    private var playbackInfoSection: some View {
        VStack(spacing: 12) {
            PlayerNowPlayingInfoView(
                album: playback.currentAlbum,
                track: playback.currentTrack
            )
            PlaybackProgressView(playback: playback, style: .player)
            TransportControls(playback: playback, style: .player) {
                barcodeEject.presentEject()
            }
            if let error = playback.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var playerToolbar: some View {
        PlayerToolbarIconGroup {
            Button {
                PlayerWindowSizing.attach(
                    dismissWindow: dismissWindow,
                    openWindow: openWindow,
                    tracker: playerWindowTracker
                )
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .scaleEffect(x: -1, y: 1)
            }
            .buttonStyle(.borderless)
            .help("Attach to Library")

            Button {
                showTrackList.toggle()
            } label: {
                Image(systemName: showTrackList ? "list.bullet.circle.fill" : "list.bullet.circle")
            }
            .buttonStyle(.borderless)
            .help("Show track list")
            .disabled(playback.currentAlbum == nil)

            Button {
                PlayerWindowSizing.toggleLibrary(
                    openWindow: openWindow,
                    dismissWindow: dismissWindow,
                    tracker: libraryWindowTracker
                )
            } label: {
                Image(systemName: libraryWindowTracker.isOpen ? "book.fill" : "book")
            }
            .buttonStyle(.borderless)
            .help(libraryWindowTracker.isOpen ? "Close Library (⌘2)" : "Open Library (⌘2)")
        }
        .frame(width: PlayerArtworkSizing.toolbarWidth, alignment: .center)
    }

    private func persistCurrentPlayerLayout(trackListVisible: Bool? = nil) {
        let mode = trackListVisible ?? showTrackList
        AppSettings.setPlayerArtworkSize(artworkSize, trackListVisible: mode)
        PlayerWindowSizing.saveCurrentSize(trackListVisible: mode, artworkSize: artworkSize)
    }

    private func clampArtworkSize(forWidth width: CGFloat) {
        let clamped = PlayerArtworkSizing.clamp(artworkSize, forWidth: width, showsSpinningCD: showsSpinningCD)
        guard clamped != artworkSize else { return }
        artworkSize = clamped
    }
}
