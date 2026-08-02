import SwiftUI

struct PlayerView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @EnvironmentObject private var playerWindowTracker: PlayerWindowTracker
    @AppStorage("playerTrackListVisible") private var showTrackList = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                NowPlayingMetadataView(
                    album: playback.currentAlbum,
                    track: playback.currentTrack,
                    artworkURL: playback.currentAlbum.flatMap { libraryVM.artworkURL(for: $0) },
                    isPlaying: playback.isPlaying,
                    layout: .player,
                    trailingControls: AnyView(playerToolbar)
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

            if showTrackList {
                Divider()
                PlayerTrackListView(playback: playback)
                    .padding(.bottom, 8)
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
    }
}
