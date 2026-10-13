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
    var artworkBookmark: Data? = nil
    var barcode: String?
    var isFavorite = false
    var isHidden = false
    var parentFolder: String = ""
    var tracks: [LibraryTrack]

    var displayTitle: String {
        if title.isEmpty { return (cueRelativePath as NSString).lastPathComponent }
        return title
    }

    var hasRegisteredBarcode: Bool {
        guard let barcode else { return false }
        return !barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasCoverArt: Bool {
        guard let artworkRelativePath else { return false }
        return !artworkRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasCatalogMetadata: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !performer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var needsDiskMetadataFill: Bool {
        !hasCatalogMetadata || !hasCoverArt || tracks.isEmpty
    }
}

extension LibraryAlbum {
    enum CodingKeys: String, CodingKey {
        case id, cueRelativePath, flacRelativePath, title, performer
        case genre, date, discID, comment
        case artworkRelativePath, artworkBookmark, barcode
        case isFavorite, isHidden, parentFolder, tracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        cueRelativePath = try container.decode(String.self, forKey: .cueRelativePath)
        flacRelativePath = try container.decode(String.self, forKey: .flacRelativePath)
        title = try container.decode(String.self, forKey: .title)
        performer = try container.decode(String.self, forKey: .performer)
        genre = try container.decodeIfPresent(String.self, forKey: .genre)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        discID = try container.decodeIfPresent(String.self, forKey: .discID)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        artworkRelativePath = try container.decodeIfPresent(String.self, forKey: .artworkRelativePath)
        artworkBookmark = try container.decodeIfPresent(Data.self, forKey: .artworkBookmark)
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        parentFolder = try container.decodeIfPresent(String.self, forKey: .parentFolder) ?? ""
        tracks = try container.decode([LibraryTrack].self, forKey: .tracks)
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
