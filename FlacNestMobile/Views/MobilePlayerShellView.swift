import SwiftUI

struct MobilePlayerShellView: View {
    @Environment(MobileLibraryStore.self) private var libraryStore

    var body: some View {
        @Bindable var playback = libraryStore.playback
        let album = playback.currentAlbum ?? libraryStore.selectedAlbum
        let track = playback.currentTrack ?? libraryStore.selectedTrack

        VStack(spacing: 20) {
            Spacer(minLength: 0)

            MobileCDCaseArtworkView(
                url: album.flatMap { libraryStore.artworkURL(for: $0) },
                height: 240
            )
            .overlay {
                if playback.isLoadingAudio {
                    ZStack {
                        Color.black.opacity(0.25)
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .shadow(radius: 8, y: 4)

            VStack(spacing: 8) {
                Text(track?.title ?? "No track selected")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(trackPerformer(track: track, album: album))
                    .mobileSecondaryForeground()
                Text(album?.displayTitle ?? "Open an export folder to begin")
                    .font(.subheadline)
                    .mobileSecondaryForeground()
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            MobilePlaybackProgressView(playback: playback)
                .padding(.horizontal)

            HStack(spacing: 28) {
                Button {
                    playback.previousTrack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(album == nil || playback.isLoadingAudio)

                Button {
                    if playback.currentAlbum == nil {
                        libraryStore.playSelectedTrack()
                    } else {
                        playback.togglePlayPause()
                    }
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }
                .disabled(album == nil || playback.isLoadingAudio)

                Button {
                    playback.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(album == nil || playback.isLoadingAudio)
            }

            if let error = playback.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .mobileThemedScreenBackground()
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            syncPlaybackSelection(playback: playback)
        }
        .onChange(of: libraryStore.selectedAlbumID) { _, _ in
            syncPlaybackSelection(playback: playback)
        }
        .onChange(of: libraryStore.selectedTrackID) { _, _ in
            syncPlaybackSelection(playback: playback)
        }
    }

    private func trackPerformer(track: MobileLibraryTrack?, album: MobileLibraryAlbum?) -> String {
        if let track, let performer = track.performer?.trimmingCharacters(in: .whitespacesAndNewlines), !performer.isEmpty {
            return performer
        }
        return album?.performer ?? ""
    }

    private func syncPlaybackSelection(playback: MobilePlaybackController) {
        guard playback.currentAlbum == nil,
              let album = libraryStore.selectedAlbum else {
            return
        }
        let trackIndex = album.tracks.firstIndex { $0.id == libraryStore.selectedTrackID } ?? 0
        playback.load(album: album, trackIndex: trackIndex)
    }
}
