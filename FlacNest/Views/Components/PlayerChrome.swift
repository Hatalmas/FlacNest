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
    var playback: PlaybackController
    var onEject: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 16) {
            Group {
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
            .disabled(playback.currentAlbum == nil)

            if let onEject {
                Button(action: onEject) {
                    Image(systemName: "eject.fill")
                }
                .help("Eject — scan CD barcode (⌘⇧E)")
            }
        }
        .buttonStyle(.borderless)
        .font(.title2)
    }
}

struct PlaybackProgressView: View {
    var playback: PlaybackController

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
    @State private var angularVelocity: Double = 0

    private let secondsPerRotation = 4.0
    private let spinUpDuration = 0.7
    private let spinDownDuration = 1.5
    private let frameInterval = 1.0 / 60.0

    private var targetAngularVelocity: Double {
        360.0 / secondsPerRotation
    }

    private var spinUpAcceleration: Double {
        targetAngularVelocity / spinUpDuration
    }

    private var spinDownDeceleration: Double {
        targetAngularVelocity / spinDownDuration
    }

    var body: some View {
        cdImage
            .onAppear(perform: advanceRotationIfNeeded)
            .onChange(of: isSpinning) { _, _ in advanceRotationIfNeeded() }
            .modifier(SpinningCDTimerModifier(isActive: isSpinning || angularVelocity > 0) {
                advanceRotation()
            })
    }

    private var cdImage: some View {
        Image("cd")
            .highQualityScaled(contentMode: .fit)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
    }

    private func advanceRotation() {
        if isSpinning {
            if angularVelocity < targetAngularVelocity {
                angularVelocity = min(
                    targetAngularVelocity,
                    angularVelocity + spinUpAcceleration * frameInterval
                )
            }
        } else if angularVelocity > 0 {
            angularVelocity = max(0, angularVelocity - spinDownDeceleration * frameInterval)
        }

        guard angularVelocity > 0 else { return }

        angle += angularVelocity * frameInterval
        if angle >= 360 {
            angle -= 360
        }
    }

    private func advanceRotationIfNeeded() {
        if isSpinning || angularVelocity > 0 {
            advanceRotation()
        }
    }
}

private struct SpinningCDTimerModifier: ViewModifier {
    let isActive: Bool
    let onTick: () -> Void

    func body(content: Content) -> some View {
        if isActive {
            content.onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
                onTick()
            }
        } else {
            content
        }
    }
}

