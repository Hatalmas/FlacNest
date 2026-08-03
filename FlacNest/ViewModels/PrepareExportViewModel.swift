import AppKit
import Foundation
import SwiftUI

@MainActor
final class PrepareExportViewModel: ObservableObject {
    @Published var bitrate: MobileExportBitrate = .kbps320
    @Published var parallelism: MobileExportParallelism = .four
    @Published var exportDirectoryPath: String = ""
    @Published var isRunning = false
    @Published var progress = MobileExportProgress()
    @Published var statusMessage: String?

    private var exportTask: Task<Void, Never>?
    private var exportCancellation: ExportCancellation?
    private var exportDirectoryURL: URL?
    private var exportDirectoryBookmark: Data?

    private static let exportDirectoryBookmarkKey = "mobileExportDirectoryBookmark"
    private static let exportDirectoryPathKey = "mobileExportDirectoryPath"
    private static let exportBitrateKey = "mobileExportBitrate"
    private static let exportParallelismKey = "mobileExportParallelism"

    init() {
        if let raw = UserDefaults.standard.object(forKey: Self.exportBitrateKey) as? Int,
           let saved = MobileExportBitrate(rawValue: raw) {
            bitrate = saved
        }
        if let raw = UserDefaults.standard.object(forKey: Self.exportParallelismKey) as? Int,
           let saved = MobileExportParallelism(rawValue: raw) {
            parallelism = saved
        }
        exportDirectoryPath = UserDefaults.standard.string(forKey: Self.exportDirectoryPathKey) ?? ""
        exportDirectoryBookmark = UserDefaults.standard.data(forKey: Self.exportDirectoryBookmarkKey)
        exportDirectoryURL = resolveExportDirectoryURL()
    }

    var canStart: Bool {
        !isRunning && exportDirectoryURL != nil
    }

    func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Directory"
        panel.message = "Select the folder where MP3 files and flacnestmobile.xml will be written."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if let url = exportDirectoryURL {
            panel.directoryURL = url
        }

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        setExportDirectory(url)
    }

    func startExport(library: FlacNestLibrary, artworkURLProvider: @escaping (LibraryAlbum) -> URL?) {
        guard !isRunning else { return }
        guard let exportDirectory = exportDirectoryURL else {
            statusMessage = "Choose an export directory first."
            return
        }
        guard let libraryRoot = AppSettings.libraryRootURL else {
            statusMessage = "Set a library folder in Settings first."
            return
        }
        guard !library.albums.isEmpty else {
            statusMessage = "There are no albums to export."
            return
        }

        UserDefaults.standard.set(bitrate.rawValue, forKey: Self.exportBitrateKey)
        UserDefaults.standard.set(parallelism.rawValue, forKey: Self.exportParallelismKey)

        let cancellation = ExportCancellation()
        exportCancellation = cancellation
        isRunning = true
        progress = MobileExportProgress(phase: .preparing)
        statusMessage = nil

        let selectedBitrate = bitrate
        let selectedParallelism = parallelism.rawValue
        let exportPath = exportDirectory.path
        let artworkSourceURLs = Dictionary(
            uniqueKeysWithValues: library.albums.compactMap { album in
                artworkURLProvider(album).map { (album.id, $0) }
            }
        )

        exportTask = Task {
            let accessingExport = exportDirectory.startAccessingSecurityScopedResource()
            defer {
                if accessingExport {
                    exportDirectory.stopAccessingSecurityScopedResource()
                }
                exportCancellation = nil
                isRunning = false
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try MobileLibraryPreparer.prepareExport(
                        library: library,
                        libraryRoot: libraryRoot,
                        exportDirectory: exportDirectory,
                        bitrate: selectedBitrate,
                        parallelJobs: selectedParallelism,
                        artworkSourceURLs: artworkSourceURLs,
                        cancellation: cancellation,
                        reportProgress: { update in
                            Task { @MainActor in
                                self.applyProgress(update)
                            }
                        }
                    )
                }.value

                applyProgress(result)
                switch result.phase {
                case .finished:
                    statusMessage = "Export finished. Output: \(exportPath)"
                case .cancelled:
                    statusMessage = "Export cancelled."
                default:
                    break
                }
            } catch MobileLibraryExportError.cancelled {
                var cancelled = progress
                cancelled.phase = .cancelled
                cancelled.currentItem = ""
                appendLog(&cancelled, "Export cancelled.")
                applyProgress(cancelled)
                statusMessage = "Export cancelled."
            } catch {
                var failed = progress
                failed.phase = .failed
                failed.currentItem = ""
                appendLog(&failed, error.localizedDescription)
                applyProgress(failed)
                statusMessage = error.localizedDescription
            }
        }
    }

    func cancelExport() {
        exportCancellation?.cancel()
        exportTask?.cancel()
    }

    private func setExportDirectory(_ url: URL) {
        exportDirectoryURL = url
        exportDirectoryPath = url.path

        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            exportDirectoryBookmark = data
            UserDefaults.standard.set(data, forKey: Self.exportDirectoryBookmarkKey)
        }

        UserDefaults.standard.set(url.path, forKey: Self.exportDirectoryPathKey)
    }

    private func resolveExportDirectoryURL() -> URL? {
        if let data = exportDirectoryBookmark {
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
                    exportDirectoryBookmark = refreshed
                    UserDefaults.standard.set(refreshed, forKey: Self.exportDirectoryBookmarkKey)
                }
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }

        let path = exportDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func applyProgress(_ update: MobileExportProgress) {
        progress = update
    }

    private func appendLog(_ progress: inout MobileExportProgress, _ line: String) {
        progress.logLines.append(line)
        if progress.logLines.count > 10 {
            progress.logLines.removeFirst(progress.logLines.count - 10)
        }
    }
}
