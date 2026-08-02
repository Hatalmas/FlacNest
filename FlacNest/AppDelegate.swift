import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppSettings.libraryRootURL == nil {
            if let url = FolderPicker.chooseLibraryFolder() {
                AppSettings.libraryRootURL = url
            }
        }
        NotificationCenter.default.post(name: .flacNestLibraryRootDidChange, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .flacNestApplicationWillTerminate, object: nil)
        AppSettings.stopAccessing()
    }
}

extension Notification.Name {
    static let flacNestLibraryRootDidChange = Notification.Name("flacNestLibraryRootDidChange")
    static let flacNestLibraryDidLoad = Notification.Name("flacNestLibraryDidLoad")
    static let flacNestApplicationWillTerminate = Notification.Name("flacNestApplicationWillTerminate")
}
