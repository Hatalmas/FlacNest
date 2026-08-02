import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var currentAlbum: LibraryAlbum?
    @Published private(set) var currentTrackIndex: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var fileDuration: Double = 0
    @Published var lastError: String?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var displayLinkTimer: Timer?
    private var segmentStartSeconds: Double = 0
    private var segmentEndSeconds: Double = 0
    private var scheduledSegmentID = 0
    private var libraryRoot: URL?
    private var hasAttemptedRestore = false
    private var lastResumeSave = Date.distantPast

    init() {
        engine.attach(playerNode)
    }

    func configure(libraryRoot: URL?) {
        self.libraryRoot = libraryRoot
    }

    var currentTrack: LibraryTrack? {
        guard let album = currentAlbum, album.tracks.indices.contains(currentTrackIndex) else { return nil }
        return album.tracks[currentTrackIndex]
    }

    var trackDuration: Double {
        guard let track = currentTrack else { return 0 }
        let end = endTimeForTrack(at: currentTrackIndex)
        return max(0, end - track.startSeconds)
    }

    var trackElapsed: Double {
        guard let track = currentTrack else { return 0 }
        return max(0, min(trackDuration, currentTime - track.startSeconds))
    }

    var trackProgress: Double {
        guard trackDuration > 0 else { return 0 }
        return min(1, max(0, trackElapsed / trackDuration))
    }

    var albumDuration: Double {
        guard let album = currentAlbum, !album.tracks.isEmpty else { return fileDuration }
        return endTimeForTrack(at: album.tracks.count - 1)
    }

    var albumProgress: Double {
        guard albumDuration > 0 else { return 0 }
        return min(1, max(0, currentTime / albumDuration))
    }

    func load(album: LibraryAlbum, trackIndex: Int = 0, seekTo seconds: Double? = nil) {
        saveResumeStateIfNeeded()
        stopInternal(saveState: false)

        currentAlbum = album
        currentTrackIndex = min(max(0, trackIndex), max(0, album.tracks.count - 1))
        lastError = nil

        guard let root = libraryRoot else {
            lastError = "Library folder is not set."
            currentAlbum = nil
            return
        }

        let flacURL = root.appendingPathComponent(album.flacRelativePath)
        guard FileManager.default.fileExists(atPath: flacURL.path) else {
            lastError = "Could not open FLAC: file not found."
            currentAlbum = nil
            audioFile = nil
            return
        }

        do {
            let file = try AVAudioFile(forReading: flacURL)
            audioFile = file
            fileDuration = Double(file.length) / file.fileFormat.sampleRate
            connectAndPrepare(file: file)

            let targetTime: Double
            if let seconds {
                targetTime = seconds
            } else if let track = currentTrack {
                targetTime = track.startSeconds
            } else {
                targetTime = 0
            }

            currentTrackIndex = indexForAbsoluteTime(targetTime)
            setPlaybackPosition(targetTime)
        } catch {
            lastError = "Could not open FLAC: \(error.localizedDescription)"
            currentAlbum = nil
            audioFile = nil
        }

        saveResumeStateIfNeeded()
        MediaRemoteController.shared.refresh(from: self)
    }

    func restoreLastPlayback(from library: FlacNestLibrary) {
        guard !hasAttemptedRestore else { return }
        hasAttemptedRestore = true

        guard AppSettings.saveLastPlayedPosition,
              let state = AppSettings.lastPlaybackState else {
            return
        }

        guard let album = library.albums.first(where: { $0.id == state.albumID }) else {
            AppSettings.lastPlaybackState = nil
            return
        }

        guard album.flacRelativePath == state.flacRelativePath,
              let root = libraryRoot else {
            AppSettings.lastPlaybackState = nil
            return
        }

        let flacURL = root.appendingPathComponent(state.flacRelativePath)
        guard FileManager.default.fileExists(atPath: flacURL.path) else {
            AppSettings.lastPlaybackState = nil
            return
        }

        load(
            album: album,
            trackIndex: state.trackIndex,
            seekTo: state.positionSeconds
        )
    }

    func saveResumeStateIfNeeded() {
        guard AppSettings.saveLastPlayedPosition else { return }
        guard let album = currentAlbum, audioFile != nil else { return }

        AppSettings.lastPlaybackState = LastPlaybackState(
            albumID: album.id,
            flacRelativePath: album.flacRelativePath,
            trackIndex: currentTrackIndex,
            positionSeconds: currentTime
        )
        lastResumeSave = Date()
    }

    func updateAlbumMetadataIfPlaying(_ album: LibraryAlbum) {
        guard currentAlbum?.id == album.id else { return }
        currentAlbum = album
    }

    func play(fromTrackStart: Bool = false) {
        guard audioFile != nil, let track = currentTrack else { return }

        if playerNode.isPlaying && !fromTrackStart {
            isPlaying = true
            startPositionTimer()
            return
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                lastError = error.localizedDescription
                return
            }
        }

        let trackEnd = endTimeForTrack(at: currentTrackIndex)
        let start: Double
        if !fromTrackStart,
           currentTime >= track.startSeconds && currentTime < trackEnd - 0.05 {
            start = currentTime
        } else {
            start = track.startSeconds
        }

        scheduleSegment(from: start, to: trackEnd)
        playerNode.play()
        isPlaying = true
        startPositionTimer()
        MediaRemoteController.shared.refresh(from: self)
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopPositionTimer()
        saveResumeStateIfNeeded()
        MediaRemoteController.shared.refresh(from: self)
    }

    func togglePlayPause() {
        guard currentAlbum != nil else { return }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        stopInternal(saveState: true)
    }

    func playTrack(at index: Int) {
        guard let album = currentAlbum, album.tracks.indices.contains(index) else { return }

        if audioFile == nil {
            load(album: album, trackIndex: index)
        } else {
            cancelScheduledSegments()
            currentTrackIndex = index
            setPlaybackPosition(album.tracks[index].startSeconds)
        }
        play(fromTrackStart: true)
    }

    func nextTrack() {
        guard let album = currentAlbum else { return }
        guard currentTrackIndex + 1 < album.tracks.count else { return }
        currentTrackIndex += 1
        if isPlaying {
            play(fromTrackStart: true)
        } else {
            setPlaybackPosition(currentTrack?.startSeconds ?? 0)
            saveResumeStateIfNeeded()
        }
    }

    func previousTrack() {
        guard currentAlbum != nil else { return }
        if currentTime - (currentTrack?.startSeconds ?? 0) > 3, let track = currentTrack {
            if isPlaying {
                play(fromTrackStart: true)
            } else {
                setPlaybackPosition(track.startSeconds)
                saveResumeStateIfNeeded()
            }
            return
        }
        guard currentTrackIndex > 0 else { return }
        currentTrackIndex -= 1
        if isPlaying {
            play(fromTrackStart: true)
        } else {
            setPlaybackPosition(currentTrack?.startSeconds ?? 0)
            saveResumeStateIfNeeded()
        }
    }

    func seekToTrackProgress(_ fraction: Double) {
        guard let track = currentTrack, trackDuration > 0 else { return }
        let target = track.startSeconds + trackDuration * fraction.clamped(to: 0...1)
        seekToAbsoluteTime(target)
    }

    func seekToAlbumProgress(_ fraction: Double) {
        guard albumDuration > 0 else { return }
        let target = albumDuration * fraction.clamped(to: 0...1)
        seekToAbsoluteTime(target)
    }

    private func seekToAbsoluteTime(_ seconds: Double) {
        let wasPlaying = isPlaying
        cancelScheduledSegments()
        currentTrackIndex = indexForAbsoluteTime(seconds)
        setPlaybackPosition(seconds)
        if wasPlaying {
            play(fromTrackStart: false)
        } else {
            saveResumeStateIfNeeded()
        }
    }

    private func indexForAbsoluteTime(_ absoluteTime: Double) -> Int {
        guard let album = currentAlbum, !album.tracks.isEmpty else { return 0 }
        if let index = album.tracks.lastIndex(where: { $0.startSeconds <= absoluteTime + 0.001 }) {
            return index
        }
        return 0
    }

    private func setPlaybackPosition(_ seconds: Double) {
        let clamped = max(0, min(seconds, fileDuration))
        currentTime = clamped
        segmentStartSeconds = clamped
        segmentEndSeconds = endTimeForTrack(at: currentTrackIndex)
    }

    private func endTimeForTrack(at index: Int) -> Double {
        guard let album = currentAlbum, album.tracks.indices.contains(index) else { return fileDuration }
        let track = album.tracks[index]
        if let end = track.endSeconds, end > track.startSeconds {
            return min(end, fileDuration)
        }
        return fileDuration
    }

    private func connectAndPrepare(file: AVAudioFile) {
        cancelScheduledSegments()
        engine.stop()
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
        playerNode.stop()
    }

    private func scheduleSegment(from startSeconds: Double, to endSeconds: Double) {
        guard let file = audioFile else { return }

        cancelScheduledSegments()

        let sampleRate = file.fileFormat.sampleRate
        let startFrame = max(0, min(AVAudioFramePosition(startSeconds * sampleRate), file.length - 1))
        let resolvedEndSeconds = max(startSeconds + 0.001, min(endSeconds, fileDuration))
        let endFrame = max(
            startFrame + 1,
            min(AVAudioFramePosition(resolvedEndSeconds * sampleRate), file.length)
        )

        let frameCount = endFrame - startFrame
        guard frameCount > 0 else { return }

        let segmentID = scheduledSegmentID

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(frameCount),
            at: nil
        ) { [weak self] in
            Task { @MainActor in
                self?.handleSegmentFinished(segmentID: segmentID)
            }
        }

        segmentStartSeconds = Double(startFrame) / sampleRate
        segmentEndSeconds = Double(endFrame) / sampleRate
        currentTime = segmentStartSeconds
    }

    private func cancelScheduledSegments() {
        scheduledSegmentID += 1
        playerNode.stop()
        playerNode.reset()
    }

    private func handleSegmentFinished(segmentID: Int) {
        guard segmentID == scheduledSegmentID else { return }
        guard isPlaying else { return }
        scheduledSegmentID += 1

        if currentTrackIndex + 1 < (currentAlbum?.tracks.count ?? 0) {
            currentTrackIndex += 1
            play(fromTrackStart: true)
        } else {
            isPlaying = false
            stopPositionTimer()
            currentTime = segmentEndSeconds
            saveResumeStateIfNeeded()
        }
    }

    private func stopInternal(saveState: Bool) {
        cancelScheduledSegments()
        engine.stop()
        isPlaying = false
        stopPositionTimer()
        currentTime = 0
        segmentStartSeconds = 0
        segmentEndSeconds = 0
        if saveState {
            saveResumeStateIfNeeded()
        }
        MediaRemoteController.shared.refresh(from: self)
    }

    private func startPositionTimer() {
        stopPositionTimer()
        displayLinkTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickPosition()
            }
        }
    }

    private func stopPositionTimer() {
        displayLinkTimer?.invalidate()
        displayLinkTimer = nil
    }

    private func tickPosition() {
        guard isPlaying else { return }

        if !playerNode.isPlaying {
            if currentTime >= segmentEndSeconds - 0.1 {
                handleSegmentFinished(segmentID: scheduledSegmentID)
            }
            return
        }

        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleTime >= 0,
              let file = audioFile else { return }

        let sampleRate = file.fileFormat.sampleRate
        let seconds = segmentStartSeconds + Double(playerTime.sampleTime) / sampleRate

        guard seconds >= segmentStartSeconds - 0.05, seconds <= segmentEndSeconds + 0.1 else {
            return
        }

        currentTime = min(seconds, segmentEndSeconds)

        if Date().timeIntervalSince(lastResumeSave) >= 5 {
            saveResumeStateIfNeeded()
        }

        MediaRemoteController.shared.refresh(from: self)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
