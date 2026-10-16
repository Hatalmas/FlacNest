import AppKit
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

    private static var isPlayerKeyWindow: Bool {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return window.map(PlayerWindowSizing.isPlayerWindow) == true
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About FlacNest") {
                DockIconVisibility.prepareToShowMainWindow()
                openWindow(id: "about")
            }
        }

        CommandGroup(replacing: .newItem) { }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(Self.isPlayerKeyWindow)

            Button(Self.isPlayerKeyWindow ? "Copy Playing Now Token" : "Copy") {
                copyForFrontmostWindow()
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(Self.isPlayerKeyWindow && !hasLoadedAlbum)

            Button(Self.isPlayerKeyWindow ? "Paste Playing Now Token" : "Paste") {
                pasteForFrontmostWindow()
            }
            .keyboardShortcut("v", modifiers: .command)

            Divider()

            Button("Select All") {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(Self.isPlayerKeyWindow)
        }

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

    private func copyForFrontmostWindow() {
        if Self.isPlayerKeyWindow {
            copyPlayingNowToken()
        } else {
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        }
    }

    private func pasteForFrontmostWindow() {
        if Self.isPlayerKeyWindow {
            pastePlayingNowToken()
        } else {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        }
    }

    private func copyPlayingNowToken() {
        do {
            try playback.copyPlayingNowToken()
        } catch {
            PlayingNowTokenPasteboard.presentError(error)
        }
    }

    private func pastePlayingNowToken() {
        do {
            try playback.pastePlayingNowToken()
        } catch {
            PlayingNowTokenPasteboard.presentError(error)
        }
    }
}
