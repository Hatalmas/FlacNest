import AppKit
import Foundation
import UniformTypeIdentifiers

enum AlbumArtworkImporter {
    @MainActor
    static func chooseImageFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Album Artwork"
        panel.message = "Select an image to reference in metadata. The file is not copied."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png]
        panel.prompt = "Choose"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    static func referenceArtwork(from sourceURL: URL, album: LibraryAlbum, libraryRoot: URL) throws -> String {
        let source = sourceURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw AlbumArtworkImporterError.sourceFileNotFound
        }

        let root = libraryRoot.standardizedFileURL
        let rootPath = root.path
        let sourcePath = source.path

        if sourcePath == rootPath {
            throw AlbumArtworkImporterError.invalidArtworkSelection
        }

        if sourcePath.hasPrefix(rootPath + "/") {
            return relativePath(from: rootPath, to: sourcePath)
        }

        return sourcePath
    }

    static func artworkURL(for album: LibraryAlbum, libraryRoot: URL?) -> URL? {
        guard let art = album.artworkRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !art.isEmpty else {
            return nil
        }

        if art.hasPrefix("/") {
            return URL(fileURLWithPath: art)
        }

        guard let libraryRoot else { return nil }
        return libraryRoot.appendingPathComponent(art)
    }

    private static func relativePath(from root: String, to target: String) -> String {
        var rootNorm = root
        if rootNorm.hasSuffix("/") { rootNorm.removeLast() }
        if target.hasPrefix(rootNorm + "/") {
            return String(target.dropFirst(rootNorm.count + 1))
        }
        return target
    }
}

enum AlbumArtworkImporterError: LocalizedError {
    case sourceFileNotFound
    case invalidArtworkSelection

    var errorDescription: String? {
        switch self {
        case .sourceFileNotFound:
            return "The selected image file could not be found."
        case .invalidArtworkSelection:
            return "Choose an image file, not the library folder itself."
        }
    }
}
