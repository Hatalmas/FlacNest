import SwiftUI

struct FlacNestCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusedValue(\.focusedPlayback) private var playback
    @FocusedValue(\.focusedLibraryViewModel) private var libraryVM
    @FocusedValue(\.focusedEditMetadata) private var editMetadata
    @FocusedValue(\.focusedEject) private var eject

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandMenu("Playback") {
            Button("Play / Pause") {
                playback?.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(playback?.currentAlbum == nil)

            Button("Stop") {
                playback?.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(playback?.currentAlbum == nil)

            Divider()

            Button("Next Track") {
                playback?.nextTrack()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(playback?.currentAlbum == nil)

            Button("Previous Track") {
                playback?.previousTrack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(playback?.currentAlbum == nil)

            Divider()

            Button("Eject — Scan Barcode") {
                eject?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(eject == nil)
        }

        CommandMenu("Library") {
            Button("Play Selected Album") {
                guard let libraryVM, let album = libraryVM.selectedAlbum else { return }
                playback?.load(album: album)
                playback?.play()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(libraryVM?.selectedAlbum == nil || libraryVM?.isLibraryBusy == true)

            Button("Edit Metadata…") {
                editMetadata?()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(libraryVM?.selectedAlbum == nil || editMetadata == nil)

            Divider()

            Button("Refresh Library") {
                libraryVM?.refreshLibrary()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(libraryVM?.isLibraryBusy == true)

            Button("Cancel Scan") {
                libraryVM?.cancelScan()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(libraryVM?.isScanning != true)

            Divider()

            Button("Prepare Export…") {
                openWindow(id: "prepareExport")
            }
            .disabled(libraryVM?.library.albums.isEmpty == true || libraryVM?.isLibraryBusy == true)
        }

        CommandGroup(after: .windowArrangement) {
            Button("FlacNest Player") {
                DockIconVisibility.prepareToShowMainWindow()
                openWindow(id: "player")
                DispatchQueue.main.async {
                    PlayerWindowSizing.bringPlayerToFront()
                }
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("FlacNest Library") {
                PlayerWindowSizing.toggleLibrary(
                    openWindow: openWindow,
                    dismissWindow: dismissWindow
                )
            }
            .keyboardShortcut("2", modifiers: .command)
        }
    }
}
