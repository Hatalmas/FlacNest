import AppKit
import Foundation

enum LibraryRootRelocateChoice {
    case saveAnyway
    case selectAgain
    case cancel
}

enum LibraryRootRelocation {
    @MainActor
    @discardableResult
    static func relocateLibrary(currentLibrary: FlacNestLibrary) -> URL? {
        while true {
            guard let newRoot = FolderPicker.chooseRelocatedLibraryFolder() else {
                return nil
            }

            guard let firstAlbum = currentLibrary.albums.first else {
                applyLibraryRoot(newRoot)
                return newRoot
            }

            if albumExists(at: newRoot, album: firstAlbum) {
                applyLibraryRoot(newRoot)
                return newRoot
            }

            switch promptWhenNotFound(album: firstAlbum, newRoot: newRoot) {
            case .saveAnyway:
                applyLibraryRoot(newRoot)
                return newRoot
            case .selectAgain:
                continue
            case .cancel:
                return nil
            }
        }
    }

    static func albumExists(at libraryRoot: URL, album: LibraryAlbum) -> Bool {
        let fileManager = FileManager.default
        let cueURL = libraryRoot.appendingPathComponent(album.cueRelativePath)
        if fileManager.fileExists(atPath: cueURL.path) {
            return true
        }

        let flacURL = libraryRoot.appendingPathComponent(album.flacRelativePath)
        return fileManager.fileExists(atPath: flacURL.path)
    }

    @MainActor
    private static func promptWhenNotFound(album: LibraryAlbum, newRoot: URL) -> LibraryRootRelocateChoice {
        let cuePath = newRoot.appendingPathComponent(album.cueRelativePath).path
        let flacPath = newRoot.appendingPathComponent(album.flacRelativePath).path

        let alert = NSAlert()
        alert.messageText = "First album not found"
        alert.informativeText = """
        The first album in your library could not be found under the selected folder.

        Album: \(album.displayTitle)
        Expected CUE: \(cuePath)
        Expected FLAC: \(flacPath)

        Do you still want to use this folder as the library home?
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save Anyway")
        alert.addButton(withTitle: "Select Again")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .saveAnyway
        case .alertSecondButtonReturn:
            return .selectAgain
        default:
            return .cancel
        }
    }

    @MainActor
    private static func applyLibraryRoot(_ url: URL) {
        AppSettings.libraryRootURL = url
        NotificationCenter.default.post(name: .flacNestLibraryRootDidChange, object: nil)
    }
}
