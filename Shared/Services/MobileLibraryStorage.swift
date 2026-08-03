import Foundation

enum MobileLibraryFolderSource: String, Equatable {
    case `default`
    case custom
}

enum MobileLibraryStorage {
    private static let customExportRootBookmarkKey = "mobileCustomExportRootBookmark"
    private static let customExportRootPathKey = "mobileCustomExportRootPath"
    private static let useCustomExportRootKey = "mobileUseCustomExportRoot"

    private static var accessedExportRootURL: URL?

#if os(macOS)
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = .withSecurityScope
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
#else
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
#endif

    static var defaultDocumentsURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    static func configuredFolderSource() -> MobileLibraryFolderSource {
        UserDefaults.standard.bool(forKey: useCustomExportRootKey) ? .custom : .default
    }

    static func configuredFolderDisplayName() -> String {
        guard let url = resolveExportRootURL() else {
            return "Not set"
        }
        return url.lastPathComponent
    }

    static func configuredFolderPath() -> String? {
        resolveExportRootURL()?.path
    }

    static func setLibraryFolder(_ url: URL) {
        let standardized = url.standardizedFileURL

        if isWithinDefaultDocuments(standardized) {
            useDefaultFolder()
            return
        }

        stopAccessingExportRoot()

        _ = standardized.startAccessingSecurityScopedResource()
        if let data = try? standardized.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: customExportRootBookmarkKey)
        }
        UserDefaults.standard.set(standardized.path, forKey: customExportRootPathKey)
        UserDefaults.standard.set(true, forKey: useCustomExportRootKey)

        _ = standardized.startAccessingSecurityScopedResource()
        accessedExportRootURL = standardized
    }

    static func useDefaultFolder() {
        stopAccessingExportRoot()
        UserDefaults.standard.removeObject(forKey: customExportRootBookmarkKey)
        UserDefaults.standard.removeObject(forKey: customExportRootPathKey)
        UserDefaults.standard.set(false, forKey: useCustomExportRootKey)
    }

    static func clearLibraryFolder() {
        useDefaultFolder()
    }

    static func resolveExportRootURL() -> URL? {
        if let accessedExportRootURL {
            return accessedExportRootURL
        }

        if UserDefaults.standard.bool(forKey: useCustomExportRootKey),
           let customURL = resolveCustomExportRootURL() {
            _ = customURL.startAccessingSecurityScopedResource()
            accessedExportRootURL = customURL
            return customURL
        }

        guard let defaultURL = findExportRootInDocuments() else {
            return nil
        }

        _ = defaultURL.startAccessingSecurityScopedResource()
        accessedExportRootURL = defaultURL
        return defaultURL
    }

    static func loadActivePackage() throws -> MobileLibraryPackage? {
        guard let root = resolveExportRootURL() else { return nil }
        return try FlacNestMobileLibraryLoader.load(from: root)
    }

    private static func resolveCustomExportRootURL() -> URL? {
        if let data = UserDefaults.standard.data(forKey: customExportRootBookmarkKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if stale, let refreshed = try? url.bookmarkData(
                    options: bookmarkCreationOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(refreshed, forKey: customExportRootBookmarkKey)
                }
                return url
            }
        }

        if let path = UserDefaults.standard.string(forKey: customExportRootPathKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return nil
    }

    private static func findExportRootInDocuments() -> URL? {
        guard let documents = defaultDocumentsURL else { return nil }

        let subfolders: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        } ?? []

        let candidates = [documents] + subfolders

        for candidate in candidates {
            let xmlURL = candidate.appendingPathComponent(MobileLibraryPaths.xmlFilename, isDirectory: false)
            if FileManager.default.fileExists(atPath: xmlURL.path) {
                return candidate
            }
        }

        return nil
    }

    private static func isWithinDefaultDocuments(_ url: URL) -> Bool {
        guard let documents = defaultDocumentsURL?.standardizedFileURL else { return false }
        let target = url.standardizedFileURL
        if target.path == documents.path {
            return true
        }
        return target.path.hasPrefix(documents.path + "/")
    }

    private static func stopAccessingExportRoot() {
        accessedExportRootURL?.stopAccessingSecurityScopedResource()
        accessedExportRootURL = nil
    }
}
