import Foundation

struct MP3AlbumTags: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var genre: String?
    var date: String?
    var comment: String?

    init(album: LibraryAlbum) {
        let title = Self.cleaned(album.displayTitle) ?? "Album"
        let artist = Self.cleaned(album.displayArtist) ?? ""
        self.title = title
        self.artist = artist
        self.album = title
        self.albumArtist = artist
        self.genre = Self.cleaned(album.genre)
        self.date = Self.cleaned(album.date)
        self.comment = Self.cleaned(album.comment)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }
}

enum FFmpegConverter {
    static func convertAlbum(
        flacURL: URL,
        outputURL: URL,
        bitrate: MobileExportBitrate,
        tags: MP3AlbumTags,
        cancellation: ExportCancellation? = nil
    ) throws {
        try runConversion(
            flacURL: flacURL,
            outputURL: outputURL,
            bitrate: bitrate,
            tags: tags,
            startSeconds: nil,
            endSeconds: nil,
            cancellation: cancellation
        )
    }

    static func convertTrack(
        flacURL: URL,
        startSeconds: Double,
        endSeconds: Double?,
        outputURL: URL,
        bitrate: MobileExportBitrate,
        cancellation: ExportCancellation? = nil
    ) throws {
        try runConversion(
            flacURL: flacURL,
            outputURL: outputURL,
            bitrate: bitrate,
            tags: nil,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            cancellation: cancellation
        )
    }

    /// Rewrites ID3 tags on an existing whole-album MP3 without re-encoding audio.
    static func writeAlbumTags(
        to url: URL,
        tags: MP3AlbumTags,
        cancellation: ExportCancellation? = nil
    ) throws {
        if cancellation?.isCancelled == true {
            throw MobileLibraryExportError.cancelled
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).flacnest-tags.mp3")
        try? FileManager.default.removeItem(at: tempURL)

        var arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", url.path,
            "-map", "0",
            "-c", "copy",
            "-f", "mp3",
        ]
        arguments.append(contentsOf: id3Arguments(for: tags))
        arguments.append(tempURL.path)

        do {
            try runFFmpeg(arguments: arguments, cancellation: cancellation)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private static func runConversion(
        flacURL: URL,
        outputURL: URL,
        bitrate: MobileExportBitrate,
        tags: MP3AlbumTags?,
        startSeconds: Double?,
        endSeconds: Double?,
        cancellation: ExportCancellation?
    ) throws {
        if cancellation?.isCancelled == true {
            throw MobileLibraryExportError.cancelled
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: outputURL.path) {
            if let tags {
                try writeAlbumTags(to: outputURL, tags: tags, cancellation: cancellation)
            }
            return
        }

        var arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", flacURL.path,
        ]

        if let startSeconds {
            arguments.append(contentsOf: ["-ss", formatSeconds(startSeconds)])
        }

        arguments.append(contentsOf: [
            "-codec:a", "libmp3lame",
            "-b:a", bitrate.ffmpegBitrateArgument,
        ])

        if let endSeconds {
            arguments.append(contentsOf: ["-to", formatSeconds(endSeconds)])
        }

        if let tags {
            arguments.append(contentsOf: id3Arguments(for: tags))
        }

        arguments.append(outputURL.path)

        try runFFmpeg(arguments: arguments, cancellation: cancellation)

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw MobileLibraryExportError.conversionFailed("Output file was not created.")
        }
    }

    private static func id3Arguments(for tags: MP3AlbumTags) -> [String] {
        var arguments = [
            "-map_metadata", "-1",
            "-id3v2_version", "3",
            "-metadata", "title=\(tags.title)",
            "-metadata", "album=\(tags.album)",
        ]
        if !tags.artist.isEmpty {
            arguments.append(contentsOf: ["-metadata", "artist=\(tags.artist)"])
        }
        if !tags.albumArtist.isEmpty {
            arguments.append(contentsOf: ["-metadata", "album_artist=\(tags.albumArtist)"])
        }
        if let genre = tags.genre {
            arguments.append(contentsOf: ["-metadata", "genre=\(genre)"])
        }
        if let date = tags.date {
            arguments.append(contentsOf: ["-metadata", "date=\(date)"])
        }
        if let comment = tags.comment {
            arguments.append(contentsOf: ["-metadata", "comment=\(comment)"])
        }
        return arguments
    }

    private static func runFFmpeg(
        arguments: [String],
        cancellation: ExportCancellation?
    ) throws {
        guard let ffmpegURL = FFmpegLocator.locateExecutable() else {
            throw MobileLibraryExportError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        cancellation?.register(process)
        defer { cancellation?.unregister(process) }

        do {
            try process.run()
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == 86 {
                throw MobileLibraryExportError.conversionFailed(
                    "ffmpeg is built for a different Mac processor (bad CPU type). Run Scripts/fetch-static-ffmpeg.sh and rebuild FlacNest so it bundles a native binary."
                )
            }
            throw error
        }

        while process.isRunning {
            if cancellation?.isCancelled == true {
                process.terminate()
                process.waitUntilExit()
                throw MobileLibraryExportError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        guard process.terminationStatus == 0 else {
            if cancellation?.isCancelled == true {
                throw MobileLibraryExportError.cancelled
            }
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MobileLibraryExportError.conversionFailed(message ?? "ffmpeg exited with code \(process.terminationStatus)")
        }
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
