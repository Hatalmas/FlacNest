import Foundation

enum MobileExportLayout: String, CaseIterable, Identifiable {
    case nested
    case flat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nested:
            return "Mirror library folders"
        case .flat:
            return "Flat (MP3s at export root)"
        }
    }
}

enum MobileExportPathBuilder {
    /// Mirrors the FLAC relative path with an `.mp3` extension (one MP3 per album).
    static func mp3RelativePath(for album: LibraryAlbum, layout: MobileExportLayout = .nested) -> String {
        switch layout {
        case .nested:
            let flacPath = album.flacRelativePath as NSString
            let base = flacPath.deletingPathExtension
            return base.isEmpty ? "album.mp3" : "\(base).mp3"
        case .flat:
            return flatMp3Filename(forAlbumID: album.id)
        }
    }

    static func flatMp3Filename(forAlbumID id: String) -> String {
        "\(sanitizeFilename(id)).mp3"
    }

    static func uniqueFlatMp3Filename(forAlbumID id: String, usedNames: inout Set<String>) -> String {
        let base = sanitizeFilename(id)
        var candidate = "\(base).mp3"
        var counter = 2
        while usedNames.contains(candidate) {
            candidate = "\(base)_\(counter).mp3"
            counter += 1
        }
        usedNames.insert(candidate)
        return candidate
    }

    static func sanitizeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let sanitized = value
            .components(separatedBy: invalid)
            .joined(separator: "_")
        return sanitized.isEmpty ? "album" : sanitized
    }
}

struct MobileExportFlattenResult: Equatable, Sendable {
    var movedCount: Int
    var alreadyFlatCount: Int
}

enum MobileExportFlattenError: LocalizedError {
    case mp3Missing(String)

    var errorDescription: String? {
        switch self {
        case .mp3Missing(let path):
            return "MP3 file not found: \(path)"
        }
    }
}

enum MobileExportFlattener {
    static func flatten(
        exportDirectory: URL,
        log: (@Sendable (String) -> Void)? = nil
    ) throws -> MobileExportFlattenResult {
        let package = try FlacNestMobileLibraryLoader.load(from: exportDirectory)
        let fileManager = FileManager.default
        var usedNames = Set<String>()
        var updatedAlbums: [MobileLibraryAlbum] = []
        var movedCount = 0
        var alreadyFlatCount = 0

        for album in package.library.albums {
            let normalized = ExportProcessLog.normalizeRelativePath(album.mp3RelativePath)
            let isNested = normalized.contains("/")

            if !isNested {
                usedNames.insert(normalized)
                updatedAlbums.append(album)
                alreadyFlatCount += 1
                continue
            }

            let flatName = MobileExportPathBuilder.uniqueFlatMp3Filename(forAlbumID: album.id, usedNames: &usedNames)
            let sourceURL = exportDirectory.appendingPathComponent(normalized)
            let destinationURL = exportDirectory.appendingPathComponent(flatName)

            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw MobileExportFlattenError.mp3Missing(normalized)
            }

            if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                movedCount += 1
                log?("Moved: \(normalized) → \(flatName)")
            }

            var updated = album
            updated.mp3RelativePath = flatName
            updatedAlbums.append(updated)
        }

        var library = package.library
        library.albums = updatedAlbums
        try FlacNestMobileLibraryStore.save(library: library, to: exportDirectory)

        let flatPaths = updatedAlbums.map(\.mp3RelativePath)
        try ExportProcessLog.rewrite(withRelativePaths: flatPaths, in: exportDirectory)
        removeEmptySubdirectories(in: exportDirectory)

        log?("Updated \(FlacNestMobileLibraryStore.xmlFilename). Parent folder metadata unchanged.")
        return MobileExportFlattenResult(movedCount: movedCount, alreadyFlatCount: alreadyFlatCount)
    }

    static func removeEmptySubdirectories(in exportDirectory: URL) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: exportDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var directories: [URL] = []
        for case let url as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            directories.append(url)
        }

        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            if let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
               contents.isEmpty {
                try? fileManager.removeItem(at: directory)
            }
        }
    }
}

