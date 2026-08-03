import Foundation

enum FFmpegLocator {
    private static let bundledSubdirectory = "bin"

    static func locateExecutable() -> URL? {
        if let bundled = bundledExecutableURL() {
            return bundled
        }

        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]

        let fileManager = FileManager.default
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    static var usesBundledExecutable: Bool {
        bundledExecutableURL() != nil
    }

    private static func bundledExecutableURL() -> URL? {
        guard let url = Bundle.main.url(
            forResource: "ffmpeg",
            withExtension: nil,
            subdirectory: bundledSubdirectory
        ) else {
            return nil
        }

        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}
