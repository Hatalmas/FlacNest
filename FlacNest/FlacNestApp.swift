import SwiftUI
import AppKit

@main
struct FlacNestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("playerTrackListVisible") private var playerTrackListVisible = false
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.system.rawValue
    @AppStorage(AppSettings.showStatusMenuKey) private var showStatusMenu = false
    @State private var playback = PlaybackController()
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var playerWindowTracker = PlayerWindowTracker()
    @StateObject private var libraryWindowTracker = LibraryWindowTracker()
    @StateObject private var dockMiniPlayerWindowTracker = DockMiniPlayerWindowTracker()
    @StateObject private var barcodeEject = BarcodeEjectController()

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    var body: some Scene {
        Window("FlacNest Player", id: "player") {
            PlayerView()
                .environment(playback)
                .environmentObject(libraryVM)
                .environmentObject(playerWindowTracker)
                .environmentObject(libraryWindowTracker)
                .environmentObject(dockMiniPlayerWindowTracker)
                .environmentObject(barcodeEject)
                .flacNestFocusedCommands(
                    playback: playback,
                    onEject: { barcodeEject.presentEject() },
                    usesPlayingNowEditCommands: true
                )
                .onReceive(NotificationCenter.default.publisher(for: .flacNestLibraryRootDidChange)) { _ in
                    playback.configure(libraryRoot: AppSettings.libraryRootURL)
                    libraryVM.reloadFromDisk()
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
                .registersMetadataTransferOpener()
                .appTheme(theme)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: PlayerWindowSizing.savedSize(trackListVisible: playerTrackListVisible).width,
            height: PlayerWindowSizing.savedSize(trackListVisible: playerTrackListVisible).height
        )
        .commands {
            FlacNestCommands(playback: playback, barcodeEject: barcodeEject)
        }

        Window("FlacNest Library", id: "library") {
            LibraryManagerView()
                .environment(playback)
                .environmentObject(libraryVM)
                .environmentObject(playerWindowTracker)
                .environmentObject(libraryWindowTracker)
                .environmentObject(dockMiniPlayerWindowTracker)
                .environmentObject(barcodeEject)
                .onReceive(NotificationCenter.default.publisher(for: .flacNestLibraryRootDidChange)) { _ in
                    playback.configure(libraryRoot: AppSettings.libraryRootURL)
                    libraryVM.reloadFromDisk()
                }
                .onReceive(NotificationCenter.default.publisher(for: .flacNestLibraryDidLoad)) { _ in
                    playback.restoreLastPlayback(from: libraryVM.library)
                }
                .onAppear {
                    configureSharedPlayback()
                }
                .registersMetadataTransferOpener()
                .appTheme(theme)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 620)

        Window("FlacNest Dock Mini", id: "dockMiniPlayer") {
            DockMiniPlayerView()
                .environment(playback)
                .environmentObject(libraryVM)
                .environmentObject(playerWindowTracker)
                .environmentObject(dockMiniPlayerWindowTracker)
                .registersMetadataTransferOpener()
                .appTheme(theme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(DockMiniPlayerWindowSizing.savedSize(for: AppSettings.dockMiniPlayerOrientation))

        Window("Export to Mobile App", id: "prepareExport") {
            PrepareExportView()
                .environmentObject(libraryVM)
                .appTheme(theme)
        }
        .defaultSize(width: 560, height: 560)
        .commandsRemoved()

        Window("Export to Other Desktop", id: "transferMetadata") {
            MetadataTransferView()
                .environmentObject(libraryVM)
                .appTheme(theme)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("About FlacNest", id: "about") {
            AboutView()
                .appTheme(theme, showsBackdrop: false)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Settings {
            SettingsView()
                .environmentObject(libraryVM)
                .onReceive(NotificationCenter.default.publisher(for: .flacNestLibraryRootDidChange)) { _ in
                    playback.configure(libraryRoot: AppSettings.libraryRootURL)
                    libraryVM.reloadFromDisk()
                }
                .registersMetadataTransferOpener()
                .appTheme(theme)
        }

        MenuBarExtra(isInserted: $showStatusMenu) {
            StatusMenuContent()
                .environment(playback)
                .environmentObject(libraryVM)
                .registersMetadataTransferOpener()
                .appTheme(theme, showsBackdrop: false)
        } label: {
            StatusMenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }

    private func configureSharedPlayback() {
        playback.configure(libraryRoot: AppSettings.libraryRootURL)
        playback.orderedAlbumsProvider = {
            LibraryAlbumSorting.sorted(
                libraryVM.library.albums.filter { !$0.isHidden },
                by: libraryVM.sortMode
            )
        }
        playback.libraryAlbumsProvider = {
            libraryVM.library.albums
        }
        playback.restoreCachedPlaybackIfAvailable()
        libraryVM.loadFromDisk()
        MediaRemoteController.shared.configure(playback: playback)
    }
}

enum PlayerWindowSizing {
    static let minWidth: CGFloat = 380
    static let minHeight: CGFloat = 480
    static let defaultCompactSize = NSSize(width: 380, height: 480)
    static let defaultExpandedSize = NSSize(width: 380, height: 640)

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
        DockMiniPlayerWindowSizing.closeIfOpen()
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

enum DockMiniPlayerWindowSizing {
    static func isDockMiniPlayerWindow(_ window: NSWindow) -> Bool {
        window.title == "FlacNest Dock Mini" || window.identifier?.rawValue == "dockMiniPlayer"
    }

    static var isDockMiniPlayerWindowOpen: Bool {
        NSApp.windows.contains { isDockMiniPlayerWindow($0) && PlayerWindowSizing.isMainWindowShown($0) }
    }

    static func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    static func applyWindowChrome() {
        guard let window = dockMiniPlayerWindow else { return }
        configure(window)
    }

    static func applyOrientation(_ orientation: DockMiniPlayerOrientation) {
        DispatchQueue.main.async {
            guard let window = dockMiniPlayerWindow else { return }
            configure(window)
            window.minSize = orientation.minSize
            window.maxSize = NSSize(width: 2_000, height: 2_000)

            let current = window.contentLayoutRect.size
            let clamped = NSSize(
                width: max(orientation.minWidth, current.width),
                height: max(orientation.minHeight, current.height)
            )
            if current != clamped {
                window.setContentSize(clamped)
            }
        }
    }

    static func savedSize(for orientation: DockMiniPlayerOrientation) -> NSSize {
        let saved = AppSettings.dockMiniPlayerWindowFrame(for: orientation)
        let width = max(orientation.minWidth, saved.map { CGFloat($0.width) } ?? orientation.defaultWidth)
        let height = max(orientation.minHeight, saved.map { CGFloat($0.height) } ?? orientation.defaultHeight)
        return NSSize(width: width, height: height)
    }

    static func restoreSize(for orientation: DockMiniPlayerOrientation) {
        DispatchQueue.main.async {
            dockMiniPlayerWindow?.setContentSize(savedSize(for: orientation))
        }
    }

    static func saveCurrentSize(for orientation: DockMiniPlayerOrientation) {
        guard let window = dockMiniPlayerWindow else { return }
        let frame = PlayerWindowFrame(
            width: window.contentLayoutRect.width,
            height: window.contentLayoutRect.height,
            artworkSize: nil
        )
        AppSettings.setDockMiniPlayerWindowFrame(frame, for: orientation)
    }

    static func bringDockMiniToFront() {
        DockIconVisibility.prepareToShowMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        dockMiniPlayerWindow?.makeKeyAndOrderFront(nil)
    }

    static func closeIfOpen() {
        guard let window = dockMiniPlayerWindow else { return }
        window.close()
    }

    static func enterDockMiniMode(
        dismissWindow: DismissWindowAction,
        openWindow: OpenWindowAction,
        playerTracker: PlayerWindowTracker,
        dockMiniTracker: DockMiniPlayerWindowTracker
    ) {
        dismissWindow(id: "player")
        openWindow(id: "dockMiniPlayer")
        DispatchQueue.main.async {
            applyWindowChrome()
            applyOrientation(AppSettings.dockMiniPlayerOrientation)
            restoreSize(for: AppSettings.dockMiniPlayerOrientation)
            bringDockMiniToFront()
            playerTracker.refresh()
            dockMiniTracker.refresh()
            DockIconVisibility.sync()
        }
    }

    static func showFullPlayer(
        dismissWindow: DismissWindowAction,
        openWindow: OpenWindowAction,
        dockMiniTracker: DockMiniPlayerWindowTracker,
        playerTracker: PlayerWindowTracker
    ) {
        dismissWindow(id: "dockMiniPlayer")
        openWindow(id: "player")
        DispatchQueue.main.async {
            PlayerWindowSizing.bringPlayerToFront()
            dockMiniTracker.refresh()
            playerTracker.refresh()
            DockIconVisibility.sync()
        }
    }

    private static var dockMiniPlayerWindow: NSWindow? {
        NSApp.windows.first(where: isDockMiniPlayerWindow)
    }
}

@MainActor
final class DockMiniPlayerWindowTracker: ObservableObject {
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
                Task { @MainActor in
                    self?.refresh()
                }
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
        isOpen = DockMiniPlayerWindowSizing.isDockMiniPlayerWindowOpen
        DockIconVisibility.sync()
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
                Task { @MainActor in
                    self?.refresh()
                }
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
        apply(showInDock: shouldShowInDock)
    }

    private static var shouldShowInDock: Bool {
        AppSettings.showStatusMenu
            || PlayerWindowSizing.isPlayerWindowOpen
            || PlayerWindowSizing.isLibraryWindowOpen
            || DockMiniPlayerWindowSizing.isDockMiniPlayerWindowOpen
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
                Task { @MainActor in
                    self?.refresh()
                }
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

            guard PlayerWindowSizing.isPlayerWindow(window)
                || PlayerWindowSizing.isLibraryWindow(window)
                || DockMiniPlayerWindowSizing.isDockMiniPlayerWindow(window) else {
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
