import Foundation

enum PortableLibraryExporter {
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func export(
        library: FlacNestLibrary,
        packageName: String,
        to destinationURL: URL,
        artworkURLProvider: (LibraryAlbum) -> URL?
    ) throws -> URL {
        let fileManager = FileManager.default
        let sanitizedName = sanitizePackageName(packageName)
        let packageURL = destinationURL
            .appendingPathComponent(sanitizedName, isDirectory: true)
            .appendingPathExtension(PortableLibraryPaths.packageExtension)

        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let artworkDirectory = packageURL
            .appendingPathComponent(PortableLibraryPaths.artworkDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)

        var portableAlbums: [PortableAlbum] = []
        for album in library.albums {
            let artworkFilename = try copyArtworkIfNeeded(
                for: album,
                into: artworkDirectory,
                artworkURLProvider: artworkURLProvider
            )
            portableAlbums.append(makePortableAlbum(from: album, artworkFilename: artworkFilename))
        }

        let manifest = PortableLibraryManifest(
            exportedAt: Date(),
            packageName: sanitizedName,
            albums: portableAlbums
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601.string(from: date))
        }
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: packageURL.appendingPathComponent(PortableLibraryPaths.manifestFilename), options: .atomic)

        return packageURL
    }

    private static func makePortableAlbum(from album: LibraryAlbum, artworkFilename: String?) -> PortableAlbum {
        PortableAlbum(
            id: album.id,
            title: album.title,
            performer: album.performer,
            genre: album.genre,
            date: album.date,
            discID: album.discID,
            comment: album.comment,
            barcode: album.barcode,
            isFavorite: album.isFavorite,
            artworkFilename: artworkFilename,
            tracks: album.tracks.map { track in
                PortableTrack(
                    id: track.id,
                    number: track.number,
                    title: track.title,
                    performer: track.performer,
                    startSeconds: track.startSeconds,
                    endSeconds: track.endSeconds
                )
            }
        )
    }

    private static func copyArtworkIfNeeded(
        for album: LibraryAlbum,
        into artworkDirectory: URL,
        artworkURLProvider: (LibraryAlbum) -> URL?
    ) throws -> String? {
        guard let sourceURL = artworkURLProvider(album),
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let filename = "\(sanitizeFilename(album.id)).\(ext)"
        let destinationURL = artworkDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return filename
    }

    private static func sanitizePackageName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "FlacNest Export"
        let candidate = trimmed.isEmpty ? fallback : trimmed
        let invalid = CharacterSet(charactersIn: "/:\\")
        return candidate
            .components(separatedBy: invalid)
            .joined(separator: "-")
    }

    private static func sanitizeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let sanitized = value
            .components(separatedBy: invalid)
            .joined(separator: "_")
        return sanitized.isEmpty ? "album" : sanitized
    }
}

enum PortableLibraryExportError: LocalizedError {
    case exportCancelled
    case libraryEmpty

    var errorDescription: String? {
        switch self {
        case .exportCancelled:
            return "Export was cancelled."
        case .libraryEmpty:
            return "There are no albums to export."
        }
    }
}
