import Foundation

enum PortableLibraryLoader {
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

    static func load(from packageURL: URL) throws -> PortableLibraryPackage {
        let rootURL = packageURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PortableLibraryError.invalidPackage
        }

        let manifestURL = rootURL.appendingPathComponent(PortableLibraryPaths.manifestFilename)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PortableLibraryError.missingManifest
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = iso8601.date(from: value) ?? iso8601Fallback.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date.")
        }

        let manifest = try decoder.decode(PortableLibraryManifest.self, from: data)
        guard manifest.version <= PortableLibraryManifest.currentVersion else {
            throw PortableLibraryError.unsupportedVersion(manifest.version)
        }

        return PortableLibraryPackage(rootURL: rootURL, manifest: manifest)
    }
}

enum PortableLibrarySorting {
    static func sorted(_ albums: [PortableAlbum], by sortMode: LibrarySortMode) -> [PortableAlbum] {
        albums.sorted { lhs, rhs in
            switch sortMode {
            case .artist:
                let artistComparison = lhs.sortArtist.localizedCaseInsensitiveCompare(rhs.sortArtist)
                if artistComparison != .orderedSame {
                    return artistComparison == .orderedAscending
                }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            case .album:
                let albumComparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
                if albumComparison != .orderedSame {
                    return albumComparison == .orderedAscending
                }
                return lhs.sortArtist.localizedCaseInsensitiveCompare(rhs.sortArtist) == .orderedAscending
            }
        }
    }

    static func sections(
        from albums: [PortableAlbum],
        sortMode: LibrarySortMode,
        groupMode: PortableLibraryGroupMode
    ) -> [PortableAlbumSection] {
        let sorted = sorted(albums, by: sortMode)

        switch groupMode {
        case .none:
            return [PortableAlbumSection(id: "all", title: "", albums: sorted)]
        case .artist:
            let grouped = Dictionary(grouping: sorted) { $0.sortArtist }
            return grouped.keys
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { key in
                    PortableAlbumSection(
                        id: key,
                        title: key,
                        albums: grouped[key] ?? []
                    )
                }
        case .parentFolder:
            return [PortableAlbumSection(id: "all", title: "", albums: sorted)]
        }
    }
}

enum PortableLibraryError: LocalizedError {
    case invalidPackage
    case missingManifest
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            return "The selected item is not a valid FlacNest export package."
        case .missingManifest:
            return "The export package is missing manifest.json."
        case .unsupportedVersion(let version):
            return "Export package version \(version) is not supported by this app."
        }
    }
}
