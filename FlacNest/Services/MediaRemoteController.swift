import AppKit
import MediaPlayer

@MainActor
final class MediaRemoteController {
    static let shared = MediaRemoteController()

    private weak var playback: PlaybackController?
    private var commandsConfigured = false
    private var mediaKeyMonitor: Any?

    private init() {}

    func configure(playback: PlaybackController) {
        self.playback = playback
        configureRemoteCommandsIfNeeded()
        startMediaKeyMonitorIfNeeded()
        refresh(from: playback)
    }

    func refresh(from playback: PlaybackController) {
        self.playback = playback
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

    private func startMediaKeyMonitorIfNeeded() {
        guard mediaKeyMonitor == nil else { return }

        mediaKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self else { return event }
            guard event.subtype.rawValue == 8 else { return event }

            let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
            let keyFlags = event.data1 & 0x0000FFFF
            let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
            guard isKeyDown else { return event }

            guard self.handlePhysicalMediaKey(keyCode) else { return event }
            return nil
        }
    }

    @discardableResult
    private func handlePhysicalMediaKey(_ keyCode: Int) -> Bool {
        switch keyCode {
        case MediaKeyCode.play:
            return handleTogglePlayPause() == .success
        case MediaKeyCode.next:
            return handleNextTrack() == .success
        case MediaKeyCode.previous:
            return handlePreviousTrack() == .success
        case MediaKeyCode.fastForward:
            return handleNextTrack() == .success
        case MediaKeyCode.rewind:
            return handlePreviousTrack() == .success
        default:
            return false
        }
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

        let performer = track.performer?.isEmpty == false ? track.performer! : album.performer
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: performer,
            MPMediaItemPropertyAlbumTitle: album.displayTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playback.currentTime,
            MPMediaItemPropertyPlaybackDuration: playback.trackDuration,
            MPNowPlayingInfoPropertyPlaybackRate: playback.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }
}

private enum MediaKeyCode {
    static let play = 16
    static let next = 17
    static let previous = 18
    static let fastForward = 19
    static let rewind = 20
}
