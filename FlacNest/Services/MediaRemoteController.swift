import AppKit
import MediaPlayer

@MainActor
final class MediaRemoteController {
    static let shared = MediaRemoteController()

    private weak var playback: PlaybackController?
    private var commandsConfigured = false
    private var lastNowPlayingRefresh = Date.distantPast
    private var lastElapsedSecond = -1
    private var lastPlaybackStateKey = ""

    private init() {}

    func configure(playback: PlaybackController) {
        self.playback = playback
        configureRemoteCommandsIfNeeded()
        refresh(from: playback, force: true)
    }

    func refresh(from playback: PlaybackController, force: Bool = false) {
        self.playback = playback

        let elapsedSecond = Int(playback.currentTime.rounded(.down))
        let playbackStateKey = "\(playback.currentAlbum?.id ?? "")|\(playback.currentTrackIndex)|\(playback.isPlaying)"
        let shouldRefreshNowPlaying = force
            || playbackStateKey != lastPlaybackStateKey
            || !playback.isPlaying
            || elapsedSecond != lastElapsedSecond
            || Date().timeIntervalSince(lastNowPlayingRefresh) >= 1

        guard shouldRefreshNowPlaying else { return }

        lastPlaybackStateKey = playbackStateKey
        lastElapsedSecond = elapsedSecond
        lastNowPlayingRefresh = Date()
        updateNowPlayingInfo(from: playback)
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
        _ action: @MainActor (MediaRemoteController) -> MPRemoteCommandHandlerStatus
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
        refresh(from: playback)
        return .success
    }

    private func handlePause() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.pause()
        refresh(from: playback)
        return .success
    }

    private func handleTogglePlayPause() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.togglePlayPause()
        refresh(from: playback)
        return .success
    }

    private func handleNextTrack() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.nextTrack()
        refresh(from: playback)
        return .success
    }

    private func handlePreviousTrack() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.previousTrack()
        refresh(from: playback)
        return .success
    }

    private func handleStop() -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.currentAlbum != nil else { return .commandFailed }
        playback.stop()
        refresh(from: playback)
        return .success
    }

    private func updateNowPlayingInfo(from playback: PlaybackController) {
        let center = MPRemoteCommandCenter.shared()
        let hasAlbum = playback.currentAlbum != nil

        center.playCommand.isEnabled = hasAlbum
        center.pauseCommand.isEnabled = hasAlbum
        center.togglePlayPauseCommand.isEnabled = hasAlbum
        center.nextTrackCommand.isEnabled = hasAlbum
        center.previousTrackCommand.isEnabled = hasAlbum
        center.stopCommand.isEnabled = hasAlbum

        guard hasAlbum, let album = playback.currentAlbum, let track = playback.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let performer = album.displayedArtist(for: track)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: performer,
            MPMediaItemPropertyAlbumArtist: album.displayArtist,
            MPMediaItemPropertyAlbumTitle: album.displayTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playback.currentTime,
            MPMediaItemPropertyPlaybackDuration: playback.trackDuration,
            MPNowPlayingInfoPropertyPlaybackRate: playback.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }
}
