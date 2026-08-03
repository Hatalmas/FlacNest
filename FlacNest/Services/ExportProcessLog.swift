import Foundation

enum ExportProcessLog {
    static let filename = "process.txt"

    static func logURL(in exportDirectory: URL) -> URL {
        exportDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    static func loadCompletedRelativePaths(from exportDirectory: URL) -> Set<String> {
        let url = logURL(in: exportDirectory)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return Set(
            contents
                .split(whereSeparator: \.isNewline)
                .map { normalizeRelativePath(String($0)) }
                .filter { !$0.isEmpty }
        )
    }

    static func append(relativePath: String, to exportDirectory: URL) throws {
        let normalized = normalizeRelativePath(relativePath)
        guard !normalized.isEmpty else { return }

        let url = logURL(in: exportDirectory)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: exportDirectory.path) {
            try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = "\(normalized)\n".data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            try "\(normalized)\n".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func normalizeRelativePath(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
    }
}