struct MobileExportProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case preparing
        case converting
        case saving
        case finished
        case failed
        case cancelled
    }

    var phase: Phase = .idle
    var processed: Int = 0
    var total: Int = 0
    var skipped: Int = 0
    var currentItem: String = ""
    var logLines: [String] = []

    var fractionCompleted: Double {
        switch phase {
        case .idle, .preparing:
            return 0
        case .saving, .finished:
            return 1
        case .failed, .cancelled:
            return total > 0 ? Double(processed) / Double(total) : 0
        case .converting:
            guard total > 0 else { return 0 }
            return Double(processed) / Double(total)
        }
    }

    var title: String {
        switch phase {
        case .idle:
            return "Ready"
        case .preparing:
            return "Preparing export…"
        case .converting:
            return "Converting to MP3…"
        case .saving:
            return "Writing flacnestmobile.xml…"
        case .finished:
            return "Export complete"
        case .failed:
            return "Export failed"
        case .cancelled:
            return "Export cancelled"
        }
    }
}

struct MobileExportWorkItem: Sendable {
    enum Action: Equatable, Sendable {
        case convert
        case skipExisting
        case moveExisting(from: String)
    }

    let album: LibraryAlbum
    let mp3RelativePath: String
    let action: Action
}

enum MobileLibraryExportError: LocalizedError {
    case libraryEmpty
    case libraryRootMissing
    case exportDirectoryMissing
    case ffmpegNotFound
    case conversionFailed(String)
    case sourceFileMissing(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .libraryEmpty:
            return "There are no albums to export."
        case .libraryRootMissing:
            return "Set a library folder in Settings first."
        case .exportDirectoryMissing:
            return "Choose an export directory first."
        case .ffmpegNotFound:
            return "A native ffmpeg was not found. Run Scripts/fetch-static-ffmpeg.sh and rebuild FlacNest, or install ffmpeg with Homebrew."
        case .conversionFailed(let message):
            return "MP3 conversion failed: \(message)"
        case .sourceFileMissing(let path):
            return "Source file not found: \(path)"
        case .cancelled:
            return "Export was cancelled."
        }
    }
}

enum MobileLibraryPreparer {
    typealias ProgressHandler = @Sendable (MobileExportProgress) -> Void

    static func prepareExport(
        library: FlacNestLibrary,
        libraryRoot: URL,
        exportDirectory: URL,
        bitrate: MobileExportBitrate,
        parallelJobs: Int,
        artworkSourceURLs: [String: URL],
        cancellation: ExportCancellation? = nil,
        reportProgress: ProgressHandler? = nil
    ) throws -> MobileExportProgress {
        guard !library.albums.isEmpty else {
            throw MobileLibraryExportError.libraryEmpty
        }

        guard FFmpegLocator.locateExecutable() != nil else {
            throw MobileLibraryExportError.ffmpegNotFound
        }

        let progressLock = NSLock()
        var progress = MobileExportProgress(phase: .preparing)

        func report(_ update: MobileExportProgress) {
            reportProgress?(update)
        }

        func mutateProgress(_ body: (inout MobileExportProgress) -> Void) {
            progressLock.lock()
            body(&progress)
            let snapshot = progress
            progressLock.unlock()
            report(snapshot)
        }

        report(progress)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        if cancellation?.isCancelled == true {
            var cancelled = progress
            cancelled.phase = .cancelled
            appendLog(&cancelled, "Export cancelled.")
            report(cancelled)
            return cancelled
        }

        let workItems = resolveWorkItems(from: library, exportDirectory: exportDirectory)
        var completedPaths = ExportProcessLog.loadCompletedRelativePaths(from: exportDirectory)
        mutateProgress { exportProgress in
            exportProgress.total = workItems.count
            exportProgress.phase = .converting
        }

        let albumMP3Lock = NSLock()
        var albumMP3Paths: [String: String] = [:]
        let processLogLock = NSLock()
        let failureLock = NSLock()
        var firstFailure: Error?

        let jobCount = max(1, parallelJobs)
        let queue = DispatchQueue(label: "com.flacnest.export.convert", attributes: .concurrent)
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: jobCount)

