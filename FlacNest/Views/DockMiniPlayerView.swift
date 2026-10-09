import AppKit
import SwiftUI

struct DockMiniPlayerView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(PlaybackController.self) private var playback
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @EnvironmentObject private var playerWindowTracker: PlayerWindowTracker
    @EnvironmentObject private var dockMiniPlayerWindowTracker: DockMiniPlayerWindowTracker
    @AppStorage(AppSettings.dockMiniPlayerOrientationKey) private var orientationRawValue = DockMiniPlayerOrientation.horizontal.rawValue

    private var orientation: DockMiniPlayerOrientation {
        DockMiniPlayerOrientation(rawValue: orientationRawValue) ?? .horizontal
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch orientation {
                case .horizontal:
                    horizontalLayout(artworkSide: artworkSide(for: geometry.size))
                case .vertical:
                    verticalLayout(artworkSide: artworkSide(for: geometry.size))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(
            minWidth: orientation.minWidth,
            minHeight: orientation.minHeight
        )
        .nestGlassPanel(cornerRadius: 16, padding: 0)
        .nestThemedScreenBackground()
        .onAppear {
            dockMiniPlayerWindowTracker.refresh()
            DockMiniPlayerWindowSizing.applyWindowChrome()
            DockMiniPlayerWindowSizing.applyOrientation(AppSettings.dockMiniPlayerOrientation)
            DockMiniPlayerWindowSizing.restoreSize(for: orientation)
        }
        .onChange(of: orientationRawValue) { _, _ in
            DockMiniPlayerWindowSizing.applyOrientation(orientation)
        }
        .onReceive(NotificationCenter.default.publisher(for: .flacNestApplicationWillTerminate)) { _ in
            DockMiniPlayerWindowSizing.saveCurrentSize(for: orientation)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  DockMiniPlayerWindowSizing.isDockMiniPlayerWindow(window) else { return }
            DockMiniPlayerWindowSizing.saveCurrentSize(for: orientation)
        }
        .background(MainWindowLifecycleMonitor())
        .background(DockMiniPlayerWindowConfigurator())
    }

    private func horizontalLayout(artworkSide: CGFloat) -> some View {
        HStack(spacing: 8) {
            artworkButton(side: artworkSide)
            VStack(spacing: 6) {
                trackNumberLabel
                playPauseButton
            }
            .frame(maxWidth: .infinity)
        }
        .padding(6)
    }

    private func verticalLayout(artworkSide: CGFloat) -> some View {
        VStack(spacing: 6) {
            artworkButton(side: artworkSide)
            trackNumberLabel
            playPauseButton
        }
        .padding(6)
    }

    private func artworkSide(for size: CGSize) -> CGFloat {
        let padding: CGFloat = 12
        switch orientation {
        case .horizontal:
            let controlsWidth: CGFloat = 56
            let maxFromHeight = size.height - padding
            let maxFromWidth = size.width - controlsWidth - padding
            return max(32, min(maxFromHeight, maxFromWidth))
        case .vertical:
            let controlsHeight: CGFloat = 44
            let maxFromWidth = size.width - padding
            let maxFromHeight = size.height - controlsHeight - padding
            return max(32, min(maxFromWidth, maxFromHeight))
        }
    }

    private func artworkButton(side: CGFloat) -> some View {
        Button {
            DockMiniPlayerWindowSizing.saveCurrentSize(for: orientation)
            DockMiniPlayerWindowSizing.showFullPlayer(
                dismissWindow: dismissWindow,
                openWindow: openWindow,
                dockMiniTracker: dockMiniPlayerWindowTracker,
                playerTracker: playerWindowTracker
            )
        } label: {
            artworkImage(side: side)
        }
        .buttonStyle(.plain)
        .help("Show full player")
    }

    @ViewBuilder
    private func artworkImage(side: CGFloat) -> some View {
        if let album = playback.currentAlbum,
           let url = libraryVM.artworkURL(for: album),
           let nsImage = ArtworkImageCache.image(for: url) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var trackNumberLabel: some View {
        Text(trackNumberText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var trackNumberText: String {
        guard let track = playback.currentTrack else { return "—" }
        return String(format: "TRACK %02d", track.number)
    }

    private var playPauseButton: some View {
        Button {
            playback.togglePlayPause()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
        }
        .buttonStyle(.borderless)
        .help(playback.isPlaying ? "Pause" : "Play")
        .disabled(playback.currentAlbum == nil)
    }
}

private struct DockMiniPlayerWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ConfiguratorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ConfiguratorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DockMiniPlayerWindowSizing.configure(window)
            DockMiniPlayerWindowSizing.applyOrientation(AppSettings.dockMiniPlayerOrientation)
        }
    }
}