struct PlayerTrackListView: View {
    var playback: PlaybackController

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
        if let url = artworkURL, let nsImage = ArtworkImageCache.image(for: url) {
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

enum PlayerArtworkSizing {
    static let minSize: CGFloat = 64
    static let defaultSize: CGFloat = 128
    static let horizontalPadding: CGFloat = 40
    static let rowSpacing: CGFloat = 14
    static let toolbarWidth: CGFloat = 44
    static let headerVerticalPadding: CGFloat = 24

    static func maxSize(forWidth width: CGFloat, showsSpinningCD: Bool) -> CGFloat {
        let contentWidth = max(width, minSize)
        let reservedWidth = horizontalPadding + toolbarWidth + rowSpacing
        if showsSpinningCD {
            // case + spacing + cd + spacing + toolbar (height drives both case and cd)
            let availableWidth = contentWidth - reservedWidth - rowSpacing
            return max(minSize, availableWidth / (CDCaseArtworkLayout.aspectRatio + 1))
        }
        // case + spacing + toolbar
        return max(minSize, (contentWidth - reservedWidth) / CDCaseArtworkLayout.aspectRatio)
    }

    static func clamp(_ size: CGFloat, forWidth width: CGFloat, showsSpinningCD: Bool) -> CGFloat {
        max(minSize, min(size, maxSize(forWidth: width, showsSpinningCD: showsSpinningCD)))
    }
}

struct AlbumArtworkImage: View {
    let artworkURL: URL?
    let size: CGFloat

    private var caseWidth: CGFloat {
        CDCaseArtworkLayout.displayWidth(forHeight: size)
    }

    private var artworkFrame: (width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) {
        let scaleX = caseWidth / CDCaseArtworkLayout.casePixelSize.width
        let scaleY = size / CDCaseArtworkLayout.casePixelSize.height
        let rect = CDCaseArtworkLayout.artworkPixelRect
        return (
            rect.width * scaleX,
            rect.height * scaleY,
            rect.minX * scaleX,
            rect.minY * scaleY
        )
    }

    var body: some View {
        let artwork = artworkFrame

        ZStack(alignment: .topLeading) {
            artworkContent
                .frame(width: artwork.width, height: artwork.height)
                .clipped()
                .offset(x: artwork.x, y: artwork.y)

            Image("cdcase")
                .resizable()
                .interpolation(.high)
                .frame(width: caseWidth, height: size)
        }
        .frame(width: caseWidth, height: size)
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let url = artworkURL, let nsImage = ArtworkImageCache.image(for: url) {
            Image(nsImage: nsImage)
                .highQualityScaled(contentMode: .fill)
        } else {
            Color.secondary.opacity(0.2)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

struct PlayerArtworkHeaderView<Trailing: View>: View {
    let artworkURL: URL?
    let isPlaying: Bool
    let hasAlbum: Bool
    let artworkSize: CGFloat
    @ViewBuilder var trailingControls: () -> Trailing

    @AppStorage("showSpinningCDWhilePlaying") private var showSpinningCDWhilePlaying = true
    @State private var cdSlideProgress: CGFloat = 1
    @State private var isAnimatingCD = false

    private let cdAnimationDuration = 0.45

    private var caseWidth: CGFloat {
        CDCaseArtworkLayout.displayWidth(forHeight: artworkSize)
    }

    private var showsCDInLayout: Bool {
        hasAlbum && (showSpinningCDWhilePlaying || cdSlideProgress > 0.001)
    }

    private var clusterWidth: CGFloat {
        guard showsCDInLayout else { return caseWidth }
        return caseWidth + PlayerArtworkSizing.rowSpacing + artworkSize
    }

    private var cdExtendedOffsetX: CGFloat {
        caseWidth + PlayerArtworkSizing.rowSpacing
    }

    private var cdTuckedOffsetX: CGFloat {
        (caseWidth - artworkSize) / 2
    }

    private var cdOffsetX: CGFloat {
        cdTuckedOffsetX + (cdExtendedOffsetX - cdTuckedOffsetX) * cdSlideProgress
    }

    private var cdScale: CGFloat {
        0.28 + 0.72 * cdSlideProgress
    }

    var body: some View {
        HStack(alignment: .center, spacing: PlayerArtworkSizing.rowSpacing) {
            artworkCluster
            trailingControls()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            applyCDSlideProgress(showSpinningCDWhilePlaying ? 1 : 0, animated: false)
        }
        .onChange(of: showSpinningCDWhilePlaying) { _, isEnabled in
            guard !isAnimatingCD else { return }
            applyCDSlideProgress(isEnabled ? 1 : 0, animated: false)
        }
    }

    private var artworkCluster: some View {
        ZStack(alignment: .topLeading) {
            if showsCDInLayout {
                Button(action: toggleSpinningCD) {
                    SpinningCDView(isSpinning: isPlaying, size: artworkSize)
                        .frame(width: artworkSize, height: artworkSize)
                }
                .buttonStyle(.plain)
                .disabled(!hasAlbum || cdSlideProgress < 0.35)
                .help(spinningCDHelpText)
                .onHover { hovering in
                    guard hasAlbum, cdSlideProgress > 0.35 else { return }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .offset(x: cdOffsetX)
                .scaleEffect(cdScale)
                .opacity(Double(max(0.05, cdSlideProgress)))
                .zIndex(cdSlideProgress > 0.65 ? 1 : 0)
            }

            Button(action: toggleSpinningCD) {
                AlbumArtworkImage(artworkURL: artworkURL, size: artworkSize)
            }
            .buttonStyle(.plain)
            .disabled(!hasAlbum)
            .help(spinningCDHelpText)
            .onHover { hovering in
                guard hasAlbum else { return }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .zIndex(2)
        }
        .frame(width: clusterWidth, height: artworkSize, alignment: .leading)
    }

    private var spinningCDHelpText: String {
        showSpinningCDWhilePlaying
            ? "Click to slip the CD into the case"
            : "Click the cover to eject the CD"
    }

    private func toggleSpinningCD() {
        guard hasAlbum, !isAnimatingCD else { return }

        if showSpinningCDWhilePlaying {
            tuckCDIntoCase()
        } else {
            ejectCDFromCase()
        }
    }

    private func tuckCDIntoCase() {
        isAnimatingCD = true
        withAnimation(.easeInOut(duration: cdAnimationDuration)) {
            cdSlideProgress = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + cdAnimationDuration) {
            showSpinningCDWhilePlaying = false
            isAnimatingCD = false
        }
    }

    private func ejectCDFromCase() {
        isAnimatingCD = true
        showSpinningCDWhilePlaying = true
        applyCDSlideProgress(0, animated: false)

        withAnimation(.easeInOut(duration: cdAnimationDuration)) {
            cdSlideProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + cdAnimationDuration) {
            isAnimatingCD = false
        }
    }

    private func applyCDSlideProgress(_ progress: CGFloat, animated: Bool) {
        guard animated else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cdSlideProgress = progress
            }
            return
        }

        cdSlideProgress = progress
    }
}

struct PlayerNowPlayingInfoView: View {
    let album: LibraryAlbum?
    let track: LibraryTrack?

    var body: some View {
        VStack(spacing: 4) {
            Text(track?.title ?? "No track")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(trackPerformer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(album?.displayTitle ?? "No album loaded")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var trackPerformer: String {
        if let performer = track?.performer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !performer.isEmpty {
            return performer
        }
        return album?.performer ?? ""
    }
}

struct PlayerArtworkResizeDivider: View {
    @Binding var artworkSize: CGFloat
    let maxSize: CGFloat
    var onResizeEnded: (() -> Void)? = nil

    @State private var sizeAtDragStart: CGFloat?

    var body: some View {
        ZStack {
            Divider()
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 36, height: 4)
        }
        .frame(height: 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if sizeAtDragStart == nil {
                        sizeAtDragStart = artworkSize
                    }
                    let proposed = (sizeAtDragStart ?? artworkSize) + value.translation.height
                    let clamped = min(maxSize, max(PlayerArtworkSizing.minSize, proposed))
                    artworkSize = clamped
                }
                .onEnded { _ in
                    sizeAtDragStart = nil
                    onResizeEnded?()
                }
        )
        .onHover { isHovering in
            if isHovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Drag to resize album art")
    }
}
