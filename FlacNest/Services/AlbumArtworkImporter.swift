import AppKit
import Foundation
import UniformTypeIdentifiers

struct AlbumArtworkReference: Equatable {
    var path: String
    var bookmark: Data?
}

enum AlbumArtworkImporter {
    private static var accessedArtworkURLs: Set<URL> = []

    @MainActor
    static func chooseImageFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Album Artwork"
        panel.message = "Select an image. FlacNest copies it into the Artwork folder next to flacnest.xml."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    static func importArtwork(from sourceURL: URL, album: LibraryAlbum) throws -> AlbumArtworkReference {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let path = try AlbumArtworkStore.ingest(
            from: sourceURL,
            albumID: album.id,
            replacing: album.artworkRelativePath,
            libraryRoot: AppSettings.libraryRootURL
        )
        return AlbumArtworkReference(path: path, bookmark: nil)
    }

    static func artworkURL(for album: LibraryAlbum, libraryRoot: URL?) -> URL? {
        AlbumArtworkStore.artworkURL(for: album, libraryRoot: libraryRoot)
    }

    static func legacyArtworkURL(for album: LibraryAlbum, libraryRoot: URL?) -> URL? {
        guard let art = album.artworkRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !art.isEmpty else {
            return nil
        }

        if art.hasPrefix("/") {
            guard let rootPath = libraryRoot?.standardizedFileURL.path,
                  art == rootPath || art.hasPrefix(rootPath + "/") else {
                return nil
            }
            return URL(fileURLWithPath: art)
        }

        guard let libraryRoot else { return nil }
        return libraryRoot.appendingPathComponent(art)
    }

    static func stopAccessingArtwork() {
        for url in accessedArtworkURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedArtworkURLs.removeAll()
    }

    private static func resolveSecurityScopedURL(from bookmark: Data) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }

        if url.startAccessingSecurityScopedResource() {
            accessedArtworkURLs.insert(url)
        }
        return url
    }
}

enum AlbumArtworkImporterError: LocalizedError {
    case sourceFileNotFound
    case invalidArtworkSelection
    case unreadableImage
    case artworkStoreUnavailable

    var errorDescription: String? {
        switch self {
        case .sourceFileNotFound:
            return "The selected image file could not be found."
        case .invalidArtworkSelection:
            return "Choose an image file, not the library folder itself."
        case .unreadableImage:
            return "FlacNest could not read that image. Try JPEG or PNG, or export it again."
        case .artworkStoreUnavailable:
            return "Set a library folder or custom flacnest.xml location before adding artwork."
        }
    }
}
