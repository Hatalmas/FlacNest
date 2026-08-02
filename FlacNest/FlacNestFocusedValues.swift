import SwiftUI

private struct PlaybackControllerFocusedKey: FocusedValueKey {
    typealias Value = PlaybackController
}

private struct LibraryViewModelFocusedKey: FocusedValueKey {
    typealias Value = LibraryViewModel
}

private struct EditMetadataFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct EjectFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var focusedPlayback: PlaybackController? {
        get { self[PlaybackControllerFocusedKey.self] }
        set { self[PlaybackControllerFocusedKey.self] = newValue }
    }

    var focusedLibraryViewModel: LibraryViewModel? {
        get { self[LibraryViewModelFocusedKey.self] }
        set { self[LibraryViewModelFocusedKey.self] = newValue }
    }

    var focusedEditMetadata: (() -> Void)? {
        get { self[EditMetadataFocusedKey.self] }
        set { self[EditMetadataFocusedKey.self] = newValue }
    }

    var focusedEject: (() -> Void)? {
        get { self[EjectFocusedKey.self] }
        set { self[EjectFocusedKey.self] = newValue }
    }
}

extension View {
    func flacNestFocusedCommands(
        playback: PlaybackController,
        libraryVM: LibraryViewModel? = nil,
        onEditMetadata: (() -> Void)? = nil,
        onEject: (() -> Void)? = nil
    ) -> some View {
        focusedValue(\.focusedPlayback, playback)
            .focusedValue(\.focusedLibraryViewModel, libraryVM)
            .focusedValue(\.focusedEditMetadata, onEditMetadata)
            .focusedValue(\.focusedEject, onEject)
    }
}
