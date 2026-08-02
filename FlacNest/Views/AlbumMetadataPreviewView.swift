import AppKit
import SwiftUI

struct AlbumMetadataPreviewView: View {
    @EnvironmentObject private var libraryVM: LibraryViewModel

    let album: LibraryAlbum?

    var body: some View {
        Group {
            if let album {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        artworkSection(for: album)
                        metadataSection(for: album)
                        tracksSection(for: album)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Album Selected",
                    systemImage: "info.circle",
                    description: Text("Select an album in the library list to preview its metadata.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private func artworkSection(for album: LibraryAlbum) -> some View {
        GroupBox("Artwork") {
            artworkPreview(for: album)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(4)
        }
    }

    @ViewBuilder
    private func artworkPreview(for album: LibraryAlbum) -> some View {
        if let url = libraryVM.artworkURL(for: album), let image = ArtworkImageCache.image(for: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func metadataSection(for album: LibraryAlbum) -> some View {
        GroupBox("Album Details") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                metadataRow("Title", value: album.title)
                metadataRow("Performer", value: album.performer)
                metadataRow("Genre", value: album.genre)
                metadataRow("Date", value: album.date)
                metadataRow("Disc ID", value: album.discID)
                metadataRow("Barcode", value: album.barcode)
                metadataRow("Comment", value: album.comment)
            }
            .padding(4)
        }
    }

    private func tracksSection(for album: LibraryAlbum) -> some View {
        GroupBox("Tracks") {
            VStack(spacing: 0) {
                HStack {
                    Text("#").frame(width: 28, alignment: .trailing)
                    Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Length").frame(width: 56, alignment: .trailing)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()

                ForEach(album.tracks) { track in
                    HStack(spacing: 8) {
                        Text("\(track.number)")
                            .frame(width: 28, alignment: .trailing)
                            .foregroundStyle(.secondary)

                        Text(track.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)

                        Text(TrackTimeFormatting.formatDuration(start: track.startSeconds, end: track.endSeconds))
                            .frame(width: 56, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Divider()
                }
            }
        }
    }

    private func metadataRow(_ label: String, value: String?) -> some View {
        GridRow {
            Text(label)
            metadataValue(value)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func metadataValue(_ value: String?, placeholder: String = "—") -> some View {
        let text = metadataValueText(value)
        Text(text)
            .foregroundStyle(text == placeholder ? .secondary : .primary)
    }

    private func metadataValueText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }
}
