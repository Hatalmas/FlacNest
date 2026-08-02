import Foundation

struct ScanProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case discovering
        case processing
        case saving
    }

    var phase: Phase = .idle
    var processed: Int = 0
    var total: Int = 0
    var currentItem: String = ""

    var fractionCompleted: Double {
        switch phase {
        case .idle, .discovering:
            return 0
        case .saving:
            return 1
        case .processing:
            guard total > 0 else { return 0 }
            return Double(processed) / Double(total)
        }
    }

    var title: String {
        switch phase {
        case .idle:
            return "Ready"
        case .discovering:
            return "Discovering CUE files…"
        case .processing:
            return "Processing albums…"
        case .saving:
            return "Saving flacnest.xml…"
        }
    }

    var detail: String {
        switch phase {
        case .idle:
            return ""
        case .discovering:
            return "Scanning folders"
        case .processing:
            if total > 0 {
                return "\(processed) of \(total)"
            }
            return ""
        case .saving:
            return "Writing library file"
        }
    }
}

struct LibraryScanResult: Sendable {
    var library: FlacNestLibrary
    var skippedCues: [String]
}

enum LibraryScanner {
    typealias ProgressHandler = @Sendable (ScanProgress) -> Void

    static func scan(
        libraryRoot: URL,
        shouldCancel: (@Sendable () -> Bool)? = nil,
        reportProgress: ProgressHandler? = nil
    ) -> LibraryScanResult {
        if shouldCancel?() == true {
            return LibraryScanResult(library: FlacNestLibrary(), skippedCues: [])
        }

        reportProgress?(ScanProgress(phase: .discovering))

        let cueFiles = discoverCueFiles(in: libraryRoot)
        let total = cueFiles.count

        var albums: [LibraryAlbum] = []
        albums.reserveCapacity(total)
        var skipped: [String] = []
        skipped.reserveCapacity(min(total / 20, 64))

        for (index, entry) in cueFiles.enumerated() {
            if shouldCancel?() == true {
                break
            }

            reportProgress?(
                ScanProgress(
                    phase: .processing,
                    processed: index + 1,
                    total: total,
                    currentItem: entry.relativePath
                )
            )

            do {
                guard let album = try parseAlbum(
                    cueURL: entry.url,
                    cueRelativePath: entry.relativePath,
                    libraryRoot: libraryRoot
                ) else {
                    continue
                }
                albums.append(album)
            } catch {
                skipped.append("\(entry.relativePath): \(error.localizedDescription)")
            }
        }

        albums.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }

        reportProgress?(
            ScanProgress(
                phase: .processing,
                processed: total,
                total: total,
                currentItem: ""
            )
        )

        return LibraryScanResult(
            library: FlacNestLibrary(scannedAt: Date(), albums: albums),
            skippedCues: skipped
        )
    }

    private struct CueFileEntry: Sendable {
        var url: URL
        var relativePath: String
    }

    private static func discoverCueFiles(in libraryRoot: URL) -> [CueFileEntry] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: libraryRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rootPath = libraryRoot.path
        var cueFiles: [CueFileEntry] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "cue" else { continue }
            cueFiles.append(
                CueFileEntry(
                    url: fileURL,
                    relativePath: relativePath(from: rootPath, to: fileURL.path)
                )
            )
        }

        return cueFiles
    }

    private static func parseAlbum(cueURL: URL, cueRelativePath: String, libraryRoot: URL) throws -> LibraryAlbum? {
        let parsed = try CUEParser.parse(url: cueURL)
        guard !parsed.flacFileName.isEmpty else { return nil }

        let cueDir = cueURL.deletingLastPathComponent()
        let flacURL = cueDir.appendingPathComponent(parsed.flacFileName)
        guard FileManager.default.fileExists(atPath: flacURL.path) else { return nil }

        let metadata = CUEMetadataRepair.repair(parsed, flacURL: flacURL)
        let flacRelative = relativePath(from: libraryRoot.path, to: flacURL.path)
        let artwork = discoverArtwork(
            near: cueDir,
            cueArtworkFileName: metadata.artworkFileName,
            libraryRootPath: libraryRoot.path
        )

        var libraryTracks: [LibraryTrack] = []
        for (index, track) in metadata.tracks.enumerated() {
            let end: Double?
            if index + 1 < metadata.tracks.count {
                end = metadata.tracks[index + 1].indexStartSeconds
            } else {
                end = nil
            }
            libraryTracks.append(
                LibraryTrack(
                    id: "\(cueRelativePath)#\(track.number)",
                    number: track.number,
                    title: track.title,
                    performer: track.performer,
                    startSeconds: track.indexStartSeconds,
                    endSeconds: end
                )
            )
        }

        return LibraryAlbum(
            id: cueRelativePath,
            cueRelativePath: cueRelativePath,
            flacRelativePath: flacRelative,
            title: metadata.title,
            performer: metadata.performer,
            genre: metadata.genre,
            date: metadata.date,
            discID: metadata.discID,
            comment: metadata.comment,
            artworkRelativePath: artwork,
            tracks: libraryTracks
        )
    }

    private static func discoverArtwork(
        near directory: URL,
        cueArtworkFileName: String?,
        libraryRootPath: String
    ) -> String? {
        if let cueArtworkFileName, !cueArtworkFileName.isEmpty {
            let cueArtURL = directory.appendingPathComponent(cueArtworkFileName)
            if FileManager.default.fileExists(atPath: cueArtURL.path) {
                return relativePath(from: libraryRootPath, to: cueArtURL.path)
            }
        }

        let folderName = directory.lastPathComponent
        let fallbackNames = [
            "cover.jpg",
            "album.jpg",
            "cover.png",
            "album.png",
            "folder.jpg",
            "folder.png",
            "\(folderName).jpg",
            "\(folderName).png",
        ]

        for name in fallbackNames {
            if let url = findFileCaseInsensitive(named: name, in: directory) {
                return relativePath(from: libraryRootPath, to: url.path)
            }
        }

        return nil
    }

    private static func findFileCaseInsensitive(named name: String, in directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents.first { fileURL in
            fileURL.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
        }
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
