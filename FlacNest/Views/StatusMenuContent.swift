import AppKit
import SwiftUI

private enum StatusMenuMetrics {
    static let width: CGFloat = 320
    static let outerPadding: CGFloat = 10
    static let moduleSpacing: CGFloat = 8
    static let modulePadding: CGFloat = 14
    static let moduleCornerRadius: CGFloat = 16
    static let artworkSize: CGFloat = 52
    static let rowCornerRadius: CGFloat = 7
}

struct StatusMenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(PlaybackController.self) private var playback
    @EnvironmentObject private var libraryVM: LibraryViewModel

    var body: some View {
        VStack(spacing: StatusMenuMetrics.moduleSpacing) {
            StatusMenuNowPlayingModule(
                playback: playback,
                artworkURL: playback.currentAlbum.flatMap { libraryVM.artworkURL(for: $0) }
            )
            .environment(\.artworkEpoch, libraryVM.artworkEpoch)

            StatusMenuModule(padding: 5) {
                VStack(spacing: 0) {
                    StatusMenuRow(title: "Show Player", systemImage: "play.rectangle", shortcut: "⌘1") {
                        showPlayer()
                    }
                    .keyboardShortcut("1", modifiers: .command)

                    StatusMenuRow(title: "Show Library", systemImage: "square.stack", shortcut: "⌘2") {
                        showLibrary()
                    }
                    .keyboardShortcut("2", modifiers: .command)

                    StatusMenuSeparator()

                    StatusMenuRow(title: "Settings…", systemImage: "gearshape", shortcut: "⌘,") {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)

                    StatusMenuRow(title: "Quit FlacNest", systemImage: "power", shortcut: "⌘Q") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                }
            }
        }
        .padding(StatusMenuMetrics.outerPadding)
        .frame(width: StatusMenuMetrics.width)
    }

    private func showPlayer() {
        DockIconVisibility.prepareToShowMainWindow()
        openWindow(id: "player")
        DispatchQueue.main.async {
            PlayerWindowSizing.bringPlayerToFront()
        }
    }

    private func showLibrary() {
        DockIconVisibility.prepareToShowMainWindow()
        openWindow(id: "library")
        DispatchQueue.main.async {
            PlayerWindowSizing.bringLibraryToFront()
        }
    }
}

// MARK: - Now Playing

private struct StatusMenuNowPlayingModule: View {
    var playback: PlaybackController
    let artworkURL: URL?

    @State private var scrubFraction: Double?

    private var hasAlbum: Bool { playback.currentAlbum != nil }

    var body: some View {
        StatusMenuModule(padding: StatusMenuMetrics.modulePadding) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    LibraryArtworkView(url: artworkURL, size: StatusMenuMetrics.artworkSize, cornerRadius: 8)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playback.currentTrack?.title ?? "Not Playing")
                            .font(.system(size: 13, weight: .semibold))
                            .nestPrimaryForeground()
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .nestSecondaryForeground()
                            .lineLimit(1)
                        if let album = playback.currentAlbum {
                            Text(album.displayTitle)
                                .font(.system(size: 11))
                                .nestSecondaryForeground()
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if hasAlbum {
                    VStack(spacing: 2) {
                        SeekableProgressBar(
                            progress: playback.trackProgress,
                            height: 4,
                            scrubFraction: $scrubFraction
                        ) { fraction in
                            playback.seekToTrackProgress(fraction)
                        }
                        HStack {
                            Text(TrackTimeFormatting.formatClock(shownElapsed))
                            Spacer()
                            Text("-" + TrackTimeFormatting.formatClock(max(0, playback.trackDuration - shownElapsed)))
                        }
                        .font(.system(size: 10).monospacedDigit())
                        .nestSecondaryForeground()
                    }
                }

                transport

                PlaybackVolumeControl(playback: playback, style: .menu)
            }
        }
    }

    private var shownElapsed: Double {
        guard let scrubFraction else { return playback.trackElapsed }
        return scrubFraction * playback.trackDuration
    }

    private var subtitle: String {
        guard let album = playback.currentAlbum else { return "FlacNest" }
        if let performer = playback.currentTrack?.performer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !performer.isEmpty {
            return performer
        }
        return album.performer
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            StatusMenuTransportButton(title: "Previous Track", systemImage: "backward.fill", size: 17) {
                playback.previousTrack()
            }
            Spacer(minLength: 0)
            StatusMenuTransportButton(
                title: playback.isPlaying ? "Pause" : "Play",
                systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                size: 24
            ) {
                playback.togglePlayPause()
            }
            Spacer(minLength: 0)
            StatusMenuTransportButton(title: "Next Track", systemImage: "forward.fill", size: 17) {
                playback.nextTrack()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .disabled(!hasAlbum)
    }
}

private struct StatusMenuTransportButton: View {
    let title: String
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: size, weight: .regular))
                .nestPrimaryForeground()
                .frame(width: 44, height: 36)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovering && isEnabled ? 0.08 : 0))
                        .frame(width: 36, height: 36)
                )
                .contentShape(Circle())
        }
        .buttonStyle(StatusMenuPressStyle())
        .onHover { isHovering = $0 }
        .help(title)
    }
}

private struct StatusMenuPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Building blocks

private struct StatusMenuModule<Content: View>: View {
    var padding: CGFloat
    @ViewBuilder var content: () -> Content

    @Environment(\.nestThemePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: StatusMenuMetrics.moduleCornerRadius, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05), lineWidth: 0.5)
            }
    }

    private var fill: Color {
        if let palette {
            return palette.surface.opacity(0.75)
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.55)
    }
}

private struct StatusMenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .nestSecondaryForeground()
                Text(title)
                    .font(.system(size: 13))
                    .nestPrimaryForeground()
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .nestSecondaryForeground()
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: StatusMenuMetrics.rowCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.09 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct StatusMenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 0.5)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
    }
}

struct StatusMenuBarLabel: View {
    var body: some View {
        Image("statusMenuPlay")
    }
}