        for item in workItems {
            if cancellation?.isCancelled == true {
                break
            }

            albumMP3Lock.lock()
            albumMP3Paths[item.album.id] = item.mp3RelativePath
            albumMP3Lock.unlock()

            let outputURL = exportDirectory.appendingPathComponent(item.mp3RelativePath)
            let tags = MP3AlbumTags(album: item.album)
            if item.action == .skipExisting {
                do {
                    try FFmpegConverter.writeAlbumTags(
                        to: outputURL,
                        tags: tags,
                        cancellation: cancellation
                    )
                    let normalized = ExportProcessLog.normalizeRelativePath(item.mp3RelativePath)
                    if !completedPaths.contains(normalized) {
                        processLogLock.lock()
                        try? ExportProcessLog.append(relativePath: item.mp3RelativePath, to: exportDirectory)
                        processLogLock.unlock()
                        completedPaths.insert(normalized)
                    }
                    try? copyArtworkIfNeeded(
                        for: item.album,
                        libraryRoot: libraryRoot,
                        exportDirectory: exportDirectory,
                        artworkSourceURL: artworkSourceURLs[item.album.id]
                    )
                    mutateProgress { exportProgress in
                        exportProgress.skipped += 1
                        exportProgress.processed += 1
                        appendLog(&exportProgress, "Updated tags: \(item.mp3RelativePath)")
                    }
                } catch {
                    failureLock.lock()
                    if firstFailure == nil {
                        firstFailure = error
                    }
                    failureLock.unlock()
                    break
                }
                continue
            }

            if case .moveExisting(let sourcePath) = item.action {
                do {
                    try moveExistingMP3(
                        from: sourcePath,
                        to: item.mp3RelativePath,
                        in: exportDirectory
                    )
                    try FFmpegConverter.writeAlbumTags(
                        to: outputURL,
                        tags: tags,
                        cancellation: cancellation
                    )
                    processLogLock.lock()
                    try ExportProcessLog.append(relativePath: item.mp3RelativePath, to: exportDirectory)
                    processLogLock.unlock()
                    try? copyArtworkIfNeeded(
                        for: item.album,
                        libraryRoot: libraryRoot,
                        exportDirectory: exportDirectory,
                        artworkSourceURL: artworkSourceURLs[item.album.id]
                    )
                    mutateProgress { exportProgress in
                        exportProgress.skipped += 1
                        exportProgress.processed += 1
                        appendLog(&exportProgress, "Flattened: \(sourcePath) → \(item.mp3RelativePath)")
                    }
                } catch {
                    failureLock.lock()
                    if firstFailure == nil {
                        firstFailure = error
                    }
                    failureLock.unlock()
                    break
                }
                continue
            }

            if cancellation?.isCancelled == true {
                break
            }

            failureLock.lock()
            let failed = firstFailure != nil
            failureLock.unlock()
            if failed {
                break
            }

            semaphore.wait()
            if cancellation?.isCancelled == true {
                semaphore.signal()
                break
            }

            group.enter()
            queue.async {
                defer {
                    semaphore.signal()
                    group.leave()
                }

                if cancellation?.isCancelled == true {
                    return
                }

                failureLock.lock()
                let failed = firstFailure != nil
                failureLock.unlock()
                if failed {
                    return
                }

                do {
                    let flacURL = libraryRoot.appendingPathComponent(item.album.flacRelativePath)
                    guard fileManager.fileExists(atPath: flacURL.path) else {
                        throw MobileLibraryExportError.sourceFileMissing(item.album.flacRelativePath)
                    }

                    mutateProgress { exportProgress in
                        exportProgress.currentItem = item.mp3RelativePath
                        appendLog(&exportProgress, "Converting: \(item.mp3RelativePath)")
                    }

                    try FFmpegConverter.convertAlbum(
                        flacURL: flacURL,
                        outputURL: outputURL,
                        bitrate: bitrate,
                        tags: tags,
                        cancellation: cancellation
                    )

                    if cancellation?.isCancelled == true {
                        throw MobileLibraryExportError.cancelled
                    }

                    try copyArtworkIfNeeded(
                        for: item.album,
                        libraryRoot: libraryRoot,
                        exportDirectory: exportDirectory,
                        artworkSourceURL: artworkSourceURLs[item.album.id]
                    )

                    processLogLock.lock()
                    try ExportProcessLog.append(relativePath: item.mp3RelativePath, to: exportDirectory)
                    processLogLock.unlock()

                    mutateProgress { exportProgress in
                        exportProgress.processed += 1
                        appendLog(&exportProgress, "Done: \(item.mp3RelativePath)")
                    }
                } catch MobileLibraryExportError.cancelled {
                    return
                } catch {
                    failureLock.lock()
                    if firstFailure == nil {
                        firstFailure = error
                    }
                    failureLock.unlock()
                }
            }
        }

