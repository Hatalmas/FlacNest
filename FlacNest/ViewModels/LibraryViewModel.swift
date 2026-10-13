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
    @Published var sidebarFilter: LibrarySidebarFilter = AppSettings.librarySidebarFilter
    @Published var filterText = ""
    @Published private(set) var artworkEpoch = 0

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
            var collected = loaded
            let didCollect = AlbumArtworkStore.collect(into: &collected, libraryRoot: AppSettings.libraryRootURL)
            library = collected
            if didCollect {
                try? saveLibraryToDisk()
                ArtworkImageCache.removeAll()
            }
            statusMessage = "Loaded \(collected.albums.count) albums from library."
            await rebuildDisplayedSectionsAndWait(for: collected)
            hasLoadedLibrary = true
        case .failure(let error):
            library = FlacNestLibrary()
            displayedSections = []
            isPreparingLibraryUI = false
            statusMessage = "Could not read flacnest.xml (\(error.localizedDescription)). Use Refresh Library to import albums from your files again."
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
        let sidebarFilter = self.sidebarFilter
        let sortMode = self.sortMode
        let groupMode = self.groupMode

        isPreparingLibraryUI = true
        sectionsTask = Task {
            let sections = await Task.detached(priority: .userInitiated) {
                Self.buildDisplayedSections(
                    library: sourceLibrary,
                    filter: sidebarFilter,
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

        let sidebarFilter = self.sidebarFilter
        let sortMode = self.sortMode
        let groupMode = self.groupMode
        isPreparingLibraryUI = true

        let sections = await Task.detached(priority: .userInitiated) {
            Self.buildDisplayedSections(
                library: library,
                filter: sidebarFilter,
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
        filter: LibrarySidebarFilter,
        sortMode: LibrarySortMode,
        groupMode: LibraryGroupMode
    ) -> [LibraryAlbumSection] {
        let albums = library.albums.filter { matches($0, filter: filter) }
        return LibraryAlbumSorting.sections(from: albums, sortMode: sortMode, groupMode: groupMode)
    }

    nonisolated static func matches(_ album: LibraryAlbum, filter: LibrarySidebarFilter) -> Bool {
        switch filter {
        case .allAlbums:
            return true
        case .favorites:
            return album.isFavorite
        case .noBarcode:
            return !album.hasRegisteredBarcode
        case .noCoverArt:
            return !album.hasCoverArt
        case .noMetadata:
            return !album.hasCatalogMetadata
        }
    }

    func refreshLibrary() {
        guard let root = AppSettings.libraryRootURL else {
            statusMessage = "Set a library folder in Settings first."
            return
        }

        scanTask?.cancel()
        scanTask = Task {
            await performAdditiveScan(in: root, libraryRoot: root, sourceLabel: nil)
        }
    }

    func scanSubfolder() {
        guard let libraryRoot = AppSettings.libraryRootURL else {
            statusMessage = "Set a library folder in Settings first."
            return
        }

        guard let subfolder = FolderPicker.chooseSubfolder(relativeTo: libraryRoot) else { return }

        guard FolderPicker.isDirectory(subfolder, containedIn: libraryRoot) else {
            statusMessage = "The selected folder must be inside your library home folder."
            return
        }

        scanTask?.cancel()
        scanTask = Task {
            await performAdditiveScan(
                in: subfolder,
                libraryRoot: libraryRoot,
                sourceLabel: subfolder.lastPathComponent
            )
        }
    }

    func rereadMetadata() {
        guard let root = AppSettings.libraryRootURL else {
            statusMessage = "Set a library folder in Settings first."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Re-read Metadata from Files?"
        alert.informativeText = "FlacNest will replace album and track names from CUE/FLAC files. Barcodes, favorites, and artwork you added are kept. Titles and other fields you edited will be overwritten."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Re-read Metadata")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        scanTask?.cancel()
        scanTask = Task {
            await performMetadataReread(libraryRoot: root)
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
        setSidebarFilter(enabled ? .favorites : .allAlbums)
    }

    func setSidebarFilter(_ filter: LibrarySidebarFilter) {
        sidebarFilter = filter
        showFavoritesOnly = filter == .favorites
        AppSettings.librarySidebarFilter = filter
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
        let previous = library.albums[index]
        if previous.artworkRelativePath != nil, album.artworkRelativePath == nil {
            AlbumArtworkStore.removeStoredArtwork(for: previous)
        }
        if let url = artworkURL(for: previous) {
            ArtworkImageCache.removeImage(for: url)
        }
        if let url = artworkURL(for: album) {
            ArtworkImageCache.removeImage(for: url)
        }
        artworkEpoch += 1
        library.albums[index] = album
        try saveLibraryToDisk()
        rebuildDisplayedSections()
        statusMessage = "Saved metadata for \(album.displayTitle)."
    }

    func removeAlbum(withID albumID: String) throws {
        guard let index = library.albums.firstIndex(where: { $0.id == albumID }) else { return }

        let title = library.albums[index].displayTitle
        AlbumArtworkStore.removeStoredArtwork(for: library.albums[index])
        library.albums.remove(at: index)

        if selectedAlbumID == albumID {
            selectedAlbumID = nil
        }

        try saveLibraryToDisk()
        rebuildDisplayedSections()
        statusMessage = "Removed \(title) from library."
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
        if AlbumArtworkStore.collect(into: &library, libraryRoot: AppSettings.libraryRootURL) {
            ArtworkImageCache.removeAll()
        }
        try FlacNestLibraryStore.save(library, to: xmlURL)
    }

    private func performAdditiveScan(in scanRoot: URL, libraryRoot: URL, sourceLabel: String?) async {
        guard AppSettings.libraryXMLURL != nil else {
            statusMessage = "Library data file location is not configured."
            return
        }

        isScanning = true
        lastProgressUpdate = .distantPast
        applyScanProgress(ScanProgress(phase: .discovering), force: true)
        if let sourceLabel {
            statusMessage = "Looking for new albums in \(sourceLabel)…"
        } else {
            statusMessage = "Looking for new albums…"
        }

        let previousAlbums = library.albums
        let skipCueRelativePaths = Set(
            library.albums
                .filter { !$0.needsDiskMetadataFill }
                .map(\.cueRelativePath)
        )

        let result: LibraryScanResult = await withTaskGroup(of: LibraryScanResult.self) { group in
            group.addTask(priority: .userInitiated) {
                LibraryScanner.scan(
                    in: scanRoot,
                    libraryRoot: libraryRoot,
                    skipCueRelativePaths: skipCueRelativePaths,
                    shouldCancel: { Task.isCancelled }
                ) { progress in
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

        var newAlbums: [LibraryAlbum] = []
        var filledCount = 0

        for scanned in result.library.albums {
            if let existingIndex = library.albums.firstIndex(where: {
                $0.cueRelativePath == scanned.cueRelativePath || $0.flacRelativePath == scanned.flacRelativePath
            }) {
                if Self.fillMissingMetadata(in: &library.albums[existingIndex], from: scanned, libraryRoot: libraryRoot) {
                    filledCount += 1
                }
                continue
            }

            newAlbums.append(scanned)
        }

        guard !newAlbums.isEmpty || filledCount > 0 else {
            statusMessage = Self.additiveScanMessage(
                added: 0,
                filled: 0,
                hadExistingAlbums: !previousAlbums.isEmpty,
                skippedCues: result.skippedCues.count,
                sourceLabel: sourceLabel
            )
            finishScan(cancelled: false)
            return
        }

        applyScanProgress(ScanProgress(phase: .saving), force: true)
        statusMessage = "Saving flacnest.xml…"

        library.albums.append(contentsOf: newAlbums)
        library.scannedAt = Date()
        _ = AlbumArtworkStore.collect(into: &library, libraryRoot: libraryRoot)
        ArtworkImageCache.removeAll()

        if let xmlURL = AppSettings.libraryXMLURL {
            do {
                try await Task(priority: .utility) {
                    try FlacNestLibraryStore.save(library, to: xmlURL)
                }.value
            } catch {
                library.albums = previousAlbums
                statusMessage = "Found \(newAlbums.count) new album(s), but saving flacnest.xml failed: \(error.localizedDescription)"
                finishScan(cancelled: false)
                return
            }
        }

        guard !Task.isCancelled else {
            library.albums = previousAlbums
            finishScan(cancelled: true)
            return
        }

        statusMessage = Self.additiveScanMessage(
            added: newAlbums.count,
            filled: filledCount,
            hadExistingAlbums: !previousAlbums.isEmpty,
            skippedCues: result.skippedCues.count,
            sourceLabel: sourceLabel
        )
        await rebuildDisplayedSectionsAndWait(for: library)
        finishScan(cancelled: false)
        postLibraryDidLoad()
    }

    private func performMetadataReread(libraryRoot: URL) async {
        isScanning = true
        lastProgressUpdate = .distantPast
        applyScanProgress(ScanProgress(phase: .discovering), force: true)
        statusMessage = "Re-reading metadata from CUE files…"

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
        _ = AlbumArtworkStore.collect(into: &library, libraryRoot: libraryRoot)
        ArtworkImageCache.removeAll()

        if let xmlURL = AppSettings.libraryXMLURL {
            do {
                try await Task(priority: .utility) {
                    try FlacNestLibraryStore.save(library, to: xmlURL)
                }.value
            } catch {
                statusMessage = "Re-read \(result.library.albums.count) albums, but saving flacnest.xml failed: \(error.localizedDescription)"
                finishScan(cancelled: false)
                return
            }
        }

        guard !Task.isCancelled else {
            finishScan(cancelled: true)
            return
        }

        var message = "Re-read \(result.library.albums.count) albums from CUE files. Saved to flacnest.xml."
        if !result.skippedCues.isEmpty {
            message += " Skipped \(result.skippedCues.count) CUE file(s)."
        }
        statusMessage = message
        await rebuildDisplayedSectionsAndWait(for: library)
        finishScan(cancelled: false)
        postLibraryDidLoad()
    }

    private static func additiveScanMessage(
        added: Int,
        filled: Int,
        hadExistingAlbums: Bool,
        skippedCues: Int,
        sourceLabel: String?
    ) -> String {
        var parts: [String] = []
        let location = sourceLabel.map { " in \($0)" } ?? ""

        if added > 0 {
            parts.append("Added \(added) album\(added == 1 ? "" : "s")\(location).")
        }
        if filled > 0 {
            parts.append("Filled missing metadata on \(filled) album\(filled == 1 ? "" : "s").")
        }
        if parts.isEmpty {
            var message = "No new albums found\(location)."
            if hadExistingAlbums {
                message += " Existing albums were left unchanged."
            }
            if skippedCues > 0 {
                message += " Skipped \(skippedCues) CUE file(s)."
            }
            return message
        }
        if skippedCues > 0 {
            parts.append("Skipped \(skippedCues) CUE file(s).")
        }
        return parts.joined(separator: " ")
    }

    @discardableResult
    private static func fillMissingMetadata(
        in existing: inout LibraryAlbum,
        from scanned: LibraryAlbum,
        libraryRoot: URL
    ) -> Bool {
        var changed = false

        func fillString(_ destination: inout String, _ source: String) {
            if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                destination = source
                changed = true
            }
        }

        func fillOptional(_ destination: inout String?, _ source: String?) {
            let destinationEmpty = destination?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            let sourceValue = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if destinationEmpty && !sourceValue.isEmpty {
                destination = source
                changed = true
            }
        }

        fillString(&existing.title, scanned.title)
        fillString(&existing.performer, scanned.performer)
        fillOptional(&existing.genre, scanned.genre)
        fillOptional(&existing.date, scanned.date)
        fillOptional(&existing.discID, scanned.discID)
        fillOptional(&existing.comment, scanned.comment)
        fillString(&existing.parentFolder, scanned.parentFolder)

        if !existing.hasCoverArt, scanned.hasCoverArt {
            existing.artworkRelativePath = scanned.artworkRelativePath
            existing.artworkBookmark = scanned.artworkBookmark
            changed = true
        }

        if !existing.hasRegisteredBarcode, scanned.hasRegisteredBarcode {
            existing.barcode = scanned.barcode
            changed = true
        }

        if existing.flacRelativePath != scanned.flacRelativePath,
           !scanned.flacRelativePath.isEmpty {
            let existingURL = libraryRoot.appendingPathComponent(existing.flacRelativePath)
            let existingMissing = existing.flacRelativePath.isEmpty
                || !FileManager.default.fileExists(atPath: existingURL.path)
            if existingMissing {
                existing.flacRelativePath = scanned.flacRelativePath
                changed = true
            }
        }

        if existing.tracks.isEmpty, !scanned.tracks.isEmpty {
            existing.tracks = scanned.tracks
            changed = true
        } else {
            let scannedByNumber = Dictionary(uniqueKeysWithValues: scanned.tracks.map { ($0.number, $0) })
            for index in existing.tracks.indices {
                guard let scannedTrack = scannedByNumber[existing.tracks[index].number] else { continue }
                if existing.tracks[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !scannedTrack.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.tracks[index].title = scannedTrack.title
                    changed = true
                }
                let performerEmpty = existing.tracks[index].performer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                if performerEmpty,
                   let performer = scannedTrack.performer?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !performer.isEmpty {
                    existing.tracks[index].performer = performer
                    changed = true
                }
            }
        }

        return changed
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
            message: "Select the folder that contains your FLAC albums and CUE sheets.",
            canCreateDirectories: true
        )
    }

    @MainActor
    static func chooseRelocatedLibraryFolder() -> URL? {
        chooseDirectory(
            title: "Re-locate Library Home",
            message: "Select the folder where your FLAC library has been moved.",
            canCreateDirectories: false,
            directoryURL: AppSettings.libraryRootURL
        )
    }

    @MainActor
    static func chooseLibraryXMLFolder() -> URL? {
        chooseDirectory(
            title: "Choose Library Data Folder",
            message: "Select the folder where flacnest.xml should be stored.",
            canCreateDirectories: true
        )
    }

    @MainActor
    static func chooseSubfolder(relativeTo libraryRoot: URL) -> URL? {
        chooseDirectory(
            title: "Refresh Subfolder",
            message: "Select a folder inside your library home to look for new CUE/FLAC albums. Existing metadata is left unchanged.",
            canCreateDirectories: false,
            directoryURL: libraryRoot
        )
    }

    @MainActor
    static func chooseMetadataExportFolder() -> URL? {
        chooseDirectory(
            title: "Export Library Metadata",
            message: "Choose a folder for \(MetadataTransferPackage.fileName).",
            canCreateDirectories: true
        )
    }

    @MainActor
    static func chooseImportedLibraryFolder(albumCount: Int, sourceRootPath: String?) -> URL? {
        var message = "Select the folder where you moved your FLAC albums (\(albumCount) in this export)."
        if let sourceRootPath, !sourceRootPath.isEmpty {
            message += " On the original Mac it was “\((sourceRootPath as NSString).lastPathComponent)”."
        }
        return chooseDirectory(
            title: "Choose FLAC Library Folder",
            message: message,
            canCreateDirectories: false,
            directoryURL: AppSettings.libraryRootURL
        )
    }

    @MainActor
    static func isDirectory(_ directory: URL, containedIn parent: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        guard !parentPath.isEmpty else { return false }
        return directoryPath == parentPath || directoryPath.hasPrefix(parentPath + "/")
    }

    @MainActor
    private static func chooseDirectory(
        title: String,
        message: String,
        canCreateDirectories: Bool = false,
        directoryURL: URL? = nil
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = canCreateDirectories
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let directoryURL {
            panel.directoryURL = directoryURL
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        return url
    }
}
