import AppKit
import SwiftUI

enum PortableLibraryExportPresenter {
    @MainActor
    static func exportLibrary(
        _ library: FlacNestLibrary,
        artworkURLProvider: (LibraryAlbum) -> URL?
    ) throws -> URL? {
        guard !library.albums.isEmpty else {
            throw PortableLibraryExportError.libraryEmpty
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Export Destination"
        panel.message = "Select the folder where the read-only iOS/iPad export package should be created."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else {
            throw PortableLibraryExportError.exportCancelled
        }

        let defaultName = "FlacNest Export \(Self.exportDateLabel())"
        return try PortableLibraryExporter.export(
            library: library,
            packageName: defaultName,
            to: destination,
            artworkURLProvider: artworkURLProvider
        )
    }

    private static func exportDateLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }
}
