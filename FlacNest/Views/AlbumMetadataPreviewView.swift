import AppKit
import SwiftUI

struct AlbumMetadataPreviewView: View {
    @Environment(\.nestThemePalette) private var palette
    @Environment(PlaybackController.self) private var playback
    @EnvironmentObject private var libraryVM: LibraryViewModel

    let album: LibraryAlbum?
    var onEdit: (LibraryAlbum) -> Void = { _ in }

    var body: some View {
        Group {
            if let album {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        LibraryArtworkView(url: libraryVM.artworkURL(for: album), size: nil, cornerRadius: 10)
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)

                        header(for: album)
                        actions(for: album)

                        sectionDivider
                        detailsSection(for: album)

                        sectionDivider
                        tracksSection(for: album)
                    }
                    .padding(NestMacMetrics.contentPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "square.dashed",
                    description: Text("Select an album to see its details and tracks.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private func header(for album: LibraryAlbum) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(album.displayTitle)
                .font(.title3.weight(.semibold))
                .nestPrimaryForeground()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !album.performer.isEmpty {
                Text(album.performer)
                    .font(.body)
                    .nestSecondaryForeground()
                    .textSelection(.enabled)
            }

            Text(summary(for: album))
                .font(.caption)
                .nestSecondaryForeground()
        }
    }

    private func summary(for album: LibraryAlbum) -> String {
        var parts: [String] = []
        if let genre = album.genre, !genre.isEmpty { parts.append(genre) }
        if let date = album.date, !date.isEmpty { parts.append(date) }
        parts.append(album.tracks.count == 1 ? "1 track" : "\(album.tracks.count) tracks")
        return parts.joined(separator: " · ")
    }

    private func actions(for album: LibraryAlbum) -> some View {
        HStack(spacing: 8) {
            Button {
                playback.load(album: album)
                playback.play()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                onEdit(album)
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .help("Edit metadata (⌘E)")

            Button {
                try? libraryVM.toggleFavorite(for: album.id)
            } label: {
                Label(
                    album.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: album.isFavorite ? "star.fill" : "star"
                )
                .labelStyle(.iconOnly)
                .foregroundStyle(album.isFavorite ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.primary))
            }
            .help(album.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
        .controlSize(.large)
        .disabled(libraryVM.isLibraryBusy)
    }

    // MARK: - Details

    private func detailsSection(for album: LibraryAlbum) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Details")

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(detailRows(for: album), id: \.label) { row in
                    GridRow {
                        Text(row.label)
                            .nestSecondaryForeground()
                            .gridColumnAlignment(.trailing)
                        Text(row.value)
                            .nestPrimaryForeground()
                            .textSelection(.enabled)
                            .lineLimit(row.isPath ? 3 : nil)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .font(.callout)
        }
    }

    private struct DetailRow {
        let label: String
        let value: String
        var isPath = false
    }

    private func detailRows(for album: LibraryAlbum) -> [DetailRow] {
        let candidates: [(String, String?, Bool)] = [
            ("Genre", album.genre, false),
            ("Year", album.date, false),
            ("Parent Folder", album.parentFolder, true),
            ("Disc ID", album.discID, false),
            ("Barcode", album.barcode, false),
            ("Comment", album.comment, false),
            ("Cue File", album.cueRelativePath, true),
        ]
        return candidates.compactMap { label, value, isPath in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return DetailRow(label: label, value: value, isPath: isPath)
        }
    }

    // MARK: - Tracks

    private func tracksSection(for album: LibraryAlbum) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Tracks")

            VStack(spacing: 0) {
                ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                    InspectorTrackRow(
                        track: track,
                        albumPerformer: album.performer,
                        isCurrent: playback.currentAlbum?.id == album.id && playback.currentTrackIndex == index,
                        isPlaying: playback.isPlaying
                    ) {
                        play(album, trackIndex: index)
                    }
                }
            }
        }
    }

    private func play(_ album: LibraryAlbum, trackIndex: Int) {
        if playback.currentAlbum?.id == album.id {
            playback.playTrack(at: trackIndex)
        } else {
            playback.load(album: album, trackIndex: trackIndex)
            playback.play()
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .nestPrimaryForeground()
    }

    private var sectionDivider: some View {
        Group {
            if let palette {
                Rectangle()
                    .fill(palette.secondary.opacity(0.25))
                    .frame(height: 1)
            } else {
                Divider()
            }
        }
    }
}

private struct InspectorTrackRow: View {
    let track: LibraryTrack
    let albumPerformer: String
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if isCurrent {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                        .foregroundStyle(.tint)
                } else if isHovering {
                    Image(systemName: "play.fill")
                        .nestSecondaryForeground()
                } else {
                    Text("\(track.number)")
                        .nestSecondaryForeground()
                }
            }
            .font(.caption.monospacedDigit())
            .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                    .nestPrimaryForeground()
                    .lineLimit(2)
                if let performer = trackPerformer {
                    Text(performer)
                        .font(.caption)
                        .nestSecondaryForeground()
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(TrackTimeFormatting.formatDuration(start: track.startSeconds, end: track.endSeconds))
                .font(.caption.monospacedDigit())
                .nestSecondaryForeground()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .help("Double-click to play")
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Play", onPlay)
    }

    private var rowFill: Color {
        if isCurrent { return Color.accentColor.opacity(0.14) }
        if isHovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var trackPerformer: String? {
        guard let performer = track.performer?.trimmingCharacters(in: .whitespacesAndNewlines),
              !performer.isEmpty,
              performer != albumPerformer else { return nil }
        return performer
    }
}
