import Foundation

enum FFmpegConverter {
    static func convertAlbum(
        flacURL: URL,
        outputURL: URL,
        bitrate: MobileExportBitrate,
        cancellation: ExportCancellation? = nil
    ) throws {
        try runConversion(
            flacURL: flacURL,
            outputURL: outputURL,
            bitrate: bitrate,
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
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            cancellation: cancellation
        )
    }

    private static func runConversion(
        flacURL: URL,
        outputURL: URL,
        bitrate: MobileExportBitrate,
        startSeconds: Double?,
        endSeconds: Double?,
        cancellation: ExportCancellation?
    ) throws {
        if cancellation?.isCancelled == true {
            throw MobileLibraryExportError.cancelled
        }

        guard let ffmpegURL = FFmpegLocator.locateExecutable() else {
            throw MobileLibraryExportError.ffmpegNotFound
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
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

        arguments.append(outputURL.path)

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        cancellation?.register(process)
        defer { cancellation?.unregister(process) }

        try process.run()

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

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw MobileLibraryExportError.conversionFailed("Output file was not created.")
        }
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
