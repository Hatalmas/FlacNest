import SwiftUI
import AppKit

@main
struct FlacNestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("playerTrackListVisible") private var playerTrackListVisible = false
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.system.rawValue
    @AppStorage(AppSettings.showStatusMenuKey) private var showStatusMenu = false
    @StateObject private var playback = PlaybackController()
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var playerWindowTracker = PlayerWindowTracker()
    @StateObject private var libraryWindowTracker = LibraryWindowTracker()
    @StateObject private var barcodeEject = BarcodeEjectController()

    private var preferredColorScheme: ColorScheme? {
        (AppTheme(rawValue: themeRawValue) ?? .system).colorScheme
    }

    var body: some Scene {
        Window("FlacNest Player", id: "player") {
            PlayerView()
                .environmentObject(playback)
                .environmentObject(libraryVM)
                .environmentObject(playerWindowTracker)
                .environmentObject(libraryWindowTracker)
                .environmentObject(barcodeEject)
                .flacNestFocusedCommands(
                    playback: playback,
                    onEject: { barcodeEject.presentEject() }
                )
                .onReceive(NotificationCenter.default.publisher(for: .flacNestLibraryRootDidChange)) { _ in
                    playback.configure(libraryRoot: AppSettings.libraryRootURL)
                    libraryVM.loadFromDisk()
                }
                .onReceive(NotificationCenter.default.publisher(for: .flacNestLibraryDidLoad)) { _ in
                    playback.restoreLastPlayback(from: libraryVM.library)
                }
                .onReceive(NotificationCenter.default.publisher(for: .flacNestApplicationWillTerminate)) { _ in
                    playback.saveResumeStateIfNeeded()
                }
                .onAppear {
                    configureSharedPlayback()
                }
                .preferredColorScheme(preferredColorScheme)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: PlayerWindowSizing.savedSize(trackListVisible: playerTrackListVisible).width,
            height: PlayerWindowSizing.savedSize(trackListVisible: playerTrackListVisible).height
        )
        .commands {
            FlacNestCommands()
        }

        Window("FlacNest Library", id: "library") {
            LibraryManagerView()
                .environmentObject(playback)
                .environmentObject(libraryVM)
                .environmentObject(playerWindowTracker)
                .environmentObject(libraryWindowTracker)
                .environmentObject(barcodeEject)
                .onReceive(NotificationCenter.default.publisher(for: .flacNestLibraryRootDidChange)) { _ in
                    playback.configure(libraryRoot: AppSettings.libraryRootURL)
                    libraryVM.loadFromDisk()
                }
                .onAppear {
                    configureSharedPlayback()
                }
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 720, height: 560)

        Settings {
            SettingsView()
                .onReceive(NotificationCenter.default.publisher(for: .flacNestLibraryRootDidChange)) { _ in
                    playback.configure(libraryRoot: AppSettings.libraryRootURL)
                    libraryVM.loadFromDisk()
                }
                .preferredColorScheme(preferredColorScheme)
        }

        MenuBarExtra(isInserted: $showStatusMenu) {
            StatusMenuContent()
                .environmentObject(playback)
                .environmentObject(libraryVM)
                .preferredColorScheme(preferredColorScheme)
        } label: {
            StatusMenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }

    private func configureSharedPlayback() {
        playback.configure(libraryRoot: AppSettings.libraryRootURL)
        playback.orderedAlbumsProvider = {
            LibraryAlbumSorting.sorted(libraryVM.library.albums, by: libraryVM.sortMode)
        }
        libraryVM.loadFromDisk()
        MediaRemoteController.shared.configure(playback: playback)
    }
}

enum PlayerWindowSizing {
    static let minWidth: CGFloat = 380
    static let minHeight: CGFloat = 420
    static let defaultCompactSize = NSSize(width: 380, height: 420)
    static let defaultExpandedSize = NSSize(width: 380, height: 560)

    static func savedSize(trackListVisible: Bool) -> NSSize {
        let saved = trackListVisible ? AppSettings.playerExpandedWindowFrame : AppSettings.playerCompactWindowFrame
        let defaultSize = trackListVisible ? defaultExpandedSize : defaultCompactSize
        let width = max(minWidth, saved.map { CGFloat($0.width) } ?? defaultSize.width)
        let height = max(minHeight, saved.map { CGFloat($0.height) } ?? defaultSize.height)
        return NSSize(width: width, height: height)
    }

    static func handleToggle(from wasVisible: Bool, to isVisible: Bool, artworkSize: CGFloat) {
        saveCurrentSize(trackListVisible: wasVisible, artworkSize: artworkSize)
        restoreSize(trackListVisible: isVisible)
    }

