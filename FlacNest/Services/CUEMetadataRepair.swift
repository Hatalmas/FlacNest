import Foundation

enum CUEMetadataRepair {
    static func repair(_ parsed: ParsedCUE, flacURL: URL) -> ParsedCUE {
        var result = parsed
        let flacTags = FLACMetadataReader.readVorbisComments(from: flacURL)

        result.title = MetadataTextRepair.repaired(result.title)
        result.performer = MetadataTextRepair.repaired(result.performer)
        result.genre = MetadataTextRepair.repaired(result.genre)
        result.date = MetadataTextRepair.repaired(result.date)
        result.comment = MetadataTextRepair.repaired(result.comment)
        result.albumArtist = MetadataTextRepair.repaired(firstTag(in: flacTags, keys: ["ALBUMARTIST"]))
        for index in result.tracks.indices {
            result.tracks[index].title = MetadataTextRepair.repaired(result.tracks[index].title)
            result.tracks[index].performer = MetadataTextRepair.repaired(result.tracks[index].performer)
        }

        let flacArtist = MetadataTextRepair.repaired(firstTag(in: flacTags, keys: ["ARTIST", "ALBUMARTIST"]))
        if result.performer.isEmpty || MetadataTextRepair.looksDamaged(result.performer) {
            if let artist = flacArtist {
                result.performer = artist
            } else if let trackPerformer = mostCommonTrackPerformer(result.tracks),
                      !MetadataTextRepair.looksDamaged(trackPerformer) {
                result.performer = trackPerformer
            }
        }

        if result.title.isEmpty || MetadataTextRepair.looksDamaged(result.title) {
            if let album = MetadataTextRepair.repaired(firstTag(in: flacTags, keys: ["ALBUM"])) {
                result.title = album
            }
        }

        let fallbackPerformer = [
            result.albumArtist,
            flacArtist,
            result.performer,
        ]
        .compactMap { value -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty || MetadataTextRepair.looksDamaged(trimmed) ? nil : trimmed
        }
        .first

        if let fallbackPerformer {
            for index in result.tracks.indices {
                let performer = result.tracks[index].performer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if performer.isEmpty || MetadataTextRepair.looksDamaged(performer) {
                    result.tracks[index].performer = fallbackPerformer
                }
            }
        }

        if (result.genre == nil || result.genre?.isEmpty == true),
           let genre = MetadataTextRepair.repaired(firstTag(in: flacTags, keys: ["GENRE"])) {
            result.genre = genre
        }

        if (result.date == nil || result.date?.isEmpty == true),
           let date = MetadataTextRepair.repaired(firstTag(in: flacTags, keys: ["DATE"])) {
            result.date = date
        }

        return result
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
