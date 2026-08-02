import Foundation

enum FlacNestLibraryStore {
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Fallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func load(from url: URL) throws -> FlacNestLibrary {
        let data = try Data(contentsOf: url)
        if data.isEmpty {
            return FlacNestLibrary()
        }

        if isPropertyListXML(data) {
            if let library = try? loadLegacyPropertyList(data) {
                return library
            }
        }

        if let library = try? loadFlacNestXML(data) {
            return library
        }

        if let library = try? loadLegacyPropertyList(data) {
            return library
        }

        throw FlacNestLibraryStoreError.unrecognizedFormat
    }

    static func save(_ library: FlacNestLibrary, to url: URL) throws {
        let doc = makeFlacNestXMLDocument(library)
        let data = doc.xmlData(options: [.nodePrettyPrint])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - FlacNest XML

    private static func loadFlacNestXML(_ data: Data) throws -> FlacNestLibrary {
        let doc = try XMLDocument(data: data, options: [.nodePreserveAll, .nodeCompactEmptyElement])
        guard let root = doc.rootElement(), root.name == "flacnest" else {
            throw FlacNestLibraryStoreError.unrecognizedFormat
        }

        let version = Int(root.attribute(forName: "version")?.stringValue ?? "") ?? FlacNestLibrary.currentVersion
        let scannedAt = parseDate(root.elements(forName: "scannedAt").first?.stringValue) ?? Date()

        var albums: [LibraryAlbum] = []
        for fileElement in root.elements(forName: "file") {
            if let album = parseFileElement(fileElement) {
                albums.append(album)
            }
        }

        var library = FlacNestLibrary(scannedAt: scannedAt, albums: albums)
        library.version = version
        return library
    }

    private static func parseFileElement(_ element: XMLElement) -> LibraryAlbum? {
        guard
            let id = element.attribute(forName: "id")?.stringValue,
            let cue = element.attribute(forName: "cue")?.stringValue,
            let flac = element.attribute(forName: "flac")?.stringValue
        else { return nil }

        let artworkElement = element.elements(forName: "artwork").first
        let artwork = artworkElement?.attribute(forName: "path")?.stringValue
        let artworkBookmark = artworkElement?
            .attribute(forName: "bookmark")?
            .stringValue
            .flatMap { Data(base64Encoded: $0) }

        var tracks: [LibraryTrack] = []
        for trackElement in element.elements(forName: "track") {
            guard
                let numberString = trackElement.attribute(forName: "number")?.stringValue,
                let number = Int(numberString),
                let title = trackElement.attribute(forName: "title")?.stringValue,
                let startString = trackElement.attribute(forName: "start")?.stringValue,
                let start = Double(startString)
            else { continue }

            let performer = trackElement.attribute(forName: "performer")?.stringValue
            let end: Double? = {
                guard let node = trackElement.attribute(forName: "end") else { return nil }
                return Double(node.stringValue ?? "")
            }()
            let trackID = trackElement.attribute(forName: "id")?.stringValue ?? "\(cue)#\(number)"

            tracks.append(
                LibraryTrack(
                    id: trackID,
                    number: number,
                    title: title,
                    performer: performer,
                    startSeconds: start,
                    endSeconds: end
                )
            )
        }

        return LibraryAlbum(
            id: id,
            cueRelativePath: cue,
            flacRelativePath: flac,
            title: element.attribute(forName: "title")?.stringValue ?? "",
            performer: element.attribute(forName: "performer")?.stringValue ?? "",
            genre: element.attribute(forName: "genre")?.stringValue,
            date: element.attribute(forName: "date")?.stringValue,
            discID: element.attribute(forName: "discID")?.stringValue,
            comment: element.attribute(forName: "comment")?.stringValue,
            artworkRelativePath: artwork,
            artworkBookmark: artworkBookmark,
            barcode: element.attribute(forName: "barcode")?.stringValue,
            isFavorite: parseBoolAttribute(element.attribute(forName: "favorite")?.stringValue),
            tracks: tracks
        )
    }

    private static func makeFlacNestXMLDocument(_ library: FlacNestLibrary) -> XMLDocument {
        let root = XMLElement(name: "flacnest")
        root.setAttributesWith(["version": String(library.version)])

        let scannedAt = XMLElement(name: "scannedAt")
        scannedAt.stringValue = formatDate(library.scannedAt)
        root.addChild(scannedAt)

        for album in library.albums {
            root.addChild(makeFileElement(album))
        }

        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"
        doc.characterEncoding = "UTF-8"
        return doc
    }

    private static func makeFileElement(_ album: LibraryAlbum) -> XMLElement {
        var attributes: [String: String] = [
            "id": album.id,
            "cue": album.cueRelativePath,
            "flac": album.flacRelativePath,
            "title": album.title,
            "performer": album.performer,
        ]
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
            var artworkAttributes = ["path": artwork]
            if let bookmark = album.artworkBookmark {
                artworkAttributes["bookmark"] = bookmark.base64EncodedString()
            }
            art.setAttributesWith(artworkAttributes)
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

    // MARK: - Legacy plist support

    private static func isPropertyListXML(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(512), encoding: .utf8)
            ?? String(data: data.prefix(512), encoding: .isoLatin1) else {
            return false
        }
        return text.contains("<plist")
    }

    private static func loadLegacyPropertyList(_ data: Data) throws -> FlacNestLibrary {
        let decoder = PropertyListDecoder()
        return try decoder.decode(FlacNestLibrary.self, from: data)
    }

    private static func parseBoolAttribute(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.lowercased() {
        case "true", "1", "yes":
            return true
        default:
            return false
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = iso8601.date(from: value) { return date }
        return iso8601Fallback.date(from: value)
    }

    private static func formatDate(_ date: Date) -> String {
        iso8601.string(from: date)
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}

enum FlacNestLibraryStoreError: LocalizedError {
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return "flacnest.xml is not a valid FlacNest library file. Use Refresh Library to rebuild it."
        }
    }
}