    static func saveCurrentSize(trackListVisible: Bool, artworkSize: CGFloat? = nil) {
        guard let window = playerWindow else { return }
        let existing = trackListVisible
            ? AppSettings.playerExpandedWindowFrame
            : AppSettings.playerCompactWindowFrame
        let frame = PlayerWindowFrame(
            width: window.contentLayoutRect.width,
            height: window.contentLayoutRect.height,
            artworkSize: artworkSize.map(Double.init) ?? existing?.artworkSize
        )
        if trackListVisible {
            AppSettings.playerExpandedWindowFrame = frame
        } else {
            AppSettings.playerCompactWindowFrame = frame
        }
    }

    static func restoreSize(trackListVisible: Bool) {
        let targetSize = savedSize(trackListVisible: trackListVisible)
        DispatchQueue.main.async {
            playerWindow?.setContentSize(targetSize)
        }
    }

    static func bringPlayerToFront() {
        DockIconVisibility.prepareToShowMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        playerWindow?.makeKeyAndOrderFront(nil)
    }

    static func detach(openWindow: OpenWindowAction, tracker: PlayerWindowTracker) {
        DockIconVisibility.prepareToShowMainWindow()
        openWindow(id: "player")
        DispatchQueue.main.async {
            bringPlayerToFront()
            tracker.refresh()
            DockIconVisibility.sync()
        }
    }

    static func attach(
        dismissWindow: DismissWindowAction,
        openWindow: OpenWindowAction,
        tracker: PlayerWindowTracker
    ) {
        dismissWindow(id: "player")
        openWindow(id: "library")
        DispatchQueue.main.async {
            bringLibraryToFront()
            tracker.refresh()
        }
    }

    static func bringLibraryToFront() {
        DockIconVisibility.prepareToShowMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow?.makeKeyAndOrderFront(nil)
    }

    static func isPlayerWindow(_ window: NSWindow) -> Bool {
        window.title == "FlacNest Player" || window.identifier?.rawValue == "player"
    }

    static func isLibraryWindow(_ window: NSWindow) -> Bool {
        window.title == "FlacNest Library" || window.identifier?.rawValue == "library"
    }

    static func isMainWindowShown(_ window: NSWindow) -> Bool {
        window.isVisible && window.occlusionState.contains(.visible)
    }

    static var isPlayerWindowOpen: Bool {
        NSApp.windows.contains { isPlayerWindow($0) && isMainWindowShown($0) }
    }

    static var isLibraryWindowOpen: Bool {
        NSApp.windows.contains { isLibraryWindow($0) && isMainWindowShown($0) }
    }

    static func toggleLibrary(
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction,
        tracker: LibraryWindowTracker? = nil
    ) {
        if isLibraryWindowOpen {
            dismissWindow(id: "library")
        } else {
            DockIconVisibility.prepareToShowMainWindow()
            openWindow(id: "library")
            DispatchQueue.main.async {
                bringLibraryToFront()
            }
        }
        DispatchQueue.main.async {
            tracker?.refresh()
            DockIconVisibility.sync()
        }
    }

    private static var playerWindow: NSWindow? {
        NSApp.windows.first(where: isPlayerWindow)
    }

    private static var libraryWindow: NSWindow? {
        NSApp.windows.first(where: isLibraryWindow)
    }
}

@MainActor
final class PlayerWindowTracker: ObservableObject {
    @Published private(set) var isOpen = false

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: .flacNestMainWindowVisibilityDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        )

        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        isOpen = PlayerWindowSizing.isPlayerWindowOpen
        DockIconVisibility.sync()
    }
}

enum DockIconVisibility {
    static func prepareToShowMainWindow() {
        apply(showInDock: true)
    }

    static func sync() {
        apply(
            showInDock: PlayerWindowSizing.isPlayerWindowOpen
                || PlayerWindowSizing.isLibraryWindowOpen
        )
    }

    private static func apply(showInDock: Bool) {
        let target: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != target else { return }
        NSApp.setActivationPolicy(target)
    }
}

@MainActor
final class LibraryWindowTracker: ObservableObject {
    @Published private(set) var isOpen = false

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: .flacNestMainWindowVisibilityDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        )

        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        isOpen = PlayerWindowSizing.isLibraryWindowOpen
        DockIconVisibility.sync()
    }
}

struct MainWindowLifecycleMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> MonitorView {
        MonitorView()
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {}

    final class MonitorView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            unregisterObservers()

            guard let window else {
                scheduleVisibilitySync()
                return
            }

            guard PlayerWindowSizing.isPlayerWindow(window) || PlayerWindowSizing.isLibraryWindow(window) else {
                return
            }

            registerObservers(for: window)
            scheduleVisibilitySync()
        }

        deinit {
            unregisterObservers()
        }

        private func registerObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.willCloseNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
            ]

            for name in names {
                observers.append(
                    center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        self?.scheduleVisibilitySync()
                    }
                )
            }
        }

        private func unregisterObservers() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
        }

        private func scheduleVisibilitySync() {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .flacNestMainWindowVisibilityDidChange, object: nil)
            }
        }
    }
}
