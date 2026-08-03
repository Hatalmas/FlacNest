import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var library: FlacNestLibrary = FlacNestLibrary()
    @Published private(set) var displayedSections: [LibraryAlbumSection] = []
    @Published var isScanning = false
    @Published private(set) var isLoadingLibrary = false
    @Published private(set) var isPreparingLibraryUI = false
    @Published var scanProgress = ScanProgress()
    @Published var statusMessage: String?
    @Published var selectedAlbumID: String?
    @Published var sortMode: LibrarySortMode = AppSettings.librarySortMode
    @Published var groupMode: LibraryGroupMode = AppSettings.libraryGroupMode
    @Published var showFavoritesOnly: Bool = AppSettings.libraryShowFavoritesOnly
    @Published var filterText = ""

    private var scanTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var sectionsTask: Task<Void, Never>?
    private var rootChangeObserver: NSObjectProtocol?
    private var lastProgressUpdate = Date.distantPast
    private var hasLoadedLibrary = false

    var isLibraryBusy: Bool {
        isLoadingLibrary || isScanning || isPreparingLibraryUI
    }

    var filteredDisplayedSections: [LibraryAlbumSection] {
        displayedSections.filtered(by: filterText)
    }

    init() {
        rootChangeObserver = NotificationCenter.default.addObserver(
            forName: .flacNestLibraryRootDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
        loadFromDisk()
    }

    deinit {
        if let rootChangeObserver {
            NotificationCenter.default.removeObserver(rootChangeObserver)
        }
    }

    func loadFromDisk(force: Bool = false) {
        if isLoadingLibrary {
            if force {
                loadTask?.cancel()
            } else {
                return
            }
        }
        if hasLoadedLibrary && !force {
            return
        }

        loadTask = Task {
            await performLoadFromDisk()
        }
    }

    func reloadFromDisk() {
        hasLoadedLibrary = false
        loadTask?.cancel()
        sectionsTask?.cancel()
        loadFromDisk(force: true)
    }

    private func performLoadFromDisk() async {
        guard let xmlURL = AppSettings.libraryXMLURL else {
            hasLoadedLibrary = true
            postLibraryDidLoad()
            return
        }

        guard FileManager.default.fileExists(atPath: xmlURL.path) else {
            hasLoadedLibrary = true
            postLibraryDidLoad()
            return
        }

        isLoadingLibrary = true
        statusMessage = "Loading library…"

        let result: Result<FlacNestLibrary, Error> = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try FlacNestLibraryStore.load(from: xmlURL))
            } catch {
                return .failure(error)
            }
        }.value

        guard !Task.isCancelled else {
            isLoadingLibrary = false
            return
        }

        isLoadingLibrary = false
        loadTask = nil

        switch result {
        case .success(let loaded):
            library = loaded
            statusMessage = "Loaded \(loaded.albums.count) albums from library."
            await rebuildDisplayedSectionsAndWait(for: loaded)
            hasLoadedLibrary = true
        case .failure(let error):
            library = FlacNestLibrary()
            displayedSections = []
            isPreparingLibraryUI = false
            statusMessage = "Could not read flacnest.xml (\(error.localizedDescription)). Use Refresh Library to rebuild it."
            hasLoadedLibrary = true
        }

        guard !Task.isCancelled else { return }

        postLibraryDidLoad()
    }

    private func postLibraryDidLoad() {
        NotificationCenter.default.post(name: .flacNestLibraryDidLoad, object: nil)
    }

    private func rebuildDisplayedSections(for library: FlacNestLibrary? = nil) {
        sectionsTask?.cancel()
        let sourceLibrary = library ?? self.library
        let showFavoritesOnly = self.showFavoritesOnly
        let sortMode = self.sortMode
        let groupMode = self.groupMode

        isPreparingLibraryUI = true
        sectionsTask = Task {
            let sections = await Task.detached(priority: .userInitiated) {
                Self.buildDisplayedSections(
                    library: sourceLibrary,
                    showFavoritesOnly: showFavoritesOnly,
                    sortMode: sortMode,
                    groupMode: groupMode
                )
            }.value

            guard !Task.isCancelled else { return }

            displayedSections = sections
            isPreparingLibraryUI = false
            sectionsTask = nil
        }
    }

    private func rebuildDisplayedSectionsAndWait(for library: FlacNestLibrary) async {
        sectionsTask?.cancel()

        let showFavoritesOnly = self.showFavoritesOnly
        let sortMode = self.sortMode
        let groupMode = self.groupMode
        isPreparingLibraryUI = true

        let sections = await Task.detached(priority: .userInitiated) {
            Self.buildDisplayedSections(
                library: library,
                showFavoritesOnly: showFavoritesOnly,
                sortMode: sortMode,
                groupMode: groupMode
            )
        }.value

        guard !Task.isCancelled else {
            isPreparingLibraryUI = false
            return
        }

        displayedSections = sections
        isPreparingLibraryUI = false
        sectionsTask = nil
    }

    nonisolated private static func buildDisplayedSections(
        library: FlacNestLibrary,
        showFavoritesOnly: Bool,
        sortMode: LibrarySortMode,
        groupMode: LibraryGroupMode
    ) -> [LibraryAlbumSection] {
        let albums = showFavoritesOnly ? library.albums.filter(\.isFavorite) : library.albums
        return LibraryAlbumSorting.sections(from: albums, sortMode: sortMode, groupMode: groupMode)
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

    func setShowFavoritesOnly(_ enabled: Bool) {
        showFavoritesOnly = enabled
        AppSettings.libraryShowFavoritesOnly = enabled
        rebuildDisplayedSections()
    }

    func setSortMode(_ mode: LibrarySortMode) {
        sortMode = mode
        AppSettings.librarySortMode = mode
        rebuildDisplayedSections()
    }

    func setGroupMode(_ mode: LibraryGroupMode) {
        groupMode = mode
        AppSettings.libraryGroupMode = mode
        rebuildDisplayedSections()
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
        rebuildDisplayedSections()
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
        let preservedArtwork = Dictionary<String, (String, Data?)>(
            uniqueKeysWithValues: library.albums.compactMap { album in
                guard let path = album.artworkRelativePath else { return nil }
                return (album.id, (path, album.artworkBookmark))
            }
        )
        library = result.library
        for index in library.albums.indices {
            library.albums[index].barcode = preservedBarcodes[library.albums[index].id]
            library.albums[index].isFavorite = preservedFavorites.contains(library.albums[index].id)
            if let preserved = preservedArtwork[library.albums[index].id] {
                library.albums[index].artworkRelativePath = preserved.0
                library.albums[index].artworkBookmark = preserved.1
            }
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
        await rebuildDisplayedSectionsAndWait(for: library)
        finishScan(cancelled: false)
        postLibraryDidLoad()
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
