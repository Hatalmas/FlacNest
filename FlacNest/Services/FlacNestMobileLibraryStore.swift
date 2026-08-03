import Foundation

enum FlacNestMobileLibraryStore {
    static let xmlFilename = MobileLibraryPaths.xmlFilename

    static func save(
        library: FlacNestLibrary,
        albumMP3Paths: [String: String],
        to exportDirectory: URL
    ) throws {
        let url = exportDirectory.appendingPathComponent(xmlFilename, isDirectory: false)
        let doc = makeMobileXMLDocument(library: library, albumMP3Paths: albumMP3Paths)
        let data = doc.xmlData(options: [.nodePrettyPrint])
        try data.write(to: url, options: .atomic)
    }

    private static func makeMobileXMLDocument(
        library: FlacNestLibrary,
        albumMP3Paths: [String: String]
    ) -> XMLDocument {
        let root = XMLElement(name: "flacnest")
        root.setAttributesWith(["version": String(library.version)])

        let scannedAt = XMLElement(name: "scannedAt")
        scannedAt.stringValue = formatDate(library.scannedAt)
        root.addChild(scannedAt)

        for album in library.albums {
            root.addChild(makeMobileFileElement(album, mp3RelativePath: albumMP3Paths[album.id]))
        }

        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"
        doc.characterEncoding = "UTF-8"
        return doc
    }

    private static func makeMobileFileElement(_ album: LibraryAlbum, mp3RelativePath: String?) -> XMLElement {
        var attributes: [String: String] = [
            "id": album.id,
            "cue": album.cueRelativePath,
            "title": album.title,
            "performer": album.performer,
            "parentFolder": album.parentDirectoryName,
        ]

        if let mp3RelativePath {
            attributes["mp3"] = mp3RelativePath
        }

        if let genre = album.genre { attributes["genre"] = genre }
        if let date = album.date { attributes["date"] = date }
        if let discID = album.discID { attributes["discID"] = discID }
        if let comment = album.comment { attributes["comment"] = comment }
        if let barcode = album.barcode { attributes["barcode"] = barcode }
        if album.isFavorite { attributes["favorite"] = "true" }

        let fileElement = XMLElement(name: "file")
        fileElement.setAttributesWith(attributes)

        if let artwork = album.artworkRelativePath {
            let art = XMLElement(name: "artwork")
            art.setAttributesWith(["path": artwork])
            fileElement.addChild(art)
        }

        for track in album.tracks {
            var trackAttributes: [String: String] = [
                "id": track.id,
                "number": String(track.number),
                "title": track.title,
                "start": formatSeconds(track.startSeconds),
            ]
            if let performer = track.performer { trackAttributes["performer"] = performer }
            if let end = track.endSeconds { trackAttributes["end"] = formatSeconds(end) }

            let trackElement = XMLElement(name: "track")
            trackElement.setAttributesWith(trackAttributes)
            fileElement.addChild(trackElement)
        }

        return fileElement
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func formatDate(_ date: Date) -> String {
        iso8601.string(from: date)
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
