import AppKit
import Foundation
import UniformTypeIdentifiers

enum AlbumArtworkImporter {
    @MainActor
    static func chooseImageFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Album Artwork"
        panel.message = "Select a JPEG or PNG image for this album."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png]
        panel.prompt = "Choose"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    static func importArtwork(from sourceURL: URL, album: LibraryAlbum, libraryRoot: URL) throws -> String {
        let albumDirectory = libraryRoot
            .appendingPathComponent(album.cueRelativePath)
            .deletingLastPathComponent()

        let fileExtension = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let destinationURL = albumDirectory.appendingPathComponent("cover.\(fileExtension)")

        let fileManager = FileManager.default
        if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return relativePath(from: libraryRoot.path, to: destinationURL.path)
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
