import Foundation

struct PlayerWindowFrame: Codable, Equatable {
    var width: Double
    var height: Double
    var artworkSize: Double?
}

enum AppSettings {
    private static let libraryRootBookmarkKey = "libraryRootBookmark"
    private static let legacyLibraryRootPathKey = "libraryRootPath"
    private static let libraryXMLDirectoryBookmarkKey = "libraryXMLDirectoryBookmark"
    private static let legacyLibraryXMLDirectoryPathKey = "libraryXMLDirectoryPath"
    private static let useCustomLibraryXMLLocationKey = "useCustomLibraryXMLLocation"
    private static let librarySortModeKey = "librarySortMode"
    private static let libraryGroupModeKey = "libraryGroupMode"
    private static let saveLastPlayedPositionKey = "saveLastPlayedPosition"
    private static let lastPlaybackStateKey = "lastPlaybackState"
    private static let showSpinningCDWhilePlayingKey = "showSpinningCDWhilePlaying"
    static let themeKey = "appTheme"
    static let showStatusMenuKey = "showStatusMenu"
    static let continuousAlbumPlayKey = "continuousAlbumPlay"
    static let libraryMetadataPreviewVisibleKey = "libraryMetadataPreviewVisible"
    static let libraryShowFavoritesOnlyKey = "libraryShowFavoritesOnly"
    private static let barcodeScannerCameraIDKey = "barcodeScannerCameraID"
    static let playerArtworkSizeKey = "playerArtworkSize"
    private static let playerCompactWindowFrameKey = "playerCompactWindowFrame"
    private static let playerExpandedWindowFrameKey = "playerExpandedWindowFrame"

    private static let libraryXMLFileName = "flacnest.xml"

    private static var accessedLibraryRootURL: URL?
    private static var accessedLibraryXMLDirectoryURL: URL?

    static var useCustomLibraryXMLLocation: Bool {
        get { UserDefaults.standard.bool(forKey: useCustomLibraryXMLLocationKey) }
        set { UserDefaults.standard.set(newValue, forKey: useCustomLibraryXMLLocationKey) }
    }

