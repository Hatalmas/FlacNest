import Foundation

struct LastPlaybackState: Codable, Equatable {
    var albumID: String
    var flacRelativePath: String
    var trackIndex: Int
    var positionSeconds: Double
    var cachedAlbum: LibraryAlbum?

    var hasCachedAlbum: Bool {
        cachedAlbum != nil
    }
}
