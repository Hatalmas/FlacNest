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
    enum Style {
        case standard
        case player
    }

    var playback: PlaybackController
    var style: Style = .standard
    var onEject: (() -> Void)? = nil

    @Environment(\.nestThemePalette) private var palette

    private var isDisabled: Bool { playback.currentAlbum == nil }

    var body: some View {
        HStack(spacing: style == .player ? 18 : 14) {
            transportButton("Stop", systemName: "stop.fill", role: .tertiary, help: "Stop (⌘.)") {
                playback.stop()
            }

            transportButton("Previous Track", systemName: "backward.fill", role: .secondary, help: "Previous track (⌘←)") {
                playback.previousTrack()
            }

            playPauseButton

            transportButton("Next Track", systemName: "forward.fill", role: .secondary, help: "Next track (⌘→)") {
                playback.nextTrack()
            }

            if let onEject {
                transportButton("Eject", systemName: "eject.fill", role: .tertiary, help: "Eject — scan CD barcode (⌘⇧E)", action: onEject)
            }
        }
        .labelStyle(.iconOnly)
        .disabled(isDisabled)
    }

    private enum ButtonRole {
        case secondary
        case tertiary
    }

    private var accent: Color {
        palette?.accent ?? Color.accentColor
    }

    private var playPauseButton: some View {
        Button {
            playback.togglePlayPause()
        } label: {
            Label(
                playback.isPlaying ? "Pause" : "Play",
                systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
            )
            .font(style == .player ? .title2 : .title3)
            .foregroundStyle(.white)
            .offset(x: playback.isPlaying ? 0 : 1.5)
            .frame(width: primarySize, height: primarySize)
            .background(isDisabled ? Color.secondary.opacity(0.35) : accent, in: Circle())
            .shadow(color: accent.opacity(isDisabled ? 0 : 0.35), radius: 6, y: 2)
            .contentShape(Circle())
        }
        .buttonStyle(TransportPressButtonStyle())
        .help(playback.isPlaying ? "Pause (Space)" : "Play (Space)")
    }

    private var primarySize: CGFloat {
        style == .player ? 52 : 40
    }

    private func transportButton(
        _ title: String,
        systemName: String,
        role: ButtonRole,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(role == .secondary ? .title2 : .body)
                .foregroundStyle(role == .secondary ? (palette?.primary ?? Color.primary) : (palette?.secondary ?? Color.secondary))
                .frame(width: role == .secondary ? 36 : 28, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(TransportPressButtonStyle())
        .help(help)
    }
}

struct PlaybackVolumeControl: View {
    enum Style {
        case player
        case bar
        case menu
    }

    var playback: PlaybackController
    var style: Style = .player

    @Environment(\.nestThemePalette) private var palette

