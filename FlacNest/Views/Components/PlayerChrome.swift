import AppKit
import Combine
import SwiftUI

extension Image {
    func highQualityScaled(contentMode: ContentMode = .fill) -> some View {
        resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: contentMode)
    }
}

struct TransportControls: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        HStack(spacing: 16) {
            Button(action: { playback.previousTrack() }) {
                Image(systemName: "backward.fill")
            }
            .help("Previous track (⌘←)")

            if playback.isPlaying {
                Button(action: { playback.pause() }) {
                    Image(systemName: "pause.fill")
                }
                .help("Pause (Space)")
            } else {
                Button(action: { playback.play() }) {
                    Image(systemName: "play.fill")
                }
                .help("Play (Space)")
            }

            Button(action: { playback.stop() }) {
                Image(systemName: "stop.fill")
            }
            .help("Stop (⌘.)")

            Button(action: { playback.nextTrack() }) {
                Image(systemName: "forward.fill")
            }
            .help("Next track (⌘→)")
        }
        .buttonStyle(.borderless)
        .font(.title2)
        .disabled(playback.currentAlbum == nil)
    }
}

struct PlaybackProgressView: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        VStack(spacing: 8) {
            progressRow(
                label: "Track",
                progress: playback.trackProgress,
                elapsed: TrackTimeFormatting.formatClock(playback.trackElapsed),
                total: TrackTimeFormatting.formatClock(playback.trackDuration)
            ) { fraction in
                playback.seekToTrackProgress(fraction)
            }

            progressRow(
                label: "Album",
                progress: playback.albumProgress,
                elapsed: TrackTimeFormatting.formatClock(playback.currentTime),
                total: TrackTimeFormatting.formatClock(playback.albumDuration)
            ) { fraction in
                playback.seekToAlbumProgress(fraction)
            }
        }
        .disabled(playback.currentAlbum == nil)
    }

    private func progressRow(
        label: String,
        progress: Double,
        elapsed: String,
        total: String,
        onSeek: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(elapsed) / \(total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            SeekableProgressBar(progress: progress, onSeek: onSeek)
        }
    }
}

private struct SeekableProgressBar: View {
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, geometry.size.width * progress))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = (value.location.x / geometry.size.width).clamped(to: 0...1)
                        onSeek(fraction)
                    }
            )
        }
        .frame(height: 6)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

struct SpinningCDView: View {
    let isSpinning: Bool
    let size: CGFloat

    @State private var angle: Double = 0

    private let secondsPerRotation = 4.0

    var body: some View {
        Image("cd")
            .highQualityScaled(contentMode: .fit)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
                guard isSpinning else { return }
                angle += 360.0 / (30.0 * secondsPerRotation)
                if angle >= 360 {
                    angle -= 360
                }
            }
    }
}

struct PlayerTrackListView: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let album = playback.currentAlbum {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                        trackRow(index: index, track: track)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 120)
    }

    private func trackRow(index: Int, track: LibraryTrack) -> some View {
        Button {
            playback.playTrack(at: index)
        } label: {
            HStack(spacing: 8) {
                Text("\(track.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                    .monospacedDigit()

                Text(track.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if index == playback.currentTrackIndex {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(TrackTimeFormatting.formatDuration(start: track.startSeconds, end: track.endSeconds))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            index == playback.currentTrackIndex
                ? Color.accentColor.opacity(0.18)
                : Color.clear
        )
    }
}

struct NowPlayingMetadataView: View {
    enum Layout {
        case compact
        case player
    }

    let album: LibraryAlbum?
    let track: LibraryTrack?
    let artworkURL: URL?
    var isPlaying: Bool = false
    var layout: Layout = .compact
    private var trailingControls: AnyView?

    @AppStorage("showSpinningCDWhilePlaying") private var showSpinningCDWhilePlaying = true

    init(
        album: LibraryAlbum?,
        track: LibraryTrack?,
        artworkURL: URL?,
        isPlaying: Bool = false,
        layout: Layout = .compact,
        trailingControls: AnyView? = nil
    ) {
        self.album = album
        self.track = track
        self.artworkURL = artworkURL
        self.isPlaying = isPlaying
        self.layout = layout
        self.trailingControls = trailingControls
    }

    private var artworkSize: CGFloat {
        layout == .player ? 128 : 64
    }

    private var shouldShowCD: Bool {
        showSpinningCDWhilePlaying && album != nil
    }

    var body: some View {
        Group {
            switch layout {
            case .compact:
                compactLayout
            case .player:
                playerLayout
            }
        }
    }

    private var compactLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            artworkRow
            metadataText(alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private var playerLayout: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                artwork
                if shouldShowCD {
                    SpinningCDView(isSpinning: isPlaying, size: artworkSize)
                }
                if let trailingControls {
                    trailingControls
                }
            }
            metadataText(alignment: .center)
                .frame(maxWidth: .infinity)
        }
    }

    private var artworkRow: some View {
        HStack(spacing: layout == .player ? 14 : 10) {
            artwork
            if shouldShowCD {
                SpinningCDView(isSpinning: isPlaying, size: artworkSize)
            }
        }
    }

    private func metadataText(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(track?.title ?? "No track")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
            Text(trackPerformer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(album?.displayTitle ?? "No album loaded")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
        }
    }

    private var trackPerformer: String {
        if let p = track?.performer, !p.isEmpty { return p }
        return album?.performer ?? ""
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = artworkURL, let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .highQualityScaled(contentMode: .fill)
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: layout == .player ? 8 : 6))
        } else {
            RoundedRectangle(cornerRadius: layout == .player ? 8 : 6)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: artworkSize, height: artworkSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(layout == .player ? .title : .body)
                        .foregroundStyle(.secondary)
                }
        }
    }
}
