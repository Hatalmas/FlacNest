import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum MetadataTransferPackage {
    static let fileName = "export.zip.flacnest"
    static let fileExtension = "flacnest"
    static let manifestFileName = "manifest.json"
    static let libraryFileName = "flacnest.xml"
    static let artworkDirectoryName = "artwork"

    static let contentType = UTType(exportedAs: "com.flacnest.transfer-package", conformingTo: .zip)

    static func isPackage(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension
    }
}

/// Hands packages opened from Finder to the Export to Other Desktop window, opening it when needed.
@MainActor
final class MetadataTransferRequests: ObservableObject {
    static let shared = MetadataTransferRequests()

    @Published private(set) var pendingImportURL: URL?

    private var openWindow: OpenWindowAction?

    func requestImport(of url: URL) {
        pendingImportURL = url
        showWindowIfPossible()
    }

    func registerWindowOpener(_ action: OpenWindowAction) {
        let isFirstRegistration = openWindow == nil
        openWindow = action
        if isFirstRegistration, pendingImportURL != nil {
            showWindowIfPossible()
        }
    }

    func consumePendingImport() -> URL? {
        defer { pendingImportURL = nil }
        return pendingImportURL
    }

    private func showWindowIfPossible() {
        guard let openWindow else { return }
        DockIconVisibility.prepareToShowMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "transferMetadata")
    }
}

struct MetadataTransferManifest: Codable {
    static let currentFormatVersion = 1

    struct Artwork: Codable {
        var albumID: String
        var file: String
        var originalPath: String
        var isLibraryRelative: Bool
    }

    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String?
    var sourceComputerName: String?
    var sourceLibraryRootPath: String?
    var albumCount: Int
    var artwork: [Artwork]
}

struct MetadataTransferArtworkSource {
    let albumID: String
    let sourceURL: URL
    let originalPath: String
    let isLibraryRelative: Bool
}

struct MetadataTransferExportResult {
    let packageURL: URL
    let albumCount: Int
    let artworkCount: Int
    let missingArtworkCount: Int
}

struct MetadataTransferPackageContents {
    let manifest: MetadataTransferManifest
    let library: FlacNestLibrary
    let extractedDirectory: URL
}

struct MetadataTransferInstallResult {
    let library: FlacNestLibrary
    let artworkStoreURL: URL
    let copiedArtworkCount: Int
    let reusedArtworkCount: Int
}

struct MetadataTransferPathResolution {
    var library: FlacNestLibrary
    var foundCount: Int
    var remappedCount: Int
}

enum MetadataTransferError: LocalizedError {
    case libraryEmpty
    case missingManifest
    case missingLibrary
    case newerFormat(Int)

    var errorDescription: String? {
        switch self {
        case .libraryEmpty:
            return "There are no albums to export."
        case .missingManifest:
            return "The package does not contain a FlacNest manifest."
        case .missingLibrary:
            return "The package does not contain flacnest.xml."
        case .newerFormat(let version):
            return "This package was created by a newer version of FlacNest (format \(version)). Update FlacNest on this Mac and try again."
        }
    }
}

// MARK: - Export

