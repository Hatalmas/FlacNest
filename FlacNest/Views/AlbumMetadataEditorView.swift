import AppKit
import SwiftUI

struct AlbumMetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @Environment(PlaybackController.self) private var playback

    @State private var draft: LibraryAlbum
    @State private var errorMessage: String?
    @State private var updateParentOnSiblings = false

    private let originalParentFolder: String

    init(album: LibraryAlbum) {
        _draft = State(initialValue: album)
        originalParentFolder = album.parentFolder
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                artworkSection
                barcodeSection
                metadataSection
                tracksSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(NestMacMetrics.contentPadding)
        }
        .frame(minWidth: 720, minHeight: 560)
        .nestThemedScreenBackground()
        .nestThemedScrollSurface()
        .nestThemedGroupBoxes()
        .navigationTitle("Edit Album Metadata")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorActionBar
        }
        .onChange(of: parentFolderChanged) { _, changed in
            if !changed {
                updateParentOnSiblings = false
            }
        }
    }

    private var parentFolderChanged: Bool {
        draft.parentFolder.trimmingCharacters(in: .whitespacesAndNewlines)
            != originalParentFolder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var editorActionBar: some View {
        HStack(alignment: .center, spacing: 16) {
            if parentFolderChanged {
                Toggle("Update parent info on siblings", isOn: $updateParentOnSiblings)
                    .toggleStyle(.checkbox)
                    .help("Also set this parent folder on other albums grouped with this one.")
            }

            Spacer(minLength: 12)

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Save") { saveChanges() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(libraryVM.isLibraryBusy)
        }
        .padding(.horizontal, NestMacMetrics.contentPadding)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .top) {
                    Divider()
                }
                .ignoresSafeArea()
        }
    }

    private var artworkSection: some View {
        GroupBox("Artwork") {
            HStack(alignment: .top, spacing: 16) {
                artworkPreview
                    .frame(width: 160, height: 160)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    if draft.artworkRelativePath?.isEmpty == false {
                        Text("Stored with library metadata")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("No artwork set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Choose Image…") { chooseArtwork() }
                        Button("Clear") {
                            draft.artworkRelativePath = nil
                            draft.artworkBookmark = nil
                        }
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
        if let url = libraryVM.artworkURL(for: draft), let image = ArtworkImageCache.image(for: url) {
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

    private var barcodeSection: some View {
        GroupBox("Barcode") {
            HStack(alignment: .top, spacing: 16) {
                barcodePreview
                    .frame(width: 280)
                    .frame(minHeight: 88)

                VStack(alignment: .leading, spacing: 8) {
                    if let barcode = registeredBarcode {
                        Text("Assigned barcode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(barcode)
                            .font(.body.monospacedDigit())
                            .textSelection(.enabled)
                    } else {
                        Text("No barcode set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Clear") {
                        draft.barcode = nil
                    }
                    .disabled(registeredBarcode == nil)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var barcodePreview: some View {
        if let barcode = registeredBarcode {
            AlbumBarcodeView(barcode: barcode, cornerRadius: 8, barcodeHeight: 56)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    Image(systemName: "barcode")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var registeredBarcode: String? {
        guard let barcode = draft.barcode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !barcode.isEmpty else {
            return nil
        }
        return barcode
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
                    Text("Parent Folder")
                    TextField("Parent Folder", text: $draft.parentFolder)
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
                    Button("Override performer") {
                        overrideTrackPerformersFromAlbum()
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
        guard AppSettings.libraryRootURL != nil || AppSettings.libraryXMLURL != nil else {
            errorMessage = "Set a library folder in Settings first."
            return
        }
        guard let sourceURL = AlbumArtworkImporter.chooseImageFile() else { return }

        do {
            if let previousURL = libraryVM.artworkURL(for: draft) {
                ArtworkImageCache.removeImage(for: previousURL)
            }
            let reference = try AlbumArtworkImporter.importArtwork(from: sourceURL, album: draft)
            draft.artworkRelativePath = reference.path
            draft.artworkBookmark = nil
            if let url = libraryVM.artworkURL(for: draft) {
                ArtworkImageCache.removeImage(for: url)
            }
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

    private func overrideTrackPerformersFromAlbum() {
        let performer = draft.performer.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in draft.tracks.indices {
            draft.tracks[index].performer = performer.isEmpty ? nil : performer
        }
        errorMessage = nil
    }

    private func saveChanges() {
        do {
            let applyToSiblings = parentFolderChanged && updateParentOnSiblings
            draft.parentFolder = draft.parentFolder.trimmingCharacters(in: .whitespacesAndNewlines)
            try libraryVM.updateAlbum(draft, applyParentFolderToSiblings: applyToSiblings)
            if let playingID = playback.currentAlbum?.id,
               let latest = libraryVM.library.albums.first(where: { $0.id == playingID }) {
                playback.updateAlbumMetadataIfPlaying(latest)
            }
            dismiss()
        } catch {
            errorMessage = "Could not save metadata: \(error.localizedDescription)"
        }
    }
}
