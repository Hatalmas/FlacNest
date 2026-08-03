import Foundation

enum FlacNestMobileLibraryLoader {
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

    static func load(from exportRoot: URL) throws -> MobileLibraryPackage {
        let rootURL = exportRoot.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MobileLibraryError.invalidExportRoot
        }

        let xmlURL = rootURL.appendingPathComponent(MobileLibraryPaths.xmlFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: xmlURL.path) else {
            throw MobileLibraryError.missingManifest
        }

        let data = try Data(contentsOf: xmlURL)
        let library = try parseXML(data)
        return MobileLibraryPackage(rootURL: rootURL, library: library)
    }

    private static func parseXML(_ data: Data) throws -> MobileLibrary {
        let parser = MobileLibraryXMLParser(data: data)
        guard parser.parse() else {
            throw parser.parserError ?? MobileLibraryError.invalidManifest
        }
        guard let library = parser.library else {
            throw MobileLibraryError.invalidManifest
        }
        return library
    }

    fileprivate static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = iso8601.date(from: value) { return date }
        return iso8601Fallback.date(from: value)
    }

    fileprivate static func parseBoolAttribute(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.lowercased() {
        case "true", "1", "yes":
            return true
        default:
            return false
        }
    }
}

private final class MobileLibraryXMLParser: NSObject, XMLParserDelegate {
    private(set) var library: MobileLibrary?
    private(set) var parserError: Error?

    private var version = MobileLibrary.currentVersion
    private var scannedAt = Date()
    private var albums: [MobileLibraryAlbum] = []
    private var currentFileAttributes: [String: String] = [:]
    private var currentArtworkPath: String?
    private var currentTracks: [MobileLibraryTrack] = []
    private var scannedAtText = ""
    private var currentElement = ""
    private let xmlParser: XMLParser

    init(data: Data) {
        xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() -> Bool {
        xmlParser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        switch elementName {
        case "flacnest":
            if let versionString = attributeDict["version"], let parsedVersion = Int(versionString) {
                version = parsedVersion
            }
        case "file":
            currentFileAttributes = attributeDict
            currentArtworkPath = nil
            currentTracks = []
        case "artwork":
            currentArtworkPath = attributeDict["path"]
        case "track":
            guard
                let numberString = attributeDict["number"],
                let number = Int(numberString),
                let title = attributeDict["title"],
                let startString = attributeDict["start"],
                let start = Double(startString)
            else { return }

            let end = attributeDict["end"].flatMap(Double.init)
            let trackID = attributeDict["id"] ?? "\(currentFileAttributes["cue"] ?? currentFileAttributes["id"] ?? "track")#\(number)"
            currentTracks.append(
                MobileLibraryTrack(
                    id: trackID,
                    number: number,
                    title: title,
                    performer: attributeDict["performer"],
                    startSeconds: start,
                    endSeconds: end
                )
            )
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentElement == "scannedAt" else { return }
        scannedAtText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "scannedAt":
            if let date = FlacNestMobileLibraryLoader.parseDate(scannedAtText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                scannedAt = date
            }
            scannedAtText = ""
        case "file":
            if let album = makeAlbum(from: currentFileAttributes, artworkPath: currentArtworkPath, tracks: currentTracks) {
                albums.append(album)
            }
            currentFileAttributes = [:]
            currentArtworkPath = nil
            currentTracks = []
        case "flacnest":
            var library = MobileLibrary(scannedAt: scannedAt, albums: albums)
            library.version = version
            self.library = library
        default:
            break
        }

        if currentElement == elementName {
            currentElement = ""
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parserError = parseError
    }

    private func makeAlbum(from attributes: [String: String], artworkPath: String?, tracks: [MobileLibraryTrack]) -> MobileLibraryAlbum? {
        guard
            let id = attributes["id"],
            let mp3 = attributes["mp3"]
        else { return nil }

        let cue = attributes["cue"] ?? id
        return MobileLibraryAlbum(
            id: id,
            cueRelativePath: cue,
            mp3RelativePath: mp3,
            title: attributes["title"] ?? "",
            performer: attributes["performer"] ?? "",
            parentFolder: attributes["parentFolder"] ?? "Unknown",
            genre: attributes["genre"],
            date: attributes["date"],
            discID: attributes["discID"],
            comment: attributes["comment"],
            barcode: attributes["barcode"],
            isFavorite: FlacNestMobileLibraryLoader.parseBoolAttribute(attributes["favorite"]),
            artworkRelativePath: artworkPath,
            tracks: tracks
        )
    }
}

enum MobileLibraryError: LocalizedError {
    case invalidExportRoot
    case missingManifest
    case invalidManifest

    var errorDescription: String? {
        switch self {
        case .invalidExportRoot:
            return "The selected folder is not a valid export directory."
        case .missingManifest:
            return "The export folder is missing flacnestmobile.xml."
        case .invalidManifest:
            return "flacnestmobile.xml is not a valid FlacNest mobile library file."
        }
    }
}
