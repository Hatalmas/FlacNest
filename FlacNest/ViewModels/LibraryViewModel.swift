import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var library: FlacNestLibrary = FlacNestLibrary()
    @Published var isScanning = false
    @Published var scanProgress = ScanProgress()
    @Published var statusMessage: String?
    @Published var selectedAlbumID: String?
    @Published var sortMode: LibrarySortMode = AppSettings.librarySortMode
    @Published var groupMode: LibraryGroupMode = AppSettings.libraryGroupMode
    @Published var showFavoritesOnly: Bool = AppSettings.libraryShowFavoritesOnly

    private var scanTask: Task<Void, Never>?
    private var lastProgressUpdate = Date.distantPast

    func loadFromDisk() {
        guard let xmlURL = AppSettings.libraryXMLURL else {
            NotificationCenter.default.post(name: .flacNestLibraryDidLoad, object: nil)
            return
        }
        guard FileManager.default.fileExists(atPath: xmlURL.path) else {
            NotificationCenter.default.post(name: .flacNestLibraryDidLoad, object: nil)
            return
        }
        do {
            library = try FlacNestLibraryStore.load(from: xmlURL)
            statusMessage = "Loaded \(library.albums.count) albums from library."
        } catch {
            library = FlacNestLibrary()
            statusMessage = "Could not read flacnest.xml (\(error.localizedDescription)). Use Refresh Library to rebuild it."
        }
        NotificationCenter.default.post(name: .flacNestLibraryDidLoad, object: nil)
    }

    func refreshLibrary() {
        guard let root = AppSettings.libraryRootURL else {
            statusMessage = "Set a library folder in Settings first."
            return
        }

        scanTask?.cancel()
        scanTask = Task {
            await performScan(libraryRoot: root)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    var selectedAlbum: LibraryAlbum? {
        guard let id = selectedAlbumID else { return nil }
        return library.albums.first { $0.id == id }
    }

    var displayedSections: [LibraryAlbumSection] {
        let albums = showFavoritesOnly
            ? library.albums.filter(\.isFavorite)
            : library.albums
        return LibraryAlbumSorting.sections(
            from: albums,
            sortMode: sortMode,
            groupMode: groupMode
        )
    }

    func setShowFavoritesOnly(_ enabled: Bool) {
        showFavoritesOnly = enabled
        AppSettings.libraryShowFavoritesOnly = enabled
    }

    func setSortMode(_ mode: LibrarySortMode) {
        sortMode = mode
        AppSettings.librarySortMode = mode
    }

    func setGroupMode(_ mode: LibraryGroupMode) {
        groupMode = mode
        AppSettings.libraryGroupMode = mode
    }

    func artworkURL(for album: LibraryAlbum) -> URL? {
        AlbumArtworkImporter.artworkURL(for: album, libraryRoot: AppSettings.libraryRootURL)
    }

    func updateAlbum(_ album: LibraryAlbum) throws {
        guard let index = library.albums.firstIndex(where: { $0.id == album.id }) else { return }
        library.albums[index] = album
        try saveLibraryToDisk()
        statusMessage = "Saved metadata for \(album.displayTitle)."
    }

    func album(forBarcode barcode: String) -> LibraryAlbum? {
        let normalized = Self.normalizeBarcode(barcode)
        guard !normalized.isEmpty else { return nil }
        return library.albums.first { Self.normalizeBarcode($0.barcode ?? "") == normalized }
    }

    func toggleFavorite(for albumID: String) throws {
        guard let index = library.albums.firstIndex(where: { $0.id == albumID }) else { return }
        library.albums[index].isFavorite.toggle()
        try saveLibraryToDisk()
    }

    func assignBarcode(_ barcode: String, to albumID: String) throws {
        let normalized = Self.normalizeBarcode(barcode)
        guard !normalized.isEmpty else { return }

        for index in library.albums.indices where library.albums[index].id != albumID {
            if Self.normalizeBarcode(library.albums[index].barcode ?? "") == normalized {
                library.albums[index].barcode = nil
            }
        }

        guard let index = library.albums.firstIndex(where: { $0.id == albumID }) else { return }
        library.albums[index].barcode = normalized
        try saveLibraryToDisk()
        statusMessage = "Assigned barcode to \(library.albums[index].displayTitle)."
    }

    static func normalizeBarcode(_ barcode: String) -> String {
        barcode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func albumMatchesSearch(_ album: LibraryAlbum, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let haystack = [
            album.displayTitle,
            album.performer,
            album.flacRelativePath,
            album.cueRelativePath,
            album.barcode ?? "",
        ]
        .joined(separator: " ")
        .localizedLowercase

        return trimmed.localizedLowercase
            .split(whereSeparator: \.isWhitespace)
            .allSatisfy { haystack.contains($0) }
    }

    func saveLibraryToDisk() throws {
        guard let xmlURL = AppSettings.libraryXMLURL else {
            throw LibraryViewModelError.libraryXMLNotConfigured
        }
        try FlacNestLibraryStore.save(library, to: xmlURL)
    }

    private func performScan(libraryRoot: URL) async {
        isScanning = true
        lastProgressUpdate = .distantPast
        applyScanProgress(ScanProgress(phase: .discovering), force: true)
        statusMessage = "Discovering CUE files…"

        let result: LibraryScanResult = await withTaskGroup(of: LibraryScanResult.self) { group in
            group.addTask(priority: .userInitiated) {
                LibraryScanner.scan(libraryRoot: libraryRoot, shouldCancel: { Task.isCancelled }) { progress in
                    Task { @MainActor in
                        self.handleScanProgress(progress)
                    }
                }
            }
            return await group.next() ?? LibraryScanResult(library: FlacNestLibrary(), skippedCues: [])
        }

        guard !Task.isCancelled else {
            finishScan(cancelled: true)
            return
        }

        applyScanProgress(ScanProgress(phase: .saving), force: true)
        statusMessage = "Saving flacnest.xml…"
        let preservedBarcodes = Dictionary(
            uniqueKeysWithValues: library.albums.compactMap { album in
                album.barcode.map { (album.id, $0) }
            }
        )
        let preservedFavorites = Set(library.albums.filter(\.isFavorite).map(\.id))
        library = result.library
        for index in library.albums.indices {
            library.albums[index].barcode = preservedBarcodes[library.albums[index].id]
            library.albums[index].isFavorite = preservedFavorites.contains(library.albums[index].id)
        }

        if let xmlURL = AppSettings.libraryXMLURL {
            do {
                try await Task(priority: .utility) {
                    try FlacNestLibraryStore.save(library, to: xmlURL)
                }.value
            } catch {
                statusMessage = "Found \(result.library.albums.count) albums, but saving flacnest.xml failed: \(error.localizedDescription)"
                finishScan(cancelled: false)
                return
            }
        }

        guard !Task.isCancelled else {
            finishScan(cancelled: true)
            return
        }

        var message = "Found \(result.library.albums.count) albums. Saved to flacnest.xml."
        if !result.skippedCues.isEmpty {
            message += " Skipped \(result.skippedCues.count) CUE file(s)."
        }
        statusMessage = message
        finishScan(cancelled: false)
    }

    private func handleScanProgress(_ progress: ScanProgress) {
        guard isScanning else { return }
        applyScanProgress(progress)
    }

    private func applyScanProgress(_ progress: ScanProgress, force: Bool = false) {
        let now = Date()
        let shouldUpdate = force
            || progress.phase != .processing
            || progress.processed == progress.total
            || progress.processed == 0
            || now.timeIntervalSince(lastProgressUpdate) >= 0.1

        guard shouldUpdate else { return }

        lastProgressUpdate = now
        scanProgress = progress

        switch progress.phase {
        case .discovering:
            statusMessage = "Discovering CUE files…"
        case .processing:
            if progress.total > 0 {
                statusMessage = "Processing \(progress.processed) of \(progress.total)…"
            } else {
                statusMessage = "Processing albums…"
            }
        case .saving:
            statusMessage = "Saving flacnest.xml…"
        case .idle:
            break
        }
    }

    private func finishScan(cancelled: Bool) {
        isScanning = false
        scanProgress = ScanProgress()
        if cancelled {
            statusMessage = "Library scan cancelled."
        }
        scanTask = nil
    }
}

enum LibraryViewModelError: LocalizedError {
    case libraryXMLNotConfigured

    var errorDescription: String? {
        switch self {
        case .libraryXMLNotConfigured:
            return "Library data file location is not configured."
        }
    }
}

enum FolderPicker {
    @MainActor
    static func chooseLibraryFolder() -> URL? {
        chooseDirectory(
            title: "Choose FLAC Library Home",
            message: "Select the folder that contains your FLAC albums and CUE sheets."
        )
    }

    @MainActor
    static func chooseLibraryXMLFolder() -> URL? {
        chooseDirectory(
            title: "Choose Library Data Folder",
            message: "Select the folder where flacnest.xml should be stored."
        )
    }

    @MainActor
    private static func chooseDirectory(title: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        return url
    }
}
