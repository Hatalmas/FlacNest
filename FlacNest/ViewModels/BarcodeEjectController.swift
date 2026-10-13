import AppKit
import Foundation

@MainActor
final class BarcodeEjectController: ObservableObject {
    static let playerHostID = "player"
    static let libraryHostID = "library"

    @Published var isPresenting = false
    @Published private(set) var hostID: String?

    func presentEject() {
        hostID = Self.preferredHostID()
        isPresenting = true
    }

    func dismiss() {
        isPresenting = false
        hostID = nil
    }

    func isPresenting(on hostID: String) -> Bool {
        isPresenting && self.hostID == hostID
    }

    private static func preferredHostID() -> String {
        if let key = NSApp.keyWindow {
            if PlayerWindowSizing.isPlayerWindow(key), PlayerWindowSizing.isPlayerWindowOpen {
                return playerHostID
            }
            if PlayerWindowSizing.isLibraryWindow(key), PlayerWindowSizing.isLibraryWindowOpen {
                return libraryHostID
            }
        }
        if PlayerWindowSizing.isLibraryWindowOpen {
            return libraryHostID
        }
        return playerHostID
    }
}
