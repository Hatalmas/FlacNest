import AppKit
import CryptoKit
import Foundation

struct PlayingNowToken: Equatable {
    static let scheme = "flacnest"
    static let host = "now"
    static let currentVersion = 1

    var albumID: String
    var cueRelativePath: String
    var flacRelativePath: String
    var filename: String
    var pathHash: String
    var nameHash: String
    var trackIndex: Int
    var positionSeconds: Double

    init(
        albumID: String,
        cueRelativePath: String,
        flacRelativePath: String,
        filename: String,
        pathHash: String,
        nameHash: String,
        trackIndex: Int,
        positionSeconds: Double
    ) {
        self.albumID = albumID
        self.cueRelativePath = cueRelativePath
        self.flacRelativePath = flacRelativePath
        self.filename = filename
        self.pathHash = pathHash
        self.nameHash = nameHash
        self.trackIndex = trackIndex
        self.positionSeconds = positionSeconds
    }

    init?(album: LibraryAlbum, trackIndex: Int, positionSeconds: Double) {
        let flac = album.flacRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flac.isEmpty else { return nil }

        let filename = (flac as NSString).lastPathComponent
        albumID = album.id
        cueRelativePath = album.cueRelativePath
        flacRelativePath = flac
        self.filename = filename
        pathHash = Self.digest(flac)
        nameHash = Self.digest(filename)
        self.trackIndex = max(0, trackIndex)
        self.positionSeconds = max(0, positionSeconds)
    }

    var encodedString: String {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/v\(Self.currentVersion)"
        components.queryItems = [
            URLQueryItem(name: "id", value: albumID),
            URLQueryItem(name: "cue", value: cueRelativePath),
            URLQueryItem(name: "flac", value: flacRelativePath),
            URLQueryItem(name: "file", value: filename),
            URLQueryItem(name: "h", value: pathHash),
            URLQueryItem(name: "nh", value: nameHash),
            URLQueryItem(name: "i", value: String(trackIndex)),
            URLQueryItem(name: "t", value: String(format: "%.3f", positionSeconds)),
        ]
        return components.string ?? ""
    }

    static func parse(_ raw: String) -> PlayingNowToken? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard let tokenRange = trimmed.range(of: "\(scheme)://\(host)/") else { return nil }

        let candidate = String(trimmed[tokenRange.lowerBound...])
            .components(separatedBy: .whitespacesAndNewlines)
            .first?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard let candidate, let url = URL(string: candidate) else { return nil }
        return parse(url)
    }

    static func parse(_ url: URL) -> PlayingNowToken? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            guard let value = item.value else { continue }
            items[item.name] = value
        }

        let flac = items["flac"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filename = items["file"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (flac as NSString).lastPathComponent
        guard !flac.isEmpty || !(items["id"] ?? "").isEmpty || !filename.isEmpty else {
            return nil
        }

        return PlayingNowToken(
            albumID: items["id"] ?? "",
            cueRelativePath: items["cue"] ?? items["id"] ?? "",
            flacRelativePath: flac,
            filename: filename,
            pathHash: items["h"] ?? "",
            nameHash: items["nh"] ?? "",
            trackIndex: Int(items["i"] ?? "") ?? 0,
            positionSeconds: Double(items["t"] ?? "") ?? 0
        )
    }

    func matchingAlbum(in albums: [LibraryAlbum]) -> LibraryAlbum? {
        if !albumID.isEmpty, let album = albums.first(where: { $0.id == albumID }) {
            return album
        }
        if !cueRelativePath.isEmpty,
           let album = albums.first(where: { Self.pathsMatch($0.cueRelativePath, cueRelativePath) }) {
            return album
        }
        if !flacRelativePath.isEmpty {
            if let album = albums.first(where: { $0.flacRelativePath == flacRelativePath }) {
                return album
            }
            if let album = albums.first(where: { Self.pathsMatch($0.flacRelativePath, flacRelativePath) }) {
                return album
            }
        }
        if !pathHash.isEmpty,
           let album = albums.first(where: { Self.digest($0.flacRelativePath) == pathHash }) {
            return album
        }

        if !filename.isEmpty {
            let nameMatches = albums.filter {
                Self.pathsMatch(($0.flacRelativePath as NSString).lastPathComponent, filename)
            }
            if nameMatches.count == 1 {
                return nameMatches[0]
            }
        }
        if !nameHash.isEmpty {
            let hashMatches = albums.filter {
                Self.digest(($0.flacRelativePath as NSString).lastPathComponent) == nameHash
            }
            if hashMatches.count == 1 {
                return hashMatches[0]
            }
        }
        return nil
    }

    static func digest(_ string: String) -> String {
        let normalized = string
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let hash = SHA256.hash(data: Data(normalized.utf8))
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func pathsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

enum PlayingNowResumeError: LocalizedError {
    case noAlbumLoaded
    case emptyClipboard
    case invalidToken
    case libraryUnavailable
    case noMatchingAlbum
    case failedToOpen(String)

    var errorDescription: String? {
        switch self {
        case .noAlbumLoaded:
            return "Load an album before copying a Playing Now token."
        case .emptyClipboard:
            return "The clipboard is empty."
        case .invalidToken:
            return "The clipboard doesn’t contain a Playing Now token."
        case .libraryUnavailable:
            return "The library isn’t loaded yet."
        case .noMatchingAlbum:
            return "No album in this library matches that Playing Now token. Import the same metadata on this Mac, or check that the FLAC is in the library folder."
        case .failedToOpen(let message):
            return message
        }
    }
}

enum PlayingNowTokenPasteboard {
    static func copy(_ token: PlayingNowToken) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(token.encodedString, forType: .string)
    }

    static func tokenFromClipboard() throws -> PlayingNowToken {
        guard let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw PlayingNowResumeError.emptyClipboard
        }
        guard let token = PlayingNowToken.parse(raw) else {
            throw PlayingNowResumeError.invalidToken
        }
        return token
    }

    static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t Resume from Token"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
