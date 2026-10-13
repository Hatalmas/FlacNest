import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 200)
            creditsCard
                .padding(20)
        }
        .frame(width: 460, height: 520)
        .containerBackground(for: .window) {
            Image("AboutBackground")
                .resizable()
                .scaledToFill()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: Color.black.opacity(0.18), location: 0.62),
                            .init(color: Color.black.opacity(0.55), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
        }
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbarBackground(.bar, for: .windowToolbar)
    }

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text(versionLine)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.white.opacity(0.86))

            Divider()
                .overlay(Color.white.opacity(0.28))

            VStack(alignment: .leading, spacing: 6) {
                creditLink("Cursor", url: "https://cursor.sh", detail: "portions written and refined with cursor.sh")
                creditLink("FFmpeg", url: "https://ffmpeg.org", detail: "mobile export conversion")
                creditLink("Vecteezy", url: "https://www.vecteezy.com", detail: "UI imagery")
                creditLink("PNG ARTS", url: "https://www.pngarts.com", detail: "UI imagery")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestGlassSurface(cornerRadius: 16)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "FlacNest"
    }

    private var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?) where !build.isEmpty && build != version:
            return "Version \(version) (\(build))"
        case let (version?, _):
            return "Version \(version)"
        default:
            return "Version"
        }
    }

    private func creditLink(_ title: String, url: String, detail: String) -> some View {
        Button {
            if let destination = URL(string: url) {
                openURL(destination)
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(url)
    }
}
