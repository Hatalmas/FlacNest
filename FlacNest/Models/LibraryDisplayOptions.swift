import Foundation

enum LibraryGroupMode: String, CaseIterable, Identifiable {
    case none
    case artist
    case parentDirectory

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .artist: return "Artist"
        case .parentDirectory: return "Parent Folder"
        }
    }
}

struct LibraryAlbumSection: Identifiable {
    let id: String
    let title: String
    let albums: [LibraryAlbum]
}

extension LibraryAlbum {
    var albumDirectoryRelativePath: String {
        (cueRelativePath as NSString).deletingLastPathComponent
    }

    /// Parent of the folder containing the CUE file (often the artist folder).
    var parentDirectoryName: String {
        let parentPath = (albumDirectoryRelativePath as NSString).deletingLastPathComponent
        let name = (parentPath as NSString).lastPathComponent
        return name.isEmpty ? "Unknown" : name
    }

    var sortArtist: String {
        let trimmed = performer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? parentDirectoryName : trimmed
    }

    func matchesLibraryFilter(_ query: String) -> Bool {
        LibraryFilter.matches(
            query: query,
            artist: sortArtist,
            albumTitle: displayTitle,
            tracks: tracks.map { ($0.title, $0.performer) }
        )
    }
}

enum LibraryAlbumSorting {
    static func sorted(_ albums: [LibraryAlbum], by sortMode: LibrarySortMode) -> [LibraryAlbum] {
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
        from albums: [LibraryAlbum],
        sortMode: LibrarySortMode,
        groupMode: LibraryGroupMode
    ) -> [LibraryAlbumSection] {
        let sorted = sorted(albums, by: sortMode)

        switch groupMode {
        case .none:
            return [LibraryAlbumSection(id: "all", title: "", albums: sorted)]
        case .artist:
            return groupedSections(sorted, groupKey: \.sortArtist)
        case .parentDirectory:
            return groupedSections(sorted, groupKey: \.parentDirectoryName)
        }
    }

    private static func groupedSections(
        _ albums: [LibraryAlbum],
        groupKey: KeyPath<LibraryAlbum, String>
    ) -> [LibraryAlbumSection] {
        let grouped = Dictionary(grouping: albums) { album in
            album[keyPath: groupKey]
        }

        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { key in
                LibraryAlbumSection(
                    id: key,
                    title: key,
                    albums: grouped[key] ?? []
                )
            }
    }
}

extension Array where Element == LibraryAlbumSection {
    func filtered(by query: String) -> [LibraryAlbumSection] {
        guard !LibraryFilter.normalizedQuery(query).isEmpty else { return self }
        return compactMap { section in
            let albums = section.albums.filter { $0.matchesLibraryFilter(query) }
            guard !albums.isEmpty else { return nil }
            return LibraryAlbumSection(id: section.id, title: section.title, albums: albums)
        }
    }
}
