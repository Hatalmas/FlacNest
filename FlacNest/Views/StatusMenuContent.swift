import AppKit
import SwiftUI

struct StatusMenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var libraryVM: LibraryViewModel

    private var hasLoadedAlbum: Bool {
        playback.currentAlbum != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            nowPlayingSection
            playbackControls
            Divider()
            Button("Show Player") {
                showPlayer()
            }
            .keyboardShortcut("p", modifiers: [.command])

            Divider()

            Button("Close FlacNest") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var nowPlayingSection: some View {
        HStack(alignment: .top, spacing: 10) {
            artworkView

            VStack(alignment: .leading, spacing: 3) {
                Text(playback.currentTrack?.title ?? "Not Playing")
                    .font(.headline)
                    .lineLimit(2)

                if let album = playback.currentAlbum {
                    Text(album.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(nowPlayingArtist(for: album))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Load an album in FlacNest to begin playback.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let album = playback.currentAlbum,
           let url = libraryVM.artworkURL(for: album),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button {
                playback.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
            }
            .help("Previous Track")
            .disabled(!hasLoadedAlbum)

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
            }
            .help(playback.isPlaying ? "Pause" : "Play")
            .disabled(!hasLoadedAlbum)

            Button {
                playback.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
            }
            .help("Next Track")
            .disabled(!hasLoadedAlbum)

            Button {
                playback.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .help("Stop")
            .disabled(!hasLoadedAlbum)

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .font(.title3)
        .labelStyle(.iconOnly)
    }

    private func nowPlayingArtist(for album: LibraryAlbum) -> String {
        if let track = playback.currentTrack,
           let performer = track.performer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !performer.isEmpty {
            return performer
        }
        return album.performer
    }

    private func showPlayer() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "player")
        DispatchQueue.main.async {
            PlayerWindowSizing.bringPlayerToFront()
        }
    }
}

struct StatusMenuBarLabel: View {
    var body: some View {
        Image("statusMenuPlay")
    }
}
