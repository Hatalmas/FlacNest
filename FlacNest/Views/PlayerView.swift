import SwiftUI

struct PlayerView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @EnvironmentObject private var playerWindowTracker: PlayerWindowTracker
    @AppStorage("playerTrackListVisible") private var showTrackList = false
    @AppStorage("showSpinningCDWhilePlaying") private var showSpinningCDWhilePlaying = true
    @State private var artworkSize: CGFloat = AppSettings.playerArtworkSize
    @State private var layoutWidth: CGFloat = PlayerWindowSizing.minWidth

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
                    showsSpinningCD: showsSpinningCD,
                    artworkSize: artworkSize,
                    trailingControls: { playerToolbar }
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .frame(height: artworkSize + PlayerArtworkSizing.headerVerticalPadding)

                PlayerArtworkResizeDivider(
                    artworkSize: $artworkSize,
                    maxSize: maxArtworkSize
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
            .onChange(of: geometry.size.width) { _, width in
                layoutWidth = width
                clampArtworkSize(forWidth: width)
            }
        }
        .frame(
            minWidth: PlayerWindowSizing.minWidth,
            minHeight: PlayerWindowSizing.minHeight
        )
        .onAppear {
            PlayerWindowSizing.restoreSize(trackListVisible: showTrackList)
            playerWindowTracker.refresh()
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
            PlayerWindowSizing.handleToggle(from: wasVisible, to: isVisible)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  PlayerWindowSizing.isPlayerWindow(window) else { return }
            PlayerWindowSizing.saveCurrentSize(trackListVisible: showTrackList)
        }
    }

    private var playbackInfoSection: some View {
        VStack(spacing: 12) {
            PlayerNowPlayingInfoView(
                album: playback.currentAlbum,
                track: playback.currentTrack
            )
            PlaybackProgressView(playback: playback)
            TransportControls(playback: playback)
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
        VStack(spacing: 8) {
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
                openWindow(id: "library")
            } label: {
                Image(systemName: "book")
            }
            .buttonStyle(.borderless)
            .help("Open Library (⌘2)")
        }
        .font(.title3)
        .labelStyle(.iconOnly)
        .frame(width: PlayerArtworkSizing.toolbarWidth, alignment: .center)
    }

    private func clampArtworkSize(forWidth width: CGFloat) {
        let clamped = PlayerArtworkSizing.clamp(artworkSize, forWidth: width, showsSpinningCD: showsSpinningCD)
        guard clamped != artworkSize else { return }
        artworkSize = clamped
        AppSettings.playerArtworkSize = clamped
    }
}
