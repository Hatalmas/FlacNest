import AppKit
import SwiftUI

struct AlbumMetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @EnvironmentObject private var playback: PlaybackController

    @State private var draft: LibraryAlbum
    @State private var errorMessage: String?

    init(album: LibraryAlbum) {
        _draft = State(initialValue: album)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Album Metadata")
                    .font(.title2)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { saveChanges() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(libraryVM.isScanning)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    artworkSection
                    metadataSection
                    tracksSection
                }
                .padding()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    private var artworkSection: some View {
        GroupBox("Artwork") {
            HStack(alignment: .top, spacing: 16) {
                artworkPreview
                    .frame(width: 160, height: 160)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    if let path = draft.artworkRelativePath, !path.isEmpty {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    } else {
                        Text("No artwork set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Choose Image…") { chooseArtwork() }
                        Button("Clear") { draft.artworkRelativePath = nil }
                            .disabled(draft.artworkRelativePath == nil)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var artworkPreview: some View {
        if let url = libraryVM.artworkURL(for: draft), let image = NSImage(contentsOf: url) {
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

    private var metadataSection: some View {
        GroupBox("Album Details") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Title")
                    TextField("Title", text: $draft.title)
                }
                GridRow {
                    Text("Performer")
                    TextField("Performer", text: $draft.performer)
                }
                GridRow {
                    Text("Genre")
                    TextField("Genre", text: optionalBinding($draft.genre))
                }
                GridRow {
                    Text("Date")
                    TextField("Date", text: optionalBinding($draft.date))
                }
                GridRow {
                    Text("Disc ID")
                    TextField("Disc ID", text: optionalBinding($draft.discID))
                }
                GridRow {
                    Text("Comment")
                    TextField("Comment", text: optionalBinding($draft.comment))
                }
            }
            .padding(4)
        }
    }

    private var tracksSection: some View {
        GroupBox("Tracks") {
            VStack(spacing: 0) {
                HStack {
                    Button("Import from clipboard") {
                        importTrackTitlesFromClipboard()
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 8)

                HStack {
                    Text("#").frame(width: 28, alignment: .trailing)
                    Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Performer").frame(width: 160, alignment: .leading)
                    Text("Start").frame(width: 56, alignment: .trailing)
                    Text("End").frame(width: 56, alignment: .trailing)
                    Text("Length").frame(width: 56, alignment: .trailing)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                Divider()

                ForEach($draft.tracks) { $track in
                    HStack(spacing: 8) {
                        Text("\(track.number)")
                            .frame(width: 28, alignment: .trailing)
                            .foregroundStyle(.secondary)

                        TextField("Title", text: $track.title)
                            .textFieldStyle(.plain)

                        TextField("Performer", text: optionalBinding($track.performer))
                            .textFieldStyle(.plain)
                            .frame(width: 160)

                        Text(TrackTimeFormatting.formatClock(track.startSeconds))
                            .frame(width: 56, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Text(track.endSeconds.map(TrackTimeFormatting.formatClock) ?? "—")
                            .frame(width: 56, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

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

    private func optionalBinding(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private func chooseArtwork() {
        guard let root = AppSettings.libraryRootURL else {
            errorMessage = "Set a library folder in Settings first."
            return
        }
        guard let sourceURL = AlbumArtworkImporter.chooseImageFile() else { return }

        do {
            draft.artworkRelativePath = try AlbumArtworkImporter.referenceArtwork(
                from: sourceURL,
                album: draft,
                libraryRoot: root
            )
            errorMessage = nil
        } catch {
            errorMessage = "Could not set artwork: \(error.localizedDescription)"
        }
    }

    private func importTrackTitlesFromClipboard() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty else {
            errorMessage = "Clipboard is empty."
            return
        }

        var lines = clipboardText.components(separatedBy: .newlines)
        while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }
        lines = lines.map { TrackTimeFormatting.importedTrackTitle(from: $0) }

        guard lines.count == draft.tracks.count else {
            errorMessage = "Clipboard has \(lines.count) line(s), but this album has \(draft.tracks.count) track(s)."
            return
        }

        for index in draft.tracks.indices {
            draft.tracks[index].title = lines[index]
        }
        errorMessage = nil
    }

    private func saveChanges() {
        do {
            try libraryVM.updateAlbum(draft)
            playback.updateAlbumMetadataIfPlaying(draft)
            dismiss()
        } catch {
            errorMessage = "Could not save metadata: \(error.localizedDescription)"
        }
    }
}
