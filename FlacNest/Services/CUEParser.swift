import Foundation

struct ParsedCUE {
    var flacFileName: String
    var title: String
    var performer: String
    var genre: String?
    var date: String?
    var discID: String?
    var comment: String?
    var artworkFileName: String?
    var tracks: [ParsedTrack]
}

struct ParsedTrack {
    var number: Int
    var title: String
    var performer: String?
    var indexStartSeconds: Double
}

enum CUEParser {
    static func parse(url: URL) throws -> ParsedCUE {
        let text = try CUEFileReader.readText(from: url)
        return parse(text: text)
    }

    static func parse(text: String) -> ParsedCUE {
        var fileName = ""
        var albumTitle = ""
        var albumPerformer = ""
        var genre: String?
        var date: String?
        var discID: String?
        var comment: String?
        var artworkFileName: String?

        var tracks: [ParsedTrack] = []
        var currentTrackNumber: Int?
        var currentTrackTitle = ""
        var currentTrackPerformer: String?
        var currentIndexStart: Double?

        func flushTrack() {
            guard let num = currentTrackNumber, let start = currentIndexStart else { return }
            tracks.append(
                ParsedTrack(
                    number: num,
                    title: currentTrackTitle.isEmpty ? "Track \(num)" : currentTrackTitle,
                    performer: currentTrackPerformer,
                    indexStartSeconds: start
                )
            )
            currentTrackNumber = nil
            currentTrackTitle = ""
            currentTrackPerformer = nil
            currentIndexStart = nil
        }

        let lines = text.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }

            if line.uppercased().hasPrefix("FILE ") {
                flushTrack()
                if let quoted = firstQuotedString(in: line) {
                    fileName = quoted
                }
                continue
            }

            if line.uppercased().hasPrefix("TRACK ") {
                flushTrack()
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2, let num = Int(parts[1]) {
                    currentTrackNumber = num
                }
                continue
            }

            if line.uppercased().hasPrefix("INDEX ") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 3, let indexNumber = Int(parts[1]) {
                    let seconds = cueTimeToSeconds(String(parts[2]))
                    if indexNumber == 1 {
                        currentIndexStart = seconds
                    } else if indexNumber == 0, currentIndexStart == nil {
                        currentIndexStart = seconds
                    }
                }
                continue
            }

            if line.uppercased().hasPrefix("TITLE ") {
                let value = quotedOrRemainder(line, keyword: "TITLE")
                if currentTrackNumber != nil {
                    currentTrackTitle = value
                } else {
                    albumTitle = value
                }
                continue
            }

            if line.uppercased().hasPrefix("PERFORMER ") {
                let value = quotedOrRemainder(line, keyword: "PERFORMER")
                if currentTrackNumber != nil {
                    currentTrackPerformer = value
                } else {
                    albumPerformer = value
                }
                continue
            }

            if line.uppercased().hasPrefix("REM ") {
                let rem = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                let upper = rem.uppercased()
                if upper.hasPrefix("GENRE ") {
                    genre = String(rem.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if upper.hasPrefix("DATE ") {
                    date = String(rem.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                } else if upper.hasPrefix("DISCID ") || upper.hasPrefix("DISC_ID ") {
                    discID = rem.components(separatedBy: " ").dropFirst().joined(separator: " ")
                } else if upper.hasPrefix("COMMENT ") {
                    comment = String(rem.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                } else if upper.hasPrefix("COVER ") {
                    artworkFileName = quotedOrRemainder(rem, keyword: "COVER")
                }
            }
        }
        flushTrack()

        tracks.sort { $0.number < $1.number }

        return ParsedCUE(
            flacFileName: fileName,
            title: albumTitle,
            performer: albumPerformer,
            genre: genre,
            date: date,
            discID: discID,
            comment: comment,
            artworkFileName: artworkFileName,
            tracks: tracks
        )
    }

    /// CUE time: MM:SS:FF (frames are 1/75 second)
    static func cueTimeToSeconds(_ time: String) -> Double {
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]),
              let frames = Int(parts[2]) else {
            return 0
        }
        return Double(minutes * 60 + seconds) + Double(frames) / 75.0
    }

    private static func firstQuotedString(in line: String) -> String? {
        guard let start = line.firstIndex(of: "\"") else { return nil }
        let after = line.index(after: start)
        guard let end = line[after...].firstIndex(of: "\"") else { return nil }
        return String(line[after..<end])
    }

    private static func quotedOrRemainder(_ line: String, keyword: String) -> String {
        if let q = firstQuotedString(in: line) { return q }
        let prefix = keyword + " "
        if line.uppercased().hasPrefix(prefix.uppercased()) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
}
