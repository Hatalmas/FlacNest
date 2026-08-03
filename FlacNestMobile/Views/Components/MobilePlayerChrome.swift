import SwiftUI

struct MobileCDCaseArtworkView: View {
    let url: URL?
    let height: CGFloat

    @State private var image: UIImage?

    private var caseWidth: CGFloat {
        CDCaseArtworkLayout.displayWidth(forHeight: height)
    }

    private var artworkFrame: (width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) {
        let scaleX = caseWidth / CDCaseArtworkLayout.casePixelSize.width
        let scaleY = height / CDCaseArtworkLayout.casePixelSize.height
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
                .frame(width: caseWidth, height: height)
        }
        .frame(width: caseWidth, height: height)
        .task(id: url?.path) {
            guard let url else {
                image = nil
                return
            }
            image = await Task.detached(priority: .utility) {
                MobileArtworkImageCache.image(for: url, maxPixelSize: max(height * 2, 256))
            }.value
        }
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            Color.secondary.opacity(0.2)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.title)
                        .mobileSecondaryForeground()
                }
        }
    }
}

struct MobilePlaybackProgressView: View {
    var playback: MobilePlaybackController

    var body: some View {
        VStack(spacing: 10) {
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
        .disabled(playback.currentAlbum == nil || playback.isLoadingAudio)
    }

    private func progressRow(
        label: String,
        progress: Double,
        elapsed: String,
        total: String,
        onSeek: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .mobileSecondaryForeground()
                Spacer()
                Text("\(elapsed) / \(total)")
                    .font(.caption2.monospacedDigit())
                    .mobileSecondaryForeground()
            }

            MobileSeekableProgressBar(progress: progress, onSeek: onSeek)
        }
    }
}

private struct MobileSeekableProgressBar: View {
    let progress: Double
    let onSeek: (Double) -> Void

    @State private var scrubFraction: Double?

    private var displayProgress: Double {
        scrubFraction ?? progress
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, geometry.size.width * displayProgress))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubFraction = (value.location.x / geometry.size.width).clamped(to: 0...1)
                    }
                    .onEnded { value in
                        let fraction = (value.location.x / geometry.size.width).clamped(to: 0...1)
                        scrubFraction = nil
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
