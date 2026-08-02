import Foundation

struct FlacNestLibrary: Codable, Equatable {
    var version: Int
    var scannedAt: Date
    var albums: [LibraryAlbum]

    static let currentVersion = 1

    init(scannedAt: Date = Date(), albums: [LibraryAlbum] = []) {
        self.version = Self.currentVersion
        self.scannedAt = scannedAt
        self.albums = albums
    }
}

struct LibraryAlbum: Codable, Equatable, Identifiable {
    var id: String
    var cueRelativePath: String
    var flacRelativePath: String
    var title: String
    var performer: String
    var genre: String?
    var date: String?
    var discID: String?
    var comment: String?
    var artworkRelativePath: String?
    var barcode: String?
    var tracks: [LibraryTrack]

    var displayTitle: String {
        if title.isEmpty { return (cueRelativePath as NSString).lastPathComponent }
        return title
    }
}

struct LibraryTrack: Codable, Equatable, Identifiable {
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