    static var librarySortMode: LibrarySortMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: librarySortModeKey),
                  let mode = LibrarySortMode(rawValue: raw) else {
                return .artist
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: librarySortModeKey) }
    }

    static var libraryGroupMode: LibraryGroupMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: libraryGroupModeKey),
                  let mode = LibraryGroupMode(rawValue: raw) else {
                return .none
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: libraryGroupModeKey) }
    }

    static var saveLastPlayedPosition: Bool {
        get { UserDefaults.standard.bool(forKey: saveLastPlayedPositionKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: saveLastPlayedPositionKey)
            if !newValue {
                lastPlaybackState = nil
            }
        }
    }

    static var showSpinningCDWhilePlaying: Bool {
        get {
            if UserDefaults.standard.object(forKey: showSpinningCDWhilePlayingKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showSpinningCDWhilePlayingKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showSpinningCDWhilePlayingKey) }
    }

    static var theme: AppTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: themeKey),
                  let theme = AppTheme(rawValue: raw) else {
                return .system
            }
            return theme
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: themeKey) }
    }

    static var showStatusMenu: Bool {
        get { UserDefaults.standard.bool(forKey: showStatusMenuKey) }
        set { UserDefaults.standard.set(newValue, forKey: showStatusMenuKey) }
    }

    static var continuousAlbumPlay: Bool {
        get { UserDefaults.standard.bool(forKey: continuousAlbumPlayKey) }
        set { UserDefaults.standard.set(newValue, forKey: continuousAlbumPlayKey) }
    }

    static var libraryMetadataPreviewVisible: Bool {
        get { UserDefaults.standard.bool(forKey: libraryMetadataPreviewVisibleKey) }
        set { UserDefaults.standard.set(newValue, forKey: libraryMetadataPreviewVisibleKey) }
    }

    static var libraryShowFavoritesOnly: Bool {
        get { UserDefaults.standard.bool(forKey: libraryShowFavoritesOnlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: libraryShowFavoritesOnlyKey) }
    }

    static var barcodeScannerCameraID: String? {
        get { UserDefaults.standard.string(forKey: barcodeScannerCameraIDKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: barcodeScannerCameraIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: barcodeScannerCameraIDKey)
            }
        }
    }

    static var playerCompactWindowFrame: PlayerWindowFrame? {
        get { decodeFrame(forKey: playerCompactWindowFrameKey) }
        set { encodeFrame(newValue, forKey: playerCompactWindowFrameKey) }
    }

    static var playerExpandedWindowFrame: PlayerWindowFrame? {
        get { decodeFrame(forKey: playerExpandedWindowFrameKey) }
        set { encodeFrame(newValue, forKey: playerExpandedWindowFrameKey) }
    }

    static func playerArtworkSize(trackListVisible: Bool) -> CGFloat {
        let frame = trackListVisible ? playerExpandedWindowFrame : playerCompactWindowFrame
        if let size = frame?.artworkSize, size > 0 {
            return CGFloat(size)
        }

        let legacy = UserDefaults.standard.double(forKey: playerArtworkSizeKey)
        if legacy > 0 {
            return CGFloat(legacy)
        }
        return 128
    }

    static func setPlayerArtworkSize(_ size: CGFloat, trackListVisible: Bool) {
        updatePlayerWindowFrame(trackListVisible: trackListVisible) { frame in
            var updated = frame
            updated.artworkSize = Double(size)
            return updated
        }
    }

    private static func updatePlayerWindowFrame(
        trackListVisible: Bool,
        transform: (PlayerWindowFrame) -> PlayerWindowFrame
    ) {
        let defaultFrame = PlayerWindowFrame(
            width: trackListVisible ? 380 : 380,
            height: trackListVisible ? 560 : 420,
            artworkSize: nil
        )
        let current = (trackListVisible ? playerExpandedWindowFrame : playerCompactWindowFrame) ?? defaultFrame
        let updated = transform(current)
        if trackListVisible {
            playerExpandedWindowFrame = updated
        } else {
            playerCompactWindowFrame = updated
        }
    }

    static var lastPlaybackState: LastPlaybackState? {
        get {
            guard let data = UserDefaults.standard.data(forKey: lastPlaybackStateKey) else { return nil }
            return try? JSONDecoder().decode(LastPlaybackState.self, from: data)
        }
        set {
            if let newValue {
                if let data = try? JSONEncoder().encode(newValue) {
                    UserDefaults.standard.set(data, forKey: lastPlaybackStateKey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: lastPlaybackStateKey)
            }
        }
    }

    static var libraryRootURL: URL? {
        get { resolveBookmark(key: libraryRootBookmarkKey, legacyPathKey: legacyLibraryRootPathKey, accessed: &accessedLibraryRootURL) }
        set { setBookmarkURL(newValue, bookmarkKey: libraryRootBookmarkKey, legacyPathKey: legacyLibraryRootPathKey, accessed: &accessedLibraryRootURL) }
    }

    static var libraryXMLDirectoryURL: URL? {
        get {
            guard useCustomLibraryXMLLocation else { return nil }
            return resolveBookmark(
                key: libraryXMLDirectoryBookmarkKey,
                legacyPathKey: legacyLibraryXMLDirectoryPathKey,
                accessed: &accessedLibraryXMLDirectoryURL
            )
        }
        set {
            setBookmarkURL(
                newValue,
                bookmarkKey: libraryXMLDirectoryBookmarkKey,
                legacyPathKey: legacyLibraryXMLDirectoryPathKey,
                accessed: &accessedLibraryXMLDirectoryURL
            )
        }
    }

    static var libraryXMLURL: URL? {
        if useCustomLibraryXMLLocation, let directory = libraryXMLDirectoryURL {
            return directory.appendingPathComponent(libraryXMLFileName, isDirectory: false)
        }
        return libraryRootXMLURL
    }

    static var libraryRootXMLURL: URL? {
        guard let root = libraryRootURL else { return nil }
        return root.appendingPathComponent(libraryXMLFileName, isDirectory: false)
    }

    static func stopAccessing() {
        stopAccessing(&accessedLibraryRootURL)
        stopAccessing(&accessedLibraryXMLDirectoryURL)
    }

    @discardableResult
    static func moveLibraryXML(from source: URL, to destination: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return false }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        } else {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        try fileManager.moveItem(at: source, to: destination)
        return true
    }

    private static func resolveBookmark(
        key: String,
        legacyPathKey: String,
        accessed: inout URL?
    ) -> URL? {
        if let accessed {
            return accessed
        }
        if let data = UserDefaults.standard.data(forKey: key) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if stale, let refreshed = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(refreshed, forKey: key)
                }
                if url.startAccessingSecurityScopedResource() {
                    accessed = url
                }
                return url
            }
        }
        if let path = UserDefaults.standard.string(forKey: legacyPathKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    private static func setBookmarkURL(
        _ newValue: URL?,
        bookmarkKey: String,
        legacyPathKey: String,
        accessed: inout URL?
    ) {
        stopAccessing(&accessed)
        if let url = newValue {
            if let data = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(data, forKey: bookmarkKey)
                UserDefaults.standard.set(url.path, forKey: legacyPathKey)
            } else {
                UserDefaults.standard.set(url.path, forKey: legacyPathKey)
            }
            if url.startAccessingSecurityScopedResource() {
                accessed = url
            }
        } else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            UserDefaults.standard.removeObject(forKey: legacyPathKey)
        }
    }

    private static func stopAccessing(_ accessed: inout URL?) {
        accessed?.stopAccessingSecurityScopedResource()
        accessed = nil
    }

    private static func decodeFrame(forKey key: String) -> PlayerWindowFrame? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PlayerWindowFrame.self, from: data)
    }

    private static func encodeFrame(_ frame: PlayerWindowFrame?, forKey key: String) {
        if let frame, let data = try? JSONEncoder().encode(frame) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
