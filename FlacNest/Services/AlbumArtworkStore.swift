import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AlbumArtworkStore {
    static let directoryName = "Artwork"

    static func directoryURL(libraryRoot: URL? = AppSettings.libraryRootURL) -> URL? {
        if AppSettings.useCustomLibraryXMLLocation, let directory = AppSettings.libraryXMLDirectoryURL {
            return directory.appendingPathComponent(directoryName, isDirectory: true)
        }
        guard let libraryRoot else { return nil }
        return libraryRoot.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func isStoredPath(_ path: String?) -> Bool {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return false
        }
        return path == directoryName || path.hasPrefix(directoryName + "/")
    }

    static func storedPath(forAlbumID albumID: String, pathExtension: String) -> String {
        let ext = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolved = ext.isEmpty ? "jpg" : ext
        return "\(directoryName)/\(fileName(forAlbumID: albumID, pathExtension: resolved))"
    }

    static func artworkURL(for album: LibraryAlbum, libraryRoot: URL?) -> URL? {
        guard let art = album.artworkRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !art.isEmpty else {
            return nil
        }

        if isStoredPath(art) {
            return fileURL(forStoredPath: art, libraryRoot: libraryRoot)
        }

        return AlbumArtworkImporter.legacyArtworkURL(for: album, libraryRoot: libraryRoot)
    }

    @discardableResult
    static func collect(into library: inout FlacNestLibrary, libraryRoot: URL?) -> Bool {
        var changed = false
        for index in library.albums.indices {
            if collect(album: &library.albums[index], libraryRoot: libraryRoot) {
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    static func collect(album: inout LibraryAlbum, libraryRoot: URL?) -> Bool {
        let previousPath = album.artworkRelativePath
        let previousBookmark = album.artworkBookmark

        if isStoredPath(previousPath),
           fileURL(forStoredPath: previousPath, libraryRoot: libraryRoot) != nil {
            if previousBookmark != nil {
                album.artworkBookmark = nil
                return true
            }
            return false
        }

        guard let sourceURL = AlbumArtworkImporter.legacyArtworkURL(for: album, libraryRoot: libraryRoot),
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            return false
        }

        do {
            let stored = try ingest(
                from: sourceURL,
                albumID: album.id,
                replacing: previousPath,
                libraryRoot: libraryRoot
            )
            album.artworkRelativePath = stored
            album.artworkBookmark = nil
            return stored != previousPath || previousBookmark != nil
        } catch {
            return false
        }
    }

    static func ingest(
        from sourceURL: URL,
        albumID: String,
        replacing previousPath: String?,
        libraryRoot: URL?
    ) throws -> String {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let source = sourceURL.standardizedFileURL
        let artwork = try loadArtworkFile(from: source)

        guard let storeURL = directoryURL(libraryRoot: libraryRoot) else {
            throw AlbumArtworkImporterError.artworkStoreUnavailable
        }

        let storedRelativePath = storedPath(forAlbumID: albumID, pathExtension: artwork.ext)
        let destination = storeURL.appendingPathComponent((storedRelativePath as NSString).lastPathComponent)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: storeURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try artwork.data.write(to: destination, options: .atomic)

        if let previousPath,
           isStoredPath(previousPath),
           previousPath != storedRelativePath,
           let previousURL = fileURL(forStoredPath: previousPath, libraryRoot: libraryRoot) {
            try? fileManager.removeItem(at: previousURL)
        }

        return storedRelativePath
    }

    static func removeStoredArtwork(for album: LibraryAlbum, libraryRoot: URL? = AppSettings.libraryRootURL) {
        guard isStoredPath(album.artworkRelativePath),
              let url = fileURL(forStoredPath: album.artworkRelativePath, libraryRoot: libraryRoot) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    static func moveStore(from oldXMLURL: URL, to newXMLURL: URL) throws {
        let oldStore = oldXMLURL.deletingLastPathComponent().appendingPathComponent(directoryName, isDirectory: true)
        let newStore = newXMLURL.deletingLastPathComponent().appendingPathComponent(directoryName, isDirectory: true)
        let fileManager = FileManager.default

        guard oldStore.standardizedFileURL != newStore.standardizedFileURL,
              fileManager.fileExists(atPath: oldStore.path) else {
            return
        }

        if fileManager.fileExists(atPath: newStore.path) {
            let files = try fileManager.contentsOfDirectory(at: oldStore, includingPropertiesForKeys: nil)
            for file in files where !file.hasDirectoryPath {
                let destination = newStore.appendingPathComponent(file.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: file, to: destination)
            }
            try? fileManager.removeItem(at: oldStore)
        } else {
            try fileManager.moveItem(at: oldStore, to: newStore)
        }
    }

    private static func loadArtworkFile(from url: URL) throws -> (data: Data, ext: String) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw AlbumArtworkImporterError.sourceFileNotFound
        }
        guard !data.isEmpty else {
            throw AlbumArtworkImporterError.unreadableImage
        }

        if isJPEG(data) {
            return (data, "jpg")
        }
        if isPNG(data) {
            return (data, "png")
        }
        if let jpeg = jpegData(from: data) {
            return (jpeg, "jpg")
        }
        throw AlbumArtworkImporterError.unreadableImage
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    private static func jpegData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImageFromSource(destination, source, 0, [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationData as Data
    }

    private static func fileURL(forStoredPath path: String?, libraryRoot: URL?) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              isStoredPath(path),
              let storeURL = directoryURL(libraryRoot: libraryRoot) else {
            return nil
        }
        let url = storeURL.deletingLastPathComponent().appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func fileName(forAlbumID albumID: String, pathExtension: String) -> String {
        let digest = SHA256.hash(data: Data(albumID.utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "\(hex).\(pathExtension)"
    }
}