    var body: some View {
        HStack(spacing: style == .bar ? 6 : 8) {
            Button {
                playback.toggleMute()
            } label: {
                Image(systemName: speakerSymbol)
                    .font(style == .player ? .body : .caption)
                    .frame(width: style == .bar ? 16 : 18)
                    .nestSecondaryForeground()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(playback.volume > 0.001 ? "Mute" : "Unmute")

            Slider(
                value: Binding(
                    get: { Double(playback.volume) },
                    set: { playback.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .controlSize(style == .player ? .regular : .small)
            .tint(palette?.accent ?? Color.accentColor)
            .accessibilityLabel("Volume")
        }
        .frame(maxWidth: style == .player ? 240 : (style == .menu ? .infinity : 120))
    }

    private var speakerSymbol: String {
        switch playback.volume {
        case 0...0.001:
            return "speaker.slash.fill"
        case ...0.33:
            return "speaker.wave.1.fill"
        case ...0.66:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }
}

private struct TransportPressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PlaybackProgressView: View {
    enum Style {
        case standard
        case player
    }

    var playback: PlaybackController
    var style: Style = .standard

    private var trackProgressLabel: String {
        guard let album = playback.currentAlbum, playback.currentTrack != nil else { return "Track" }
        return "Track \(playback.currentTrackIndex + 1) of \(album.tracks.count)"
    }

    var body: some View {
        VStack(spacing: style == .player ? 12 : 8) {
            PlaybackProgressRow(
                label: trackProgressLabel,
                progress: playback.trackProgress,
                elapsed: playback.trackElapsed,
                duration: playback.trackDuration
            ) { fraction in
                playback.seekToTrackProgress(fraction)
            }

            PlaybackProgressRow(
                label: "Album",
                progress: playback.albumProgress,
                elapsed: playback.currentTime,
                duration: playback.albumDuration
            ) { fraction in
                playback.seekToAlbumProgress(fraction)
            }
        }
        .disabled(playback.currentAlbum == nil)
    }
}

private struct PlaybackProgressRow: View {
    let label: String
    let progress: Double
    let elapsed: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var scrubFraction: Double?

    private var shownElapsed: Double {
        guard let scrubFraction else { return elapsed }
        return scrubFraction * duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .nestSecondaryForeground()

            SeekableProgressBar(progress: progress, height: 5, scrubFraction: $scrubFraction, onSeek: onSeek)
                .accessibilityLabel("\(label) position")

            HStack {
                Text(TrackTimeFormatting.formatClock(shownElapsed))
                Spacer()
                Text("-" + TrackTimeFormatting.formatClock(max(0, duration - shownElapsed)))
            }
            .font(.caption.monospacedDigit())
            .nestSecondaryForeground()
        }
    }
}

struct SeekableProgressBar: View {
    let progress: Double
    var height: CGFloat = 6
    var scrubFraction: Binding<Double?>? = nil
    let onSeek: (Double) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.nestThemePalette) private var palette
    @State private var dragFraction: Double?
    @State private var isHovering = false

    private var isActive: Bool {
        isEnabled && (isHovering || dragFraction != nil)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let shown = (dragFraction ?? progress).clamped(to: 0...1)
            let barHeight = isActive ? height + 2 : height
            let knobSize = barHeight + 8

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(height: barHeight)
                Capsule()
                    .fill(isEnabled ? (palette?.accent ?? Color.accentColor) : Color.secondary.opacity(0.4))
                    .frame(width: width * shown, height: barHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: width * shown - knobSize / 2)
                    .opacity(isActive ? 1 : 0)
            }
            .frame(width: width, height: geometry.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = (value.location.x / width).clamped(to: 0...1)
                        dragFraction = fraction
                        scrubFraction?.wrappedValue = fraction
                    }
                    .onEnded { value in
                        onSeek((value.location.x / width).clamped(to: 0...1))
                        dragFraction = nil
                        scrubFraction?.wrappedValue = nil
                    }
            )
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isActive)
        }
        .frame(height: height + 12)
        .accessibilityElement()
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(1, progress + 0.05))
            case .decrement: onSeek(max(0, progress - 0.05))
            @unknown default: break
            }
        }
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpinningDiscLayerView(isSpinning: isSpinning && !reduceMotion)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Rotation runs as a Core Animation layer animation in the render server, so SwiftUI does no per-frame work.
private struct SpinningDiscLayerView: NSViewRepresentable {
    let isSpinning: Bool

    func makeNSView(context: Context) -> SpinningDiscNSView {
        let view = SpinningDiscNSView()
        view.setSpinning(isSpinning, animated: false)
        return view
    }

    func updateNSView(_ nsView: SpinningDiscNSView, context: Context) {
        nsView.setSpinning(isSpinning, animated: true)
    }
}

private final class SpinningDiscNSView: NSView {
    private static let rotationKeyPath = "transform.rotation.z"
    private static let spinUpKey = "spinUp"
    private static let spinKey = "spin"
    private static let spinDownKey = "spinDown"

    private let secondsPerRotation: CFTimeInterval = 4.0
    private let spinUpDuration: CFTimeInterval = 0.7
    private let spinDownDuration: CFTimeInterval = 1.5

    // Bezier curves that trace t² and 1-(1-t)², i.e. constant acceleration with no velocity jump at either end.
    private let accelerateTiming = CAMediaTimingFunction(controlPoints: 1.0 / 3.0, 0, 2.0 / 3.0, 1.0 / 3.0)
    private let decelerateTiming = CAMediaTimingFunction(controlPoints: 1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1)

