import SwiftUI

struct FlacNestCommands: Commands {
    var playback: PlaybackController
    @ObservedObject var barcodeEject: BarcodeEjectController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusedValue(\.focusedLibraryViewModel) private var libraryVM
    @FocusedValue(\.focusedEditMetadata) private var editMetadata

    private var hasLoadedAlbum: Bool {
        playback.currentAlbum != nil
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandMenu("Playback") {
            Button("Play / Pause") {
                playback.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!hasLoadedAlbum)

            Button("Stop") {
                playback.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!hasLoadedAlbum)

            Divider()

            Button("Next Track") {
                playback.nextTrack()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!hasLoadedAlbum)

            Button("Previous Track") {
                playback.previousTrack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!hasLoadedAlbum)

            Divider()

            Button("Eject — Scan Barcode") {
                barcodeEject.presentEject()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandMenu("Library") {
            Button("Play Selected Album") {
                guard let libraryVM, let album = libraryVM.selectedAlbum else { return }
                playback.load(album: album)
                playback.play()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(
                libraryVM?.selectedAlbum == nil
                    || libraryVM?.isLibraryBusy == true
                    || barcodeEject.isPresenting
            )

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

            Button("Refresh Subfolder…") {
                libraryVM?.scanSubfolder()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(libraryVM?.isLibraryBusy == true || AppSettings.libraryRootURL == nil)

            Button("Re-read Metadata…") {
                libraryVM?.rereadMetadata()
            }
            .disabled(libraryVM?.isLibraryBusy == true || AppSettings.libraryRootURL == nil)

            Button("Cancel Scan") {
                libraryVM?.cancelScan()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(libraryVM?.isScanning != true)

            Divider()

            Button("Export to Mobile App…") {
                openWindow(id: "prepareExport")
            }
            .disabled(libraryVM?.library.albums.isEmpty == true || libraryVM?.isLibraryBusy == true)

            Button("Export to Other Desktop…") {
                openWindow(id: "transferMetadata")
            }
            .disabled(libraryVM?.isLibraryBusy == true)
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
