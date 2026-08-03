import MediaPlayer
import UIKit

@MainActor
final class MobileNowPlayingController {
    static let shared = MobileNowPlayingController()

    private weak var playback: MobilePlaybackController?
    private var artworkURLProvider: ((MobileLibraryAlbum) -> URL?)?
    private var commandsConfigured = false
    private var lastNowPlayingRefresh = Date.distantPast
    private var lastElapsedSecond = -1
    private var lastPlaybackStateKey = ""
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkAlbumID: String?
    private var artworkLoadTask: Task<Void, Never>?

    private init() {}

    func configure(
        playback: MobilePlaybackController,
        artworkURL: @escaping (MobileLibraryAlbum) -> URL?
    ) {
        self.playback = playback
        artworkURLProvider = artworkURL
        configureRemoteCommandsIfNeeded()
        refresh(from: playback, force: true)
    }

    func refresh(from playback: MobilePlaybackController, force: Bool = false) {
        self.playback = playback

        let elapsedSecond = Int(playback.currentTime.rounded(.down))
        let playbackStateKey = "\(playback.currentAlbum?.id ?? "")|\(playback.currentTrackIndex)|\(playback.isPlaying)"
        let shouldRefreshNowPlaying = force
            || playbackStateKey != lastPlaybackStateKey
            || !playback.isPlaying
            || elapsedSecond != lastElapsedSecond
            || Date().timeIntervalSince(lastNowPlayingRefresh) >= 1

        guard shouldRefreshNowPlaying else { return }

        if force || playbackStateKey != lastPlaybackStateKey {
            if let album = playback.currentAlbum {
                updateArtworkIfNeeded(for: album)
            } else {
                clearArtworkCache()
            }
        }

        lastPlaybackStateKey = playbackStateKey
        lastElapsedSecond = elapsedSecond
        lastNowPlayingRefresh = Date()
        updateNowPlayingInfo(from: playback)
    }

    func clear() {
        artworkLoadTask?.cancel()
        clearArtworkCache()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        lastPlaybackStateKey = ""
        lastElapsedSecond = -1
    }

    private func clearArtworkCache() {
        cachedArtwork = nil
        cachedArtworkAlbumID = nil
    }

    private func updateArtworkIfNeeded(for album: MobileLibraryAlbum) {
        guard cachedArtworkAlbumID != album.id else { return }

        cachedArtworkAlbumID = album.id
        cachedArtwork = nil
        artworkLoadTask?.cancel()

        guard let url = artworkURLProvider?(album) else { return }

        let albumID = album.id
        artworkLoadTask = Task {
            let image = await Task.detached(priority: .utility) {
                MobileArtworkImageCache.image(for: url, maxPixelSize: 600)
            }.value

            guard !Task.isCancelled else { return }
            guard cachedArtworkAlbumID == albumID, let image else { return }

            cachedArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

            guard let playback = self.playback, playback.currentAlbum?.id == albumID else { return }
            updateNowPlayingInfo(from: playback)
        }
    }

    private func configureRemoteCommandsIfNeeded() {
        guard !commandsConfigured else { return }
        commandsConfigured = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.performRemoteCommand { $0.handlePlay() } ?? .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.performRemoteCommand { $0.handlePause() } ?? .commandFailed
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.performRemoteCommand { $0.handleTogglePlayPause() } ?? .commandFailed
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.performRemoteCommand { $0.handleNextTrack() } ?? .commandFailed
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.performRemoteCommand { $0.handlePreviousTrack() } ?? .commandFailed
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.performRemoteCommand { $0.handleStop() } ?? .commandFailed
        }
    }

    private nonisolated func performRemoteCommand(
        _ action: @MainActor (MobileNowPlayingController) -> MPRemoteCommandHandlerStatus
    ) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                action(self)
            }
        }

        var result: MPRemoteCommandHandlerStatus = .commandFailed
        DispatchQueue.main.sync {
            result = MainActor.assumeIsolated {
                action(self)
            }
        }
        return result
    }

    private func handlePlay() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.play()
        refresh(from: playback, force: true)
        return .success
    }

    private func handlePause() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.pause()
        refresh(from: playback, force: true)
        return .success
    }

    private func handleTogglePlayPause() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.togglePlayPause()
        refresh(from: playback, force: true)
        return .success
    }

    private func handleNextTrack() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.nextTrack()
        refresh(from: playback, force: true)
        return .success
    }

    private func handlePreviousTrack() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.previousTrack()
        refresh(from: playback, force: true)
        return .success
    }

    private func handleStop() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.stop()
        clear()
        return .success
    }

    private func updateNowPlayingInfo(from playback: MobilePlaybackController) {
        let center = MPRemoteCommandCenter.shared()
        let hasAlbum = playback.currentAlbum != nil

        center.playCommand.isEnabled = hasAlbum && !playback.isPlaying && !playback.isLoadingAudio
        center.pauseCommand.isEnabled = hasAlbum && playback.isPlaying
        center.togglePlayPauseCommand.isEnabled = hasAlbum && !playback.isLoadingAudio
        center.nextTrackCommand.isEnabled = hasAlbum && !playback.isLoadingAudio
        center.previousTrackCommand.isEnabled = hasAlbum && !playback.isLoadingAudio
        center.stopCommand.isEnabled = hasAlbum

        guard hasAlbum, let album = playback.currentAlbum, let track = playback.currentTrack else {
            clear()
            return
        }

        let performer = track.performer?.isEmpty == false ? track.performer! : album.performer
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: performer,
            MPMediaItemPropertyAlbumTitle: album.displayTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playback.trackElapsed,
            MPMediaItemPropertyPlaybackDuration: playback.trackDuration,
            MPNowPlayingInfoPropertyPlaybackRate: playback.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]

        if let cachedArtwork {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
