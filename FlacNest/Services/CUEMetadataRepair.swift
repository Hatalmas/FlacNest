import Foundation

enum CUEMetadataRepair {
    static func repair(_ parsed: ParsedCUE, flacURL: URL) -> ParsedCUE {
        var result = parsed
        let flacTags = FLACMetadataReader.readVorbisComments(from: flacURL)

        if metadataIsDamaged(result.performer) {
            if let artist = firstTag(in: flacTags, keys: ["ARTIST", "ALBUMARTIST"]) {
                result.performer = artist
            } else if let trackPerformer = mostCommonTrackPerformer(result.tracks) {
                result.performer = trackPerformer
            }
        }

        if metadataIsDamaged(result.title) {
            if let album = firstTag(in: flacTags, keys: ["ALBUM"]) {
                result.title = album
            }
        }

        if (result.genre == nil || result.genre?.isEmpty == true),
           let genre = firstTag(in: flacTags, keys: ["GENRE"]) {
            result.genre = genre
        }

        if (result.date == nil || result.date?.isEmpty == true),
           let date = firstTag(in: flacTags, keys: ["DATE"]) {
            result.date = date
        }

        return result
    }

    private static func metadataIsDamaged(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.contains("\u{FFFD}") || text.contains("ï¿½")
    }

    private static func firstTag(in tags: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = tags[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func mostCommonTrackPerformer(_ tracks: [ParsedTrack]) -> String? {
        var counts: [String: Int] = [:]
        for track in tracks {
            guard let performer = track.performer, !performer.isEmpty else { continue }
            counts[performer, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
