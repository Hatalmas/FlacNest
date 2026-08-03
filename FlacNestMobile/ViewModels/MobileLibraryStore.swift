import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class MobileLibraryStore {
    private(set) var package: MobileLibraryPackage?
    private(set) var libraryFolderPath: String?
    private(set) var libraryFolderSource: MobileLibraryFolderSource = .default
    var selectedAlbumID: String?
    var selectedTrackID: String?
    var sortMode: LibrarySortMode = .artist
    var groupMode: PortableLibraryGroupMode = .artist
    var showFavoritesOnly = false
    var filterText = ""
    var statusMessage: String?
    var errorMessage: String?
    private(set) var isLoadingLibrary = false

    let playback = MobilePlaybackController()
    private var loadTask: Task<Void, Never>?

    init() {
        MobileNowPlayingController.shared.configure(playback: playback) { [weak self] album in
            self?.artworkURL(for: album)
        }
        playback.onTrackChanged = { [weak self] in
            self?.syncSelectionFromPlayback()
        }
    }

    private func syncSelectionFromPlayback() {
        guard let album = playback.currentAlbum else { return }
        selectedAlbumID = album.id
        if let track = playback.currentTrack {
            selectedTrackID = track.id
        }
    }

    var selectedAlbum: MobileLibraryAlbum? {
        guard let selectedAlbumID else { return nil }
        return package?.albums.first { $0.id == selectedAlbumID }
    }

    var selectedTrack: MobileLibraryTrack? {
        guard let album = selectedAlbum, let selectedTrackID else { return nil }
        return album.tracks.first { $0.id == selectedTrackID }
    }

    var displayedSections: [MobileLibraryAlbumSection] {
        guard let package else { return [] }
        let albums = showFavoritesOnly ? package.albums.filter(\.isFavorite) : package.albums
        return MobileLibrarySorting
            .sections(from: albums, sortMode: sortMode, groupMode: groupMode)
            .filtered(by: filterText)
    }

    var libraryFolderSourceLabel: String {
        switch libraryFolderSource {
        case .default:
            return "App Documents folder"
        case .custom:
            return "Custom folder"
        }
    }

    func loadLibraryIfAvailable() {
        loadTask?.cancel()
        loadTask = Task {
            await performLibraryLoad(resetSelection: false)
        }
    }

    func openExportRoot(from url: URL) {
        loadTask?.cancel()
        errorMessage = nil
        MobileLibraryStorage.setLibraryFolder(url)
        MobileArtworkImageCache.clear()
        loadTask = Task {
            await performLibraryLoad(resetSelection: true)
        }
    }

    func useDefaultLibraryFolder() {
        loadTask?.cancel()
        MobileLibraryStorage.useDefaultFolder()
        MobileArtworkImageCache.clear()
        selectedAlbumID = nil
        selectedTrackID = nil
        playback.stop()
        loadTask = Task {
            await performLibraryLoad(resetSelection: true)
        }
    }

    private func performLibraryLoad(resetSelection: Bool) async {
        refreshFolderMetadata()
        isLoadingLibrary = true
        errorMessage = nil

        let exportRoot = MobileLibraryStorage.resolveExportRootURL()

        let loadResult: Result<MobileLibraryPackage?, Error> = await Task.detached(priority: .userInitiated) {
            guard let root = exportRoot else {
                return .success(nil)
            }
            do {
                return .success(try FlacNestMobileLibraryLoader.load(from: root))
            } catch {
                return .failure(error)
            }
        }.value

        guard !Task.isCancelled else { return }

        isLoadingLibrary = false
        applyLoadedPackage(loadResult, resetSelection: resetSelection)
    }

    private func applyLoadedPackage(_ result: Result<MobileLibraryPackage?, Error>, resetSelection: Bool) {
        switch result {
        case .success(let loaded):
            package = loaded
            if let loaded {
                playback.configure(exportRoot: loaded.rootURL)
                if resetSelection || selectedAlbumID == nil {
                    selectedAlbumID = loaded.albums.first?.id
                    selectedTrackID = loaded.albums.first?.tracks.first?.id
                }
                statusMessage = "Loaded \(loaded.albums.count) albums from \(loaded.displayName)."
            } else {
                if resetSelection {
                    package = nil
                    playback.stop()
                }
                statusMessage = "Copy an export folder to Documents or choose a library folder in Settings."
            }
            errorMessage = nil
        case .failure(let error):
            if resetSelection {
                package = nil
                playback.stop()
            }
            errorMessage = error.localizedDescription
        }
    }

    func selectAlbum(_ album: MobileLibraryAlbum) {
        selectedAlbumID = album.id
        if selectedTrackID == nil || !album.tracks.contains(where: { $0.id == selectedTrackID }) {
            selectedTrackID = album.tracks.first?.id
        }
    }

    func selectTrack(_ track: MobileLibraryTrack, in album: MobileLibraryAlbum) {
        selectAlbum(album)
        selectedTrackID = track.id
    }

    func artworkURL(for album: MobileLibraryAlbum) -> URL? {
        package?.artworkURL(for: album)
    }

    func playSelectedTrack() {
        guard let album = selectedAlbum else { return }
        let trackIndex = album.tracks.firstIndex { $0.id == selectedTrackID } ?? 0
        playback.load(album: album, trackIndex: trackIndex, autoPlay: true)
    }

    func openAlbum(_ album: MobileLibraryAlbum, startPlayback: Bool = true) {
        selectAlbum(album)
        if startPlayback {
            playSelectedTrack()
        }
    }

    func playTrack(_ track: MobileLibraryTrack, in album: MobileLibraryAlbum) {
        selectTrack(track, in: album)
        let trackIndex = album.tracks.firstIndex { $0.id == track.id } ?? 0
        if playback.currentAlbum?.id == album.id {
            playback.playTrack(at: trackIndex)
        } else {
            playback.load(album: album, trackIndex: trackIndex, autoPlay: true)
        }
    }

    private func refreshFolderMetadata() {
        libraryFolderPath = MobileLibraryStorage.configuredFolderPath()
        libraryFolderSource = MobileLibraryStorage.configuredFolderSource()
    }
}
