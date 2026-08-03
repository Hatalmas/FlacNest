import Foundation

struct MobileLibrary: Equatable {
    var version: Int
    var scannedAt: Date
    var albums: [MobileLibraryAlbum]

    static let currentVersion = 1

    init(scannedAt: Date = Date(), albums: [MobileLibraryAlbum] = []) {
        self.version = Self.currentVersion
        self.scannedAt = scannedAt
        self.albums = albums
    }
}

struct MobileLibraryAlbum: Equatable, Identifiable {
    var id: String
    var cueRelativePath: String
    var mp3RelativePath: String
    var title: String
    var performer: String
    var parentFolder: String
    var genre: String?
    var date: String?
    var discID: String?
    var comment: String?
    var barcode: String?
    var isFavorite = false
    var artworkRelativePath: String?
    var tracks: [MobileLibraryTrack]

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (cueRelativePath as NSString).lastPathComponent }
        return trimmed
    }

    var sortArtist: String {
        let trimmed = performer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? parentFolder : trimmed
    }
}

struct MobileLibraryTrack: Equatable, Identifiable {
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

struct MobileLibraryPackage: Equatable {
    let rootURL: URL
    let library: MobileLibrary

    var albums: [MobileLibraryAlbum] { library.albums }
    var displayName: String { rootURL.lastPathComponent }

    func mp3URL(for album: MobileLibraryAlbum) -> URL {
        rootURL.appendingPathComponent(album.mp3RelativePath)
    }

    func artworkURL(for album: MobileLibraryAlbum) -> URL? {
        guard let relative = album.artworkRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !relative.isEmpty else {
            return nil
        }
        return rootURL.appendingPathComponent(relative)
    }
}

struct MobileLibraryAlbumSection: Identifiable, Equatable {
    let id: String
    let title: String
    let albums: [MobileLibraryAlbum]
}

enum MobileLibraryPaths {
    static let xmlFilename = "flacnestmobile.xml"
    static let processLogFilename = "process.txt"
}
