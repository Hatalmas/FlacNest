import SwiftUI

struct MobileAlbumDetailView: View {
    @Environment(MobileLibraryStore.self) private var libraryStore
    let album: MobileLibraryAlbum

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    MobileArtworkThumbnail(
                        url: libraryStore.artworkURL(for: album),
                        size: 96,
                        cornerRadius: 10
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text(album.displayTitle)
                            .font(.title3.bold())
                        Text(album.sortArtist)
                            .mobileSecondaryForeground()
                        if let date = album.date, !date.isEmpty {
                            Text(date)
                                .font(.caption)
                                .mobileSecondaryForeground()
                        }
                        if let genre = album.genre, !genre.isEmpty {
                            Text(genre)
                                .font(.caption)
                                .mobileSecondaryForeground()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Tracks") {
                ForEach(album.tracks) { track in
                    Button {
                        libraryStore.playTrack(track, in: album)
                    } label: {
                        HStack {
                            Text("\(track.number)")
                                .mobileSecondaryForeground()
                                .frame(width: 24, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .mobilePrimaryForeground()
                                if let performer = track.performer, !performer.isEmpty {
                                    Text(performer)
                                        .font(.caption)
                                        .mobileSecondaryForeground()
                                }
                            }
                            Spacer()
                            if libraryStore.selectedTrackID == track.id {
                                Image(systemName: "speaker.wave.2.fill")
                                    .mobileSecondaryForeground()
                            }
                            Text(TrackTimeFormatting.formatDuration(start: track.startSeconds, end: track.endSeconds))
                                .font(.caption.monospacedDigit())
                                .mobileSecondaryForeground()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if let comment = album.comment, !comment.isEmpty {
                Section("Comment") {
                    Text(comment)
                        .mobileSecondaryForeground()
                }
            }
        }
        .mobileThemedListSurface()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            libraryStore.selectAlbum(album)
            if libraryStore.playback.currentAlbum?.id != album.id {
                libraryStore.playSelectedTrack()
            }
        }
    }
}