enum MetadataTransferExporter {
    static func export(
        library: FlacNestLibrary,
        artwork: [MetadataTransferArtworkSource],
        sourceLibraryRootPath: String?,
        to packageURL: URL,
        progress: (_ completed: Int, _ total: Int) -> Void
    ) throws -> MetadataTransferExportResult {
        guard !library.albums.isEmpty else { throw MetadataTransferError.libraryEmpty }

        let fileManager = FileManager.default
        let partialURL = packageURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(packageURL.lastPathComponent).\(UUID().uuidString).partial")
        defer { try? fileManager.removeItem(at: partialURL) }

        let writer = try ZipArchiveWriter(url: partialURL)
        var manifestArtwork: [MetadataTransferManifest.Artwork] = []
        var entryNameBySourcePath: [String: String] = [:]
        var missingCount = 0

        for (index, source) in artwork.enumerated() {
            let sourcePath = source.sourceURL.standardizedFileURL.path
            let entryName: String
            if let existing = entryNameBySourcePath[sourcePath] {
                entryName = existing
            } else if let data = try? Data(contentsOf: source.sourceURL), !data.isEmpty {
                let ext = source.sourceURL.pathExtension.isEmpty ? "jpg" : source.sourceURL.pathExtension.lowercased()
                entryName = "\(MetadataTransferPackage.artworkDirectoryName)/\(String(format: "%05d", entryNameBySourcePath.count + 1)).\(ext)"
                try writer.addFile(named: entryName, data: data)
                entryNameBySourcePath[sourcePath] = entryName
            } else {
                missingCount += 1
                progress(index + 1, artwork.count)
                continue
            }

            manifestArtwork.append(MetadataTransferManifest.Artwork(
                albumID: source.albumID,
                file: entryName,
                originalPath: source.originalPath,
                isLibraryRelative: source.isLibraryRelative
            ))
            progress(index + 1, artwork.count)
        }

        var portableLibrary = library
        for index in portableLibrary.albums.indices {
            portableLibrary.albums[index].artworkBookmark = nil
        }
        try writer.addFile(
            named: MetadataTransferPackage.libraryFileName,
            data: FlacNestLibraryStore.xmlData(for: portableLibrary)
        )

        let manifest = MetadataTransferManifest(
            formatVersion: MetadataTransferManifest.currentFormatVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            sourceComputerName: Host.current().localizedName,
            sourceLibraryRootPath: sourceLibraryRootPath,
            albumCount: library.albums.count,
            artwork: manifestArtwork
        )
        try writer.addFile(named: MetadataTransferPackage.manifestFileName, data: encoder.encode(manifest))
        try writer.finish()

        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.moveItem(at: partialURL, to: packageURL)

        return MetadataTransferExportResult(
            packageURL: packageURL,
            albumCount: library.albums.count,
            artworkCount: entryNameBySourcePath.count,
            missingArtworkCount: missingCount
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

// MARK: - Import

enum MetadataTransferImporter {
    static func unpack(_ packageURL: URL) throws -> MetadataTransferPackageContents {
        let reader = try ZipArchiveReader(url: packageURL)
        let entries = reader.entries.filter { !$0.isDirectory && !$0.name.hasPrefix("__MACOSX/") }

        guard let manifestEntry = entries
            .filter({ $0.name == MetadataTransferPackage.manifestFileName || $0.name.hasSuffix("/" + MetadataTransferPackage.manifestFileName) })
            .min(by: { $0.name.count < $1.name.count }) else {
            throw MetadataTransferError.missingManifest
        }
        let prefix = String(manifestEntry.name.dropLast(MetadataTransferPackage.manifestFileName.count))

        let manifest = try decoder.decode(MetadataTransferManifest.self, from: reader.contents(of: manifestEntry))
        guard manifest.formatVersion <= MetadataTransferManifest.currentFormatVersion else {
            throw MetadataTransferError.newerFormat(manifest.formatVersion)
        }

        let fileManager = FileManager.default
        let extractedDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FlacNestImport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)

        do {
            for entry in entries where entry.name.hasPrefix(prefix) {
                let relativePath = String(entry.name.dropFirst(prefix.count))
                let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
                guard !components.isEmpty,
                      !relativePath.hasPrefix("/"),
                      !components.contains(where: { $0 == ".." || $0 == "." }) else {
                    throw ZipArchiveError.unsafeEntryPath(entry.name)
                }

                let destination = extractedDirectory.appendingPathComponent(relativePath)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try reader.contents(of: entry).write(to: destination, options: .atomic)
            }

            let libraryURL = extractedDirectory.appendingPathComponent(MetadataTransferPackage.libraryFileName)
            guard fileManager.fileExists(atPath: libraryURL.path) else {
                throw MetadataTransferError.missingLibrary
            }
            let library = try FlacNestLibraryStore.load(from: libraryURL)

            return MetadataTransferPackageContents(
                manifest: manifest,
                library: library,
                extractedDirectory: extractedDirectory
            )
        } catch {
            try? fileManager.removeItem(at: extractedDirectory)
            throw error
        }
    }

    static func matchingAlbumCount(in library: FlacNestLibrary, libraryRoot: URL) -> Int {
        resolveAudioPaths(in: library, libraryRoot: libraryRoot).foundCount
    }

    /// Finds FLACs (and CUE sheets) that moved after a file copy and rewrites those relative paths.
    static func resolveAudioPaths(in library: FlacNestLibrary, libraryRoot: URL) -> MetadataTransferPathResolution {
        MetadataTransferPathResolver.resolve(library, libraryRoot: libraryRoot)
    }

    /// Copies packaged artwork into the app's storage, except library-relative images that already exist under `libraryRoot`.
    static func install(
        _ contents: MetadataTransferPackageContents,
        library remappedLibrary: FlacNestLibrary,
        libraryRoot: URL
    ) throws -> MetadataTransferInstallResult {
        let fileManager = FileManager.default
        let storeURL = try importedArtworkRoot()
            .appendingPathComponent(Self.storeFolderName(), isDirectory: true)
        try fileManager.createDirectory(at: storeURL, withIntermediateDirectories: true)

        let artworkByAlbumID = Dictionary(
            contents.manifest.artwork.map { ($0.albumID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var library = remappedLibrary
        var copiedPathByEntry: [String: String] = [:]
        var reusedCount = 0

        do {
            for index in library.albums.indices {
                let album = library.albums[index]
                library.albums[index].artworkBookmark = nil

                guard let artwork = artworkByAlbumID[album.id] else { continue }

                if artwork.isLibraryRelative,
                   fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(artwork.originalPath).path) {
                    library.albums[index].artworkRelativePath = artwork.originalPath
                    reusedCount += 1
                    continue
                }

                if let copiedPath = copiedPathByEntry[artwork.file] {
                    library.albums[index].artworkRelativePath = copiedPath
                    continue
                }

                let source = contents.extractedDirectory.appendingPathComponent(artwork.file)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = storeURL.appendingPathComponent((artwork.file as NSString).lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
                copiedPathByEntry[artwork.file] = destination.path
                library.albums[index].artworkRelativePath = destination.path
            }
        } catch {
            try? fileManager.removeItem(at: storeURL)
            throw error
        }

        return MetadataTransferInstallResult(
            library: library,
            artworkStoreURL: storeURL,
            copiedArtworkCount: copiedPathByEntry.count,
            reusedArtworkCount: reusedCount
        )
    }

    /// Removes artwork from earlier imports; the imported library replaces the whole library, so only `current` is referenced.
    static func removeImportedArtwork(except current: URL) {
        let fileManager = FileManager.default
        guard let root = try? importedArtworkRoot(),
              let folders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders where folder.standardizedFileURL != current.standardizedFileURL {
            try? fileManager.removeItem(at: folder)
        }
    }

    static func cleanUp(_ contents: MetadataTransferPackageContents) {
        try? FileManager.default.removeItem(at: contents.extractedDirectory)
    }

    private static func importedArtworkRoot() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FlacNest", isDirectory: true)
            .appendingPathComponent("Imported Artwork", isDirectory: true)
    }

    private static func storeFolderName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Path fallback

private enum MetadataTransferPathResolver {
    static func resolve(_ library: FlacNestLibrary, libraryRoot: URL) -> MetadataTransferPathResolution {
        var resolved = library
        let fileManager = FileManager.default
        let rootPath = libraryRoot.standardizedFileURL.path
        let index = AudioFileIndex(root: libraryRoot)

        var foundCount = 0
        var remappedCount = 0

        for albumIndex in resolved.albums.indices {
            var album = resolved.albums[albumIndex]
            let originalCue = album.cueRelativePath
            let originalFlac = album.flacRelativePath
            var didChange = false

            let cueExists = fileExists(originalCue, under: rootPath, fileManager: fileManager)
            let flacExists = fileExists(originalFlac, under: rootPath, fileManager: fileManager)

            if !flacExists, let match = index.bestMatch(for: originalFlac, extension: "flac") {
                album.flacRelativePath = match
                didChange = true
            }

            let flacDirectory = (album.flacRelativePath as NSString).deletingLastPathComponent
            if !cueExists {
                if let sibling = cueBesideFlac(originalCue: originalCue, flacRelativePath: album.flacRelativePath, rootPath: rootPath, fileManager: fileManager) {
                    album.cueRelativePath = sibling
                    didChange = true
                } else if let match = index.bestMatch(for: originalCue, extension: "cue", preferredDirectory: flacDirectory) {
                    album.cueRelativePath = match
                    didChange = true
                }
            }

            let cueNowExists = fileExists(album.cueRelativePath, under: rootPath, fileManager: fileManager)
            let flacNowExists = fileExists(album.flacRelativePath, under: rootPath, fileManager: fileManager)
            guard cueNowExists || flacNowExists else { continue }

            foundCount += 1
            if didChange {
                remappedCount += 1
                album.parentFolder = parentFolder(for: album)
                resolved.albums[albumIndex] = album
            }
        }

        return MetadataTransferPathResolution(
            library: resolved,
            foundCount: foundCount,
            remappedCount: remappedCount
        )
    }

    private static func fileExists(_ relativePath: String, under rootPath: String, fileManager: FileManager) -> Bool {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return false }
        return fileManager.fileExists(atPath: (rootPath as NSString).appendingPathComponent(relativePath))
    }

    private static func cueBesideFlac(
        originalCue: String,
        flacRelativePath: String,
        rootPath: String,
        fileManager: FileManager
    ) -> String? {
        let directory = (flacRelativePath as NSString).deletingLastPathComponent
        let names = [
            (originalCue as NSString).lastPathComponent,
            ((flacRelativePath as NSString).deletingPathExtension as NSString).appendingPathExtension("cue") ?? "",
        ]
        var seen = Set<String>()
        for name in names where !name.isEmpty && seen.insert(name.lowercased()).inserted {
            let relative = directory.isEmpty ? name : (directory as NSString).appendingPathComponent(name)
            if fileExists(relative, under: rootPath, fileManager: fileManager) {
                return relative
            }
        }
        return nil
    }

    private static func parentFolder(for album: LibraryAlbum) -> String {
        let path = album.flacRelativePath.hasPrefix("/") ? album.cueRelativePath : album.flacRelativePath
        return URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
    }
}

private struct AudioFileIndex {
    private let filesByName: [String: [String]]

    init(root: URL) {
        var filesByName: [String: [String]] = [:]
        let rootPath = root.standardizedFileURL.path
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "flac" || ext == "cue" else { continue }
            let relative = Self.relativePath(from: rootPath, to: fileURL.standardizedFileURL.path)
            guard !relative.isEmpty, !relative.hasPrefix("/") else { continue }
            filesByName[fileURL.lastPathComponent.lowercased(), default: []].append(relative)
        }
        self.filesByName = filesByName
    }

    func bestMatch(for originalPath: String, extension expectedExtension: String, preferredDirectory: String? = nil) -> String? {
        let fileName = (originalPath as NSString).lastPathComponent
        guard !fileName.isEmpty else { return nil }

        var candidates = filesByName[fileName.lowercased()] ?? []
        if candidates.isEmpty {
            let stem = (fileName as NSString).deletingPathExtension.lowercased()
            candidates = filesByName.compactMap { name, paths -> [String]? in
                guard (name as NSString).pathExtension == expectedExtension,
                      (name as NSString).deletingPathExtension == stem else { return nil }
                return paths
            }.flatMap { $0 }
        }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        if let preferredDirectory, !preferredDirectory.isEmpty {
            let inPreferred = candidates.filter { candidate in
                (candidate as NSString).deletingLastPathComponent.compare(preferredDirectory, options: .caseInsensitive) == .orderedSame
            }
            if inPreferred.count == 1 { return inPreferred[0] }
            if !inPreferred.isEmpty { candidates = inPreferred }
        }

        let originalComponents = pathComponents(originalPath)
        let scored = candidates.map { candidate -> (String, Int) in
            (candidate, trailingMatchScore(original: originalComponents, candidate: pathComponents(candidate)))
        }
        guard let best = scored.map(\.1).max() else { return nil }
        let winners = scored.filter { $0.1 == best }.map(\.0)
        return winners.count == 1 ? winners[0] : nil
    }

    private func trailingMatchScore(original: [String], candidate: [String]) -> Int {
        let originalNames = original.map { $0.lowercased() }
        let candidateNames = candidate.map { $0.lowercased() }
        var score = 0
        while score < originalNames.count, score < candidateNames.count,
              originalNames[originalNames.count - 1 - score] == candidateNames[candidateNames.count - 1 - score] {
            score += 1
        }
        return score
    }

    private func pathComponents(_ path: String) -> [String] {
        (path as NSString).pathComponents.filter { $0 != "/" && $0 != "." }
    }

    private static func relativePath(from root: String, to target: String) -> String {
        var rootNorm = root
        if rootNorm.hasSuffix("/") { rootNorm.removeLast() }
        if target.hasPrefix(rootNorm + "/") {
            return String(target.dropFirst(rootNorm.count + 1))
        }
        if target.lowercased().hasPrefix(rootNorm.lowercased() + "/") {
            return String(target.dropFirst(rootNorm.count + 1))
        }
        return target
    }
}
