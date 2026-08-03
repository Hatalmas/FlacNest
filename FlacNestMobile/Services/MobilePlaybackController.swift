import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class MobilePlaybackController {
    private(set) var currentAlbum: MobileLibraryAlbum?
    private(set) var currentTrackIndex: Int = 0
    private(set) var isPlaying = false
    private(set) var isLoadingAudio = false
    private(set) var currentTime: Double = 0
    private(set) var fileDuration: Double = 0
    var lastError: String?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var displayLinkTimer: Timer?
    private var segmentStartSeconds: Double = 0
    private var segmentEndSeconds: Double = 0
    private var scheduledSegmentID = 0
    private var exportRoot: URL?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var shouldAutoPlayAfterLoad = false

    var onTrackChanged: (() -> Void)?

    init() {
        engine.attach(playerNode)
        configureAudioSession()
    }

    func configure(exportRoot: URL?) {
        self.exportRoot = exportRoot
    }

    var currentTrack: MobileLibraryTrack? {
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

    func load(
        album: MobileLibraryAlbum,
        trackIndex: Int = 0,
        seekTo seconds: Double? = nil,
        autoPlay: Bool = false
    ) {
        loadTask?.cancel()
        shouldAutoPlayAfterLoad = autoPlay
        stopInternal(clearNowPlaying: false)
        unloadAudioFile()

        currentAlbum = album
        currentTrackIndex = min(max(0, trackIndex), max(0, album.tracks.count - 1))
        notifyTrackChanged()
        lastError = nil
        refreshNowPlaying(force: true)

        guard let root = exportRoot else {
            isLoadingAudio = false
            lastError = "Export folder is not available."
            currentAlbum = nil
            return
        }

        let mp3URL = root.appendingPathComponent(album.mp3RelativePath)
        let resolvedTrackIndex = currentTrackIndex
        let seekSeconds = seconds
        loadGeneration += 1
        let generation = loadGeneration
        isLoadingAudio = true

        loadTask = Task {
            let openResult: Result<AVAudioFile, Error> = await Task.detached(priority: .userInitiated) {
                guard FileManager.default.fileExists(atPath: mp3URL.path) else {
                    return .failure(MobilePlaybackLoadError.fileNotFound)
                }
                do {
                    return .success(try AVAudioFile(forReading: mp3URL))
                } catch {
                    return .failure(error)
                }
            }.value

            guard !Task.isCancelled, generation == loadGeneration else { return }

            isLoadingAudio = false

            switch openResult {
            case .success(let file):
                audioFile = file
                fileDuration = Double(file.length) / file.fileFormat.sampleRate
                connectAndPrepare(file: file)

                let targetTime: Double
                if let seekSeconds {
                    targetTime = seekSeconds
                } else if album.tracks.indices.contains(resolvedTrackIndex) {
                    targetTime = album.tracks[resolvedTrackIndex].startSeconds
                } else {
                    targetTime = 0
                }

                assignTrackIndex(indexForAbsoluteTime(targetTime))
                setPlaybackPosition(targetTime)
                refreshNowPlaying(force: true)

                if shouldAutoPlayAfterLoad {
                    shouldAutoPlayAfterLoad = false
                    play(fromTrackStart: true)
                }
            case .failure(let error):
                shouldAutoPlayAfterLoad = false
                lastError = loadErrorMessage(for: error)
                currentAlbum = nil
                audioFile = nil
            }
        }
    }

    func play(fromTrackStart: Bool = false) {
        guard !isLoadingAudio, audioFile != nil, let track = currentTrack else { return }

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
        refreshNowPlaying(force: true)
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopPositionTimer()
        refreshNowPlaying(force: true)
    }

    func togglePlayPause() {
        guard currentAlbum != nil, !isLoadingAudio else { return }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        stopInternal()
    }

    func playTrack(at index: Int) {
        guard let album = currentAlbum, album.tracks.indices.contains(index) else { return }

        if audioFile == nil || isLoadingAudio {
            load(album: album, trackIndex: index, autoPlay: true)
            return
        }

        cancelScheduledSegments()
        assignTrackIndex(index)
        setPlaybackPosition(album.tracks[index].startSeconds)
        play(fromTrackStart: true)
    }

    func nextTrack() {
        guard let album = currentAlbum else { return }
        guard currentTrackIndex + 1 < album.tracks.count else { return }
        assignTrackIndex(currentTrackIndex + 1)
        if isPlaying {
            play(fromTrackStart: true)
        } else {
            setPlaybackPosition(currentTrack?.startSeconds ?? 0)
            refreshNowPlaying(force: true)
        }
    }

    func previousTrack() {
        guard currentAlbum != nil else { return }
        if currentTime - (currentTrack?.startSeconds ?? 0) > 3, let track = currentTrack {
            if isPlaying {
                play(fromTrackStart: true)
            } else {
                setPlaybackPosition(track.startSeconds)
                refreshNowPlaying(force: true)
            }
            return
        }
        guard currentTrackIndex > 0 else { return }
        assignTrackIndex(currentTrackIndex - 1)
        if isPlaying {
            play(fromTrackStart: true)
        } else {
            setPlaybackPosition(currentTrack?.startSeconds ?? 0)
            refreshNowPlaying(force: true)
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
        guard currentAlbum != nil else { return }
        let wasPlaying = isPlaying
        cancelScheduledSegments()
        assignTrackIndex(indexForAbsoluteTime(seconds))
        setPlaybackPosition(seconds)
        if wasPlaying {
            play(fromTrackStart: false)
        }
        refreshNowPlaying(force: true)
    }

    private func assignTrackIndex(_ index: Int) {
        currentTrackIndex = index
        notifyTrackChanged()
    }

    private func notifyTrackChanged() {
        onTrackChanged?()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            lastError = error.localizedDescription
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
            assignTrackIndex(currentTrackIndex + 1)
            play(fromTrackStart: true)
        } else {
            isPlaying = false
            stopPositionTimer()
            currentTime = segmentEndSeconds
            refreshNowPlaying(force: true)
        }
    }

    private func stopInternal(clearNowPlaying: Bool = true) {
        loadTask?.cancel()
        shouldAutoPlayAfterLoad = false
        isLoadingAudio = false
        cancelScheduledSegments()
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        isPlaying = false
        stopPositionTimer()
        if clearNowPlaying {
            MobileNowPlayingController.shared.clear()
        }
    }

    private func unloadAudioFile() {
        audioFile = nil
        fileDuration = 0
        currentTime = 0
    }

    private func startPositionTimer() {
        stopPositionTimer()
        displayLinkTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTimeFromNode()
            }
        }
    }

    private func stopPositionTimer() {
        displayLinkTimer?.invalidate()
        displayLinkTimer = nil
    }

    private func updateCurrentTimeFromNode() {
        guard isPlaying, let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return
        }

        let sampleRate = audioFile?.fileFormat.sampleRate ?? 44_100
        let elapsed = Double(playerTime.sampleTime) / sampleRate
        currentTime = min(segmentStartSeconds + elapsed, segmentEndSeconds)
        refreshNowPlaying()
    }

    private func refreshNowPlaying(force: Bool = false) {
        MobileNowPlayingController.shared.refresh(from: self, force: force)
    }

    private func loadErrorMessage(for error: Error) -> String {
        if error is MobilePlaybackLoadError {
            return "Could not open MP3: file not found."
        }
        return "Could not open MP3: \(error.localizedDescription)"
    }
}

private enum MobilePlaybackLoadError: Error {
    case fileNotFound
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