    private let discLayer = CALayer()
    private var isSpinning = false

    /// Negative because positive z-rotation is counter-clockwise in AppKit's unflipped layer space.
    private var angularVelocity: CGFloat {
        -2 * .pi / CGFloat(secondsPerRotation)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        discLayer.contentsGravity = .resizeAspect
        discLayer.minificationFilter = .trilinear
        discLayer.magnificationFilter = .linear
        discLayer.actions = ["transform": NSNull(), "bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
        if let image = NSImage(named: "cd") {
            discLayer.contents = image.layerContents(forContentsScale: image.recommendedLayerContentsScale(0))
        }
        layer?.addSublayer(discLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        discLayer.bounds = bounds
        discLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        discLayer.contentsScale = scale
        if let image = NSImage(named: "cd") {
            discLayer.contents = image.layerContents(forContentsScale: image.recommendedLayerContentsScale(scale))
        }
    }

    func setSpinning(_ spinning: Bool, animated: Bool) {
        guard spinning != isSpinning else { return }
        isSpinning = spinning

        let startAngle = currentAngle
        discLayer.removeAllAnimations()

        if spinning {
            startSpinning(from: startAngle, rampUp: animated)
        } else {
            stopSpinning(from: startAngle, rampDown: animated)
        }
    }

    private var currentAngle: CGFloat {
        let layer = discLayer.presentation() ?? discLayer
        return (layer.value(forKeyPath: Self.rotationKeyPath) as? CGFloat) ?? 0
    }

    private func startSpinning(from startAngle: CGFloat, rampUp: Bool) {
        let now = discLayer.convertTime(CACurrentMediaTime(), from: nil)
        var loopStartAngle = startAngle
        var loopBeginTime = now

        if rampUp {
            loopStartAngle = startAngle + angularVelocity * CGFloat(spinUpDuration) / 2
            loopBeginTime = now + spinUpDuration

            let rampAnimation = CABasicAnimation(keyPath: Self.rotationKeyPath)
            rampAnimation.fromValue = startAngle
            rampAnimation.toValue = loopStartAngle
            rampAnimation.duration = spinUpDuration
            rampAnimation.beginTime = now
            rampAnimation.timingFunction = accelerateTiming
            discLayer.add(rampAnimation, forKey: Self.spinUpKey)
        }

        let loopAnimation = CABasicAnimation(keyPath: Self.rotationKeyPath)
        loopAnimation.fromValue = loopStartAngle
        loopAnimation.toValue = loopStartAngle + angularVelocity * CGFloat(secondsPerRotation)
        loopAnimation.duration = secondsPerRotation
        loopAnimation.beginTime = loopBeginTime
        loopAnimation.repeatCount = .infinity
        loopAnimation.isRemovedOnCompletion = false
        discLayer.add(loopAnimation, forKey: Self.spinKey)

        setModelAngle(loopStartAngle)
    }

    private func stopSpinning(from startAngle: CGFloat, rampDown: Bool) {
        guard rampDown else {
            setModelAngle(startAngle)
            return
        }

        let endAngle = startAngle + angularVelocity * CGFloat(spinDownDuration) / 2
        let decelerateAnimation = CABasicAnimation(keyPath: Self.rotationKeyPath)
        decelerateAnimation.fromValue = startAngle
        decelerateAnimation.toValue = endAngle
        decelerateAnimation.duration = spinDownDuration
        decelerateAnimation.timingFunction = decelerateTiming
        discLayer.add(decelerateAnimation, forKey: Self.spinDownKey)

        setModelAngle(endAngle)
    }

    private func setModelAngle(_ angle: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        discLayer.setValue(angle, forKeyPath: Self.rotationKeyPath)
        CATransaction.commit()
    }
}

struct PlayerTrackListView: View {
    var playback: PlaybackController

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let album = playback.currentAlbum {
                        ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                            PlayerTrackRow(
                                track: track,
                                album: album,
                                isCurrent: index == playback.currentTrackIndex,
                                isPlaying: playback.isPlaying
                            ) {
                                playback.playTrack(at: index)
                            }
                            .id(track.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onAppear { scrollToCurrentTrack(proxy, animated: false) }
            .onChange(of: playback.currentTrackIndex) { _, _ in
                scrollToCurrentTrack(proxy, animated: true)
            }
        }
        .frame(minHeight: 120)
    }

    private func scrollToCurrentTrack(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let id = playback.currentTrack?.id else { return }
        if animated {
            withAnimation { proxy.scrollTo(id) }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct PlayerTrackRow: View {
    let track: LibraryTrack
    let album: LibraryAlbum
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isCurrent {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                        .foregroundStyle(.tint)
                } else if isHovering {
                    Image(systemName: "play.fill")
                        .nestSecondaryForeground()
                } else {
                    Text("\(track.number)")
                        .nestSecondaryForeground()
                }
            }
            .font(.caption.monospacedDigit())
            .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                    .nestPrimaryForeground()
                    .lineLimit(1)
                if let performer = trackPerformer {
                    Text(performer)
                        .font(.caption)
                        .nestSecondaryForeground()
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(TrackTimeFormatting.formatDuration(start: track.startSeconds, end: track.endSeconds))
                .font(.caption.monospacedDigit())
                .nestSecondaryForeground()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .help("Double-click to play")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play", onPlay)
    }

    private var rowFill: Color {
        if isCurrent { return Color.accentColor.opacity(0.16) }
        if isHovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var trackPerformer: String? {
        album.displayedTrackPerformer(for: track)
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
        album?.displayedArtist(for: track) ?? ""
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
    static let toolbarWidth: CGFloat = 52
    static let headerVerticalPadding: CGFloat = 24
    static let displayPadding: CGFloat = 12

    static func maxSize(
        forWidth width: CGFloat,
        showsSpinningCD: Bool,
        reservesTrailingToolbar: Bool = true
    ) -> CGFloat {
        let contentWidth = max(width, minSize)
        let toolbarReserve = reservesTrailingToolbar ? toolbarWidth + rowSpacing : 0
        let reservedWidth = horizontalPadding + toolbarReserve
        if showsSpinningCD {
            let availableWidth = contentWidth - reservedWidth - rowSpacing
            return max(minSize, availableWidth / (CDCaseArtworkLayout.aspectRatio + 1))
        }
        return max(minSize, (contentWidth - reservedWidth) / CDCaseArtworkLayout.aspectRatio)
    }

    static func clamp(
        _ size: CGFloat,
        forWidth width: CGFloat,
        showsSpinningCD: Bool,
        reservesTrailingToolbar: Bool = true
    ) -> CGFloat {
        max(minSize, min(size, maxSize(forWidth: width, showsSpinningCD: showsSpinningCD, reservesTrailingToolbar: reservesTrailingToolbar)))
    }
}

struct PlayerToolbarIconGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            content()
        }
        .font(.title3)
        .labelStyle(.iconOnly)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .nestGlassToolbarBackground(cornerRadius: 14)
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
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
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
        .padding(PlayerArtworkSizing.displayPadding)
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
    var onOpenLibrary: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 3) {
            if let album {
                Text(track?.title ?? album.displayTitle)
                    .font(.title3.weight(.semibold))
                    .nestPrimaryForeground()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if !trackPerformer.isEmpty {
                    Text(trackPerformer)
                        .font(.body)
                        .nestSecondaryForeground()
                        .lineLimit(1)
                }
                Text(album.displayTitle)
                    .font(.callout)
                    .nestSecondaryForeground()
                    .lineLimit(1)
            } else {
                Text("Nothing Playing")
                    .font(.title3.weight(.semibold))
                    .nestPrimaryForeground()
                Text("Choose an album in your library to start listening.")
                    .font(.callout)
                    .nestSecondaryForeground()
                    .multilineTextAlignment(.center)
                if let onOpenLibrary {
                    Button("Open Library", action: onOpenLibrary)
                        .padding(.top, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var trackPerformer: String {
        album?.displayedArtist(for: track) ?? ""
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
