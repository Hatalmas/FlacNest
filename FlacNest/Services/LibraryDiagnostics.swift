import Foundation
import os

enum LibraryDiagnostics {
    static let logger = Logger(subsystem: "com.flacnest.app", category: "library")

    static var logURL: URL {
        applicationSupportLogURL
    }

    static var libraryFolderLogURL: URL? {
        AppSettings.libraryXMLURL?
            .deletingLastPathComponent()
            .appendingPathComponent("flacnest-load.log")
    }

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        queue.async {
            let payload = "\(formatter.string(from: Date())) \(message)\n"
            append(payload, to: applicationSupportLogURL)
            if let libraryFolderLogURL {
                append(payload, to: libraryFolderLogURL)
            }
        }
    }

    private static var applicationSupportLogURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlacNest", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("library-load.log")
    }

    private static func append(_ payload: String, to url: URL) {
        guard let data = payload.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func measure<T>(_ label: String, work: () throws -> T) rethrows -> T {
        let started = Date()
        defer {
            let ms = Date().timeIntervalSince(started) * 1000
            log(String(format: "%@ %.1fms", label, ms))
        }
        return try work()
    }

    static func measureAsync<T>(_ label: String, work: () async throws -> T) async rethrows -> T {
        let started = Date()
        defer {
            let ms = Date().timeIntervalSince(started) * 1000
            log(String(format: "%@ %.1fms", label, ms))
        }
        return try await work()
    }

    static func summarizeArtwork(in library: FlacNestLibrary, libraryRoot: URL?) {
        var none = 0
        var stored = 0
        var storedMissing = 0
        var absoluteForeign = 0
        var absoluteLocal = 0
        var relative = 0
        var bookmarks = 0
        var examples: [String] = []

        let rootPath = libraryRoot?.standardizedFileURL.path

        for album in library.albums {
            if album.artworkBookmark != nil {
                bookmarks += 1
            }
            let art = album.artworkRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if art.isEmpty {
                none += 1
                continue
            }
            if AlbumArtworkStore.isStoredPath(art) {
                stored += 1
                if AlbumArtworkStore.existingStoredFileURL(forPath: art, libraryRoot: libraryRoot) == nil {
                    storedMissing += 1
                    if examples.count < 8 {
                        examples.append("stored-missing \(album.id) \(art)")
                    }
                }
            } else if art.hasPrefix("/") {
                if let rootPath, art == rootPath || art.hasPrefix(rootPath + "/") {
                    absoluteLocal += 1
                } else {
                    absoluteForeign += 1
                    if examples.count < 8 {
                        examples.append("foreign \(album.id) \(art)")
                    }
                }
            } else {
                relative += 1
                if examples.count < 8 {
                    examples.append("relative \(album.id) \(art)")
                }
            }
        }

        let storeURL = AlbumArtworkStore.directoryURL(libraryRoot: libraryRoot)
        let storeCount: Int
        if let storeURL {
            storeCount = (try? FileManager.default.contentsOfDirectory(at: storeURL, includingPropertiesForKeys: nil))?
                .filter { !$0.hasDirectoryPath && !$0.lastPathComponent.hasPrefix(".") }
                .count ?? -1
        } else {
            storeCount = -1
        }

        log(
            "artwork albums=\(library.albums.count) none=\(none) stored=\(stored) storedMissing=\(storedMissing) relative=\(relative) absoluteLocal=\(absoluteLocal) absoluteForeign=\(absoluteForeign) bookmarks=\(bookmarks) root=\(rootPath ?? "nil") store=\(storeURL?.path ?? "nil") storeFiles=\(storeCount) customXML=\(AppSettings.useCustomLibraryXMLLocation)"
        )
        for example in examples {
            log("artwork example \(example)")
        }
        log("log file \(logURL.path)")
    }

    private static let queue = DispatchQueue(label: "com.flacnest.diagnostics")

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
