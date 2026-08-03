import Foundation

enum LibrarySortMode: String, CaseIterable, Identifiable, Codable {
    case artist
    case album

    var id: String { rawValue }

    var label: String {
        switch self {
        case .artist: return "Artist"
        case .album: return "Album Name"
        }
    }
}

struct PortableAlbumSection: Identifiable, Equatable {
    let id: String
    let title: String
    let albums: [PortableAlbum]
}

enum PortableLibraryGroupMode: String, CaseIterable, Identifiable, Codable {
    case none
    case artist
    case parentFolder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .artist: return "Artist"
        case .parentFolder: return "Parent Folder"
        }
    }
}

enum MobileLibrarySorting {
    static func sorted(_ albums: [MobileLibraryAlbum], by sortMode: LibrarySortMode) -> [MobileLibraryAlbum] {
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
        from albums: [MobileLibraryAlbum],
        sortMode: LibrarySortMode,
        groupMode: PortableLibraryGroupMode
    ) -> [MobileLibraryAlbumSection] {
        let sorted = sorted(albums, by: sortMode)

        switch groupMode {
        case .none:
            return [MobileLibraryAlbumSection(id: "all", title: "", albums: sorted)]
        case .artist:
            return groupedSections(sorted, groupKey: \.sortArtist)
        case .parentFolder:
            return groupedSections(sorted, groupKey: \.parentFolder)
        }
    }

    private static func groupedSections(
        _ albums: [MobileLibraryAlbum],
        groupKey: KeyPath<MobileLibraryAlbum, String>
    ) -> [MobileLibraryAlbumSection] {
        let grouped = Dictionary(grouping: albums) { album in
            album[keyPath: groupKey]
        }

        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { key in
                MobileLibraryAlbumSection(
                    id: key,
                    title: key,
                    albums: grouped[key] ?? []
                )
            }
    }
}

enum LibraryFilter {
    static func normalizedQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(
        query: String,
        artist: String,
        albumTitle: String,
        tracks: [(title: String, performer: String?)]
    ) -> Bool {
        let needle = normalizedQuery(query).lowercased()
        guard !needle.isEmpty else { return true }

        if artist.lowercased().contains(needle) { return true }
        if albumTitle.lowercased().contains(needle) { return true }

        for track in tracks {
            if track.title.lowercased().contains(needle) { return true }
            if let performer = track.performer?.trimmingCharacters(in: .whitespacesAndNewlines),
               !performer.isEmpty,
               performer.lowercased().contains(needle) {
                return true
            }
        }
        return false
    }
}

extension MobileLibraryAlbum {
    func matchesLibraryFilter(_ query: String) -> Bool {
        LibraryFilter.matches(
            query: query,
            artist: sortArtist,
            albumTitle: displayTitle,
            tracks: tracks.map { ($0.title, $0.performer) }
        )
    }
}

extension Array where Element == MobileLibraryAlbumSection {
    func filtered(by query: String) -> [MobileLibraryAlbumSection] {
        guard !LibraryFilter.normalizedQuery(query).isEmpty else { return self }
        return compactMap { section in
            let albums = section.albums.filter { $0.matchesLibraryFilter(query) }
            guard !albums.isEmpty else { return nil }
            return MobileLibraryAlbumSection(id: section.id, title: section.title, albums: albums)
        }
    }
}
