import SwiftUI

struct FlacNestCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.focusedPlayback) private var playback
    @FocusedValue(\.focusedLibraryViewModel) private var libraryVM
    @FocusedValue(\.focusedEditMetadata) private var editMetadata

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
        }

        CommandMenu("Library") {
            Button("Play Selected Album") {
                guard let libraryVM, let album = libraryVM.selectedAlbum else { return }
                playback?.load(album: album)
                playback?.play()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(libraryVM?.selectedAlbum == nil || libraryVM?.isScanning == true)

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
            .disabled(libraryVM?.isScanning == true)

            Button("Cancel Scan") {
                libraryVM?.cancelScan()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(libraryVM?.isScanning != true)
        }

        CommandGroup(after: .windowArrangement) {
            Button("FlacNest Player") {
                openWindow(id: "player")
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("FlacNest Library") {
                openWindow(id: "library")
            }
            .keyboardShortcut("2", modifiers: .command)
        }
    }
}