        group.wait()

        if let firstFailure {
            throw firstFailure
        }

        if cancellation?.isCancelled == true {
            mutateProgress { exportProgress in
                exportProgress.phase = .cancelled
                exportProgress.currentItem = ""
                appendLog(&exportProgress, "Export cancelled.")
            }
            try writeMobileXML(library: library, albumMP3Paths: albumMP3Paths, exportDirectory: exportDirectory)
            MobileExportFlattener.removeEmptySubdirectories(in: exportDirectory)
            return progressLock.withLock { progress }
        }

        mutateProgress { exportProgress in
            exportProgress.phase = .saving
            exportProgress.currentItem = FlacNestMobileLibraryStore.xmlFilename
        }

        try writeMobileXML(library: library, albumMP3Paths: albumMP3Paths, exportDirectory: exportDirectory)
        MobileExportFlattener.removeEmptySubdirectories(in: exportDirectory)

        mutateProgress { exportProgress in
            exportProgress.phase = .finished
            exportProgress.currentItem = ""
            appendLog(&exportProgress, "Saved \(FlacNestMobileLibraryStore.xmlFilename).")
            if exportProgress.skipped > 0 {
                appendLog(&exportProgress, "Skipped \(exportProgress.skipped) previously exported album(s).")
            }
            appendLog(&exportProgress, "Converted \(exportProgress.processed - exportProgress.skipped) album(s).")
        }

