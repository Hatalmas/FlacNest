import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isPrimaryInstance = true

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        if let existingInstance = otherInstances.first {
            isPrimaryInstance = false
            existingInstance.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isPrimaryInstance else { return }

        if AppSettings.libraryRootURL == nil {
            if let url = FolderPicker.chooseLibraryFolder() {
                AppSettings.libraryRootURL = url
            }
        }
        NotificationCenter.default.post(name: .flacNestLibraryRootDidChange, object: nil)

        DispatchQueue.main.async {
            DockIconVisibility.sync()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .flacNestApplicationWillTerminate, object: nil)
        AlbumArtworkImporter.stopAccessingArtwork()
        AppSettings.stopAccessing()
    }
}

extension Notification.Name {
    static let flacNestLibraryRootDidChange = Notification.Name("flacNestLibraryRootDidChange")
    static let flacNestLibraryDidLoad = Notification.Name("flacNestLibraryDidLoad")
    static let flacNestApplicationWillTerminate = Notification.Name("flacNestApplicationWillTerminate")
    static let flacNestMainWindowVisibilityDidChange = Notification.Name("flacNestMainWindowVisibilityDidChange")
}
