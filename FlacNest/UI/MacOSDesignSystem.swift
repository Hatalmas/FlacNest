import AppKit
import SwiftUI

#if os(macOS)

enum NestMacMetrics {
    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let listRowCornerRadius: CGFloat = 8
    static let artworkCornerRadius: CGFloat = 6
    static let sidebarMinWidth: CGFloat = 180
    static let sidebarIdealWidth: CGFloat = 200
    static let inspectorMinWidth: CGFloat = 280
    static let inspectorIdealWidth: CGFloat = 320
    static let inspectorMaxWidth: CGFloat = 440
    static let gridItemMinWidth: CGFloat = 150
    static let gridItemMaxWidth: CGFloat = 220
    static let gridSpacing: CGFloat = 20
    static let listArtworkSize: CGFloat = 40
}

enum LibrarySidebarFilter: String, CaseIterable, Identifiable, Hashable {
    case allAlbums
    case favorites
    case hidden
    case noBarcode
    case noCoverArt
    case noMetadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allAlbums: return "All Albums"
        case .favorites: return "Favorites"
        case .hidden: return "Hidden"
        case .noBarcode: return "No Barcode"
        case .noCoverArt: return "No Cover Art"
        case .noMetadata: return "No Metadata"
        }
    }

    var systemImage: String {
        switch self {
        case .allAlbums: return "square.stack"
        case .favorites: return "star"
        case .hidden: return "eye.slash"
        case .noBarcode: return "barcode"
        case .noCoverArt: return "photo"
        case .noMetadata: return "text.badge.xmark"
        }
    }

    static let libraryCases: [LibrarySidebarFilter] = [.allAlbums, .favorites, .hidden]
    static let missingCases: [LibrarySidebarFilter] = [.noBarcode, .noCoverArt, .noMetadata]
}

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    static let storageKey = "libraryViewMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "Grid"
        case .list: return "List"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

struct LibraryGridSectionHeader: View {
    let title: String

    @Environment(\.nestThemePalette) private var palette

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .nestPrimaryForeground()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(alignment: .top) {
                scrim
                    .padding(.horizontal, -(NestMacMetrics.contentPadding + 4))
            }
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var scrim: some View {
        if NestGlassSupport.isAvailable {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(scrimMask)
        } else if let palette {
            LinearGradient(
                colors: [
                    palette.background.opacity(0.96),
                    palette.background.opacity(0.78),
                    palette.background.opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.96),
                    Color(nsColor: .windowBackgroundColor).opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var scrimMask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.82), location: 0.58),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct NestMacEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Loads downsampled artwork off the main thread and shows a placeholder until it is ready.
private struct ArtworkEpochKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var artworkEpoch: Int {
        get { self[ArtworkEpochKey.self] }
        set { self[ArtworkEpochKey.self] = newValue }
    }
}

struct LibraryArtworkView: View {
    let url: URL?
    let size: CGFloat?
    var cornerRadius: CGFloat = NestMacMetrics.artworkCornerRadius

    @Environment(\.displayScale) private var displayScale
    @Environment(\.artworkEpoch) private var artworkEpoch
    @State private var image: NSImage?
    @State private var loadedPath: String?

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: geometry.size.width, height: geometry.size.height)
                .task(id: taskID(for: geometry.size.width)) {
                    await load(pointSize: geometry.size.width)
                }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let image, loadedPath == url?.path {
            Image(nsImage: image)
                .highQualityScaled(contentMode: .fill)
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.system(size: max(12, (size ?? 120) * 0.28), weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func taskID(for width: CGFloat) -> String {
        "\(artworkEpoch)#\(ArtworkImageCache.fileRevision(for: url))#\(Int(width / 64))"
    }

    private func load(pointSize: CGFloat) async {
        guard let url, pointSize > 0 else {
            image = nil
            loadedPath = nil
            return
        }
        let pixelSize = pointSize * displayScale
        let loaded = await Task.detached(priority: .utility) {
            ArtworkImageCache.thumbnail(for: url, maxPixelSize: pixelSize)
        }.value
        guard !Task.isCancelled else { return }
        image = loaded
        loadedPath = url.path
    }
}

extension View {
    func nestMacWindowChrome() -> some View {
        self
            .toolbarBackground(.visible, for: .windowToolbar)
    }
}

#endif
