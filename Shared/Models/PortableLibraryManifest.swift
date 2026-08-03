import Foundation

struct PortableLibraryManifest: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var packageName: String
    var albums: [PortableAlbum]

    init(
        exportedAt: Date = Date(),
        packageName: String,
        albums: [PortableAlbum]
    ) {
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.packageName = packageName
        self.albums = albums
    }
}

struct PortableAlbum: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var performer: String
    var genre: String?
    var date: String?
    var discID: String?
    var comment: String?
    var barcode: String?
    var isFavorite: Bool
    var artworkFilename: String?
    var tracks: [PortableTrack]

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }

    var sortArtist: String {
        let trimmed = performer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

struct PortableTrack: Codable, Equatable, Identifiable {
    var id: String
    var number: Int
    var title: String
    var performer: String?
    var startSeconds: Double
    var endSeconds: Double?

    var durationSeconds: Double? {
        guard let end = endSeconds else { return nil }
        return max(0, end - startSeconds)
    }
}

struct PortableLibraryPackage: Equatable {
    let rootURL: URL
    let manifest: PortableLibraryManifest

    var packageName: String { manifest.packageName }
    var albums: [PortableAlbum] { manifest.albums }

    func artworkURL(for album: PortableAlbum) -> URL? {
        guard let filename = album.artworkFilename else { return nil }
        return rootURL
            .appendingPathComponent(PortableLibraryPaths.artworkDirectoryName, isDirectory: true)
            .appendingPathComponent(filename)
    }
}

enum PortableLibraryPaths {
    static let packageExtension = "flacnestexport"
    static let manifestFilename = "manifest.json"
    static let artworkDirectoryName = "artwork"
}
