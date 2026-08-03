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
