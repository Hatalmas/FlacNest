import AppKit
import Foundation

enum LibraryXMLMoveChoice {
    case move
    case leave
    case cancel
}

enum LibraryXMLLocationChange {
    @MainActor
    static func promptToMoveExistingFile(from oldURL: URL, to newURL: URL) -> LibraryXMLMoveChoice {
        let alert = NSAlert()
        alert.messageText = "Move flacnest.xml?"
        alert.informativeText = """
        A library file already exists at:
        \(oldURL.path)

        Do you want to move it to:
        \(newURL.path)?
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Don't Move")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .move
        case .alertSecondButtonReturn:
            return .leave
        default:
            return .cancel
        }
    }

    @MainActor
    static func apply(
        useCustomLocation: Bool,
        customDirectory: URL?,
        previousXMLURL: URL?
    ) -> Bool {
        let newXMLURL = proposedLibraryXMLURL(useCustomLocation: useCustomLocation, customDirectory: customDirectory)

        if let previousXMLURL, let newXMLURL, previousXMLURL != newXMLURL,
           FileManager.default.fileExists(atPath: previousXMLURL.path) {
            switch promptToMoveExistingFile(from: previousXMLURL, to: newXMLURL) {
            case .cancel:
                return false
            case .move:
                do {
                    _ = try AppSettings.moveLibraryXML(from: previousXMLURL, to: newXMLURL)
                } catch {
                    showError("Could not move flacnest.xml: \(error.localizedDescription)")
                    return false
                }
            case .leave:
                break
            }
        }

        AppSettings.useCustomLibraryXMLLocation = useCustomLocation
        if useCustomLocation {
            AppSettings.libraryXMLDirectoryURL = customDirectory
        } else {
            AppSettings.libraryXMLDirectoryURL = nil
        }

        NotificationCenter.default.post(name: .flacNestLibraryRootDidChange, object: nil)
        return true
    }

    static func proposedLibraryXMLURL(useCustomLocation: Bool, customDirectory: URL?) -> URL? {
        if useCustomLocation, let customDirectory {
            return customDirectory.appendingPathComponent("flacnest.xml", isDirectory: false)
        }
        return AppSettings.libraryRootXMLURL
    }

    @MainActor
    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Library File"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