        return progressLock.withLock { progress }
    }

    private static func resolveWorkItems(
        from library: FlacNestLibrary,
        exportDirectory: URL
    ) -> [MobileExportWorkItem] {
        let fileManager = FileManager.default
        let existingByAlbumID = existingMP3PathsByAlbumID(in: exportDirectory)
        let completedPaths = ExportProcessLog.loadCompletedRelativePaths(from: exportDirectory)
        var usedFlatNames = Set<String>()

        for path in existingByAlbumID.values where !path.contains("/") {
            usedFlatNames.insert(path)
        }

        return library.albums.map { album in
            if let existing = existingMP3RelativePath(
                for: album,
                exportDirectory: exportDirectory,
                xmlPath: existingByAlbumID[album.id],
                completedPaths: completedPaths
            ) {
                if existing.contains("/") {
                    let flatName = MobileExportPathBuilder.uniqueFlatMp3Filename(
                        forAlbumID: album.id,
                        usedNames: &usedFlatNames
                    )
                    return MobileExportWorkItem(
                        album: album,
                        mp3RelativePath: flatName,
                        action: .moveExisting(from: existing)
                    )
                }
                usedFlatNames.insert(existing)
                return MobileExportWorkItem(album: album, mp3RelativePath: existing, action: .skipExisting)
            }

            let path = MobileExportPathBuilder.uniqueFlatMp3Filename(
                forAlbumID: album.id,
                usedNames: &usedFlatNames
            )
            if fileManager.fileExists(atPath: exportDirectory.appendingPathComponent(path).path) {
                return MobileExportWorkItem(album: album, mp3RelativePath: path, action: .skipExisting)
            }
            return MobileExportWorkItem(album: album, mp3RelativePath: path, action: .convert)
        }
    }

    private static func existingMP3PathsByAlbumID(in exportDirectory: URL) -> [String: String] {
        guard let package = try? FlacNestMobileLibraryLoader.load(from: exportDirectory) else {
            return [:]
        }
        var result: [String: String] = [:]
        for album in package.library.albums {
            let path = ExportProcessLog.normalizeRelativePath(album.mp3RelativePath)
            guard !path.isEmpty else { continue }
            result[album.id] = path
        }
        return result
    }

    private static func existingMP3RelativePath(
        for album: LibraryAlbum,
        exportDirectory: URL,
        xmlPath: String?,
        completedPaths: Set<String>
    ) -> String? {
        let fileManager = FileManager.default
        let nested = ExportProcessLog.normalizeRelativePath(
            MobileExportPathBuilder.mp3RelativePath(for: album, layout: .nested)
        )
        let flat = ExportProcessLog.normalizeRelativePath(
            MobileExportPathBuilder.flatMp3Filename(forAlbumID: album.id)
        )
        let nestedName = (nested as NSString).lastPathComponent

        var candidates: [String] = []
        if let xmlPath {
            candidates.append(ExportProcessLog.normalizeRelativePath(xmlPath))
        }
        candidates.append(contentsOf: [nested, flat])
        for path in completedPaths {
            let name = (path as NSString).lastPathComponent
            if path == nested || path == flat || name == nestedName || name == flat {
                candidates.append(path)
            }
        }

        var seen = Set<String>()
        for path in candidates {
            guard seen.insert(path).inserted, !path.isEmpty else { continue }
            if fileManager.fileExists(atPath: exportDirectory.appendingPathComponent(path).path) {
                return path
            }
        }
        return nil
    }

    private static func moveExistingMP3(from sourcePath: String, to destinationPath: String, in exportDirectory: URL) throws {
        let fileManager = FileManager.default
        let sourceURL = exportDirectory.appendingPathComponent(sourcePath)
        let destinationURL = exportDirectory.appendingPathComponent(destinationPath)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw MobileExportFlattenError.mp3Missing(sourcePath)
        }
        guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else { return }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            return
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private static func writeMobileXML(
        library: FlacNestLibrary,
        albumMP3Paths: [String: String],
        exportDirectory: URL
    ) throws {
        try FlacNestMobileLibraryStore.save(
            library: library,
            albumMP3Paths: albumMP3Paths,
            to: exportDirectory
        )
    }

    private static func copyArtworkIfNeeded(
        for album: LibraryAlbum,
        libraryRoot: URL,
        exportDirectory: URL,
        artworkSourceURL: URL?
    ) throws {
        guard let sourceURL = artworkSourceURL ?? AlbumArtworkStore.artworkURL(for: album, libraryRoot: libraryRoot),
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            return
        }

        let relativePath: String
        if AlbumArtworkStore.isStoredPath(album.artworkRelativePath) {
            relativePath = album.artworkRelativePath!
        } else {
            relativePath = AlbumArtworkStore.storedPath(forAlbumID: album.id, pathExtension: sourceURL.pathExtension)
        }

        let destinationURL = exportDirectory.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return
        }

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func appendLog(_ progress: inout MobileExportProgress, _ line: String) {
        progress.logLines.append(line)
        if progress.logLines.count > 10 {
            progress.logLines.removeFirst(progress.logLines.count - 10)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
