import AppKit
import SwiftUI

enum MetadataTransferStatus {
    case idle
    case working(title: String, detail: String?, fraction: Double?)
    case succeeded(title: String, message: String, revealURL: URL?)
    case failed(title: String, message: String)
}

@MainActor
final class MetadataTransferViewModel: ObservableObject {
    @Published private(set) var status: MetadataTransferStatus = .idle

    var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    func reset() {
        guard !isWorking else { return }
        status = .idle
    }

    // MARK: Export

    func startExport(libraryVM: LibraryViewModel) {
        let library = libraryVM.library
        guard !library.albums.isEmpty else {
            status = .failed(title: "Nothing to Export", message: MetadataTransferError.libraryEmpty.localizedDescription)
            return
        }
        guard let directory = FolderPicker.chooseMetadataExportFolder() else { return }

        let packageURL = directory.appendingPathComponent(MetadataTransferPackage.fileName)
        if FileManager.default.fileExists(atPath: packageURL.path),
           !confirm(
               title: "Replace “\(MetadataTransferPackage.fileName)”?",
               message: "A transfer package already exists in “\(directory.lastPathComponent)”. Exporting replaces it.",
               confirmTitle: "Replace"
           ) {
            return
        }

        let artwork = library.albums.compactMap { album -> MetadataTransferArtworkSource? in
            guard let path = album.artworkRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  let url = libraryVM.artworkURL(for: album) else { return nil }
            return MetadataTransferArtworkSource(
                albumID: album.id,
                sourceURL: url,
                originalPath: path,
                isLibraryRelative: AlbumArtworkStore.isStoredPath(path)
            )
        }
        let rootPath = AppSettings.libraryRootURL?.path

        status = .working(title: "Exporting…", detail: "Packing \(library.albums.count) albums", fraction: 0)

        let reportProgress: (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in
                self?.updateProgress(
                    title: "Exporting…",
                    detail: "Packing artwork \(completed) of \(total)",
                    fraction: total > 0 ? Double(completed) / Double(total) : nil
                )
            }
        }

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<MetadataTransferExportResult, Error> in
                Result {
                    try MetadataTransferExporter.export(
                        library: library,
                        artwork: artwork,
                        sourceLibraryRootPath: rootPath,
                        to: packageURL,
                        progress: reportProgress
                    )
                }
            }.value

            switch result {
            case .success(let export):
                var message = "\(export.albumCount) albums and \(export.artworkCount) images saved to “\(directory.lastPathComponent)”."
                if export.missingArtworkCount > 0 {
                    message += " \(export.missingArtworkCount) images could not be read and were skipped."
                }
                status = .succeeded(title: "Export Complete", message: message, revealURL: export.packageURL)
            case .failure(let error):
                status = .failed(title: "Export Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: Import

    func startImport(libraryVM: LibraryViewModel, packageURL requestedURL: URL? = nil) {
        guard !isWorking, let packageURL = requestedURL ?? choosePackage() else { return }

        status = .working(title: "Unpacking…", detail: packageURL.lastPathComponent, fraction: nil)

        Task {
            let unpacked = await Task.detached(priority: .userInitiated) {
                Result { try MetadataTransferImporter.unpack(packageURL) }
            }.value

            let contents: MetadataTransferPackageContents
            switch unpacked {
            case .success(let value):
                contents = value
            case .failure(let error):
                status = .failed(title: "Import Failed", message: error.localizedDescription)
                return
            }

            guard let selection = await chooseLibraryRoot(for: contents),
                  confirmReplacement(
                      contents: contents,
                      root: selection.root,
                      matchedCount: selection.resolution.foundCount,
                      remappedCount: selection.resolution.remappedCount,
                      currentAlbumCount: libraryVM.library.albums.count
                  ) else {
                MetadataTransferImporter.cleanUp(contents)
                status = .idle
                return
            }

            await install(
                contents,
                library: selection.resolution.library,
                root: selection.root,
                matchedCount: selection.resolution.foundCount,
                remappedCount: selection.resolution.remappedCount
            )
        }
    }

    private func chooseLibraryRoot(
        for contents: MetadataTransferPackageContents
    ) async -> (root: URL, resolution: MetadataTransferPathResolution)? {
        let albumCount = contents.library.albums.count
        while true {
            status = .working(title: "Choose Your FLAC Folder", detail: "\(albumCount) albums to import", fraction: nil)
            guard let root = FolderPicker.chooseImportedLibraryFolder(
                albumCount: albumCount,
                sourceRootPath: contents.manifest.sourceLibraryRootPath
            ) else { return nil }

            status = .working(title: "Searching for FLAC files…", detail: root.lastPathComponent, fraction: nil)
            let accessing = root.startAccessingSecurityScopedResource()
            defer { if accessing { root.stopAccessingSecurityScopedResource() } }
            let library = contents.library
            let resolution = await Task.detached(priority: .userInitiated) {
                MetadataTransferImporter.resolveAudioPaths(in: library, libraryRoot: root)
            }.value

            guard resolution.foundCount == 0, albumCount > 0 else { return (root, resolution) }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "No Albums Found in “\(root.lastPathComponent)”"
            alert.informativeText = "None of the \(albumCount) exported albums were found in this folder or its subfolders. Choose the folder that contains the copied FLAC files — they can be nested anywhere underneath it."
            alert.addButton(withTitle: "Choose Again")
            alert.addButton(withTitle: "Import Anyway")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                continue
            case .alertSecondButtonReturn:
                return (root, resolution)
            default:
                return nil
            }
        }
    }

    private func confirmReplacement(
        contents: MetadataTransferPackageContents,
        root: URL,
        matchedCount: Int,
        remappedCount: Int,
        currentAlbumCount: Int
    ) -> Bool {
        let albumCount = contents.library.albums.count
        let existingXML = FileManager.default.fileExists(atPath: targetLibraryXMLURL(for: root).path)
        guard currentAlbumCount > 0 || existingXML || matchedCount < albumCount || remappedCount > 0 else { return true }

        var lines = ["\(matchedCount) of \(albumCount) albums were found in “\(root.lastPathComponent)”."]
        if remappedCount > 0 {
            lines.append("\(remappedCount) album\(remappedCount == 1 ? "" : "s") had moved since export; FlacNest searched subfolders and updated those file paths.")
        }
        if currentAlbumCount > 0 {
            lines.append("Your current library of \(currentAlbumCount) albums on this Mac will be replaced.")
        } else if existingXML {
            lines.append("The flacnest.xml already in this location will be replaced.")
        }
        return confirm(
            title: "Import \(albumCount) Albums?",
            message: lines.joined(separator: "\n\n"),
            confirmTitle: "Import"
        )
    }

    private func install(
        _ contents: MetadataTransferPackageContents,
        library: FlacNestLibrary,
        root: URL,
        matchedCount: Int,
        remappedCount: Int
    ) async {
        status = .working(title: "Importing…", detail: "Restoring artwork", fraction: nil)

        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        let installed = await Task.detached(priority: .userInitiated) {
            Result { try MetadataTransferImporter.install(contents, library: library, libraryRoot: root) }
        }.value
        defer { MetadataTransferImporter.cleanUp(contents) }

        let result: MetadataTransferInstallResult
        switch installed {
        case .success(let value):
            result = value
        case .failure(let error):
            status = .failed(title: "Import Failed", message: error.localizedDescription)
            return
        }

        do {
            AppSettings.libraryRootURL = root
            guard let xmlURL = AppSettings.libraryXMLURL else {
                throw LibraryViewModelError.libraryXMLNotConfigured
            }
            try FlacNestLibraryStore.save(result.library, to: xmlURL)
        } catch {
            status = .failed(title: "Import Failed", message: error.localizedDescription)
            return
        }

        MetadataTransferImporter.removeImportedArtwork(except: result.artworkStoreURL)
        ArtworkImageCache.removeAll()
        NotificationCenter.default.post(name: .flacNestLibraryRootDidChange, object: nil)

        let albumCount = result.library.albums.count
        var message = "\(albumCount) albums imported; \(matchedCount) found in “\(root.lastPathComponent)”."
        if remappedCount > 0 {
            message += " \(remappedCount) path\(remappedCount == 1 ? " was" : "s were") updated after searching subfolders."
        }
        let imageCount = result.copiedArtworkCount + result.reusedArtworkCount
        if imageCount > 0 {
            message += " \(imageCount) images restored."
        }
        if matchedCount < albumCount {
            message += " Missing albums stay in the library and play once their files are in place."
        }
        status = .succeeded(title: "Import Complete", message: message, revealURL: nil)
    }

    // MARK: Helpers

    private func updateProgress(title: String, detail: String?, fraction: Double?) {
        guard isWorking else { return }
        status = .working(title: title, detail: detail, fraction: fraction)
    }

    private func targetLibraryXMLURL(for root: URL) -> URL {
        if AppSettings.useCustomLibraryXMLLocation, let directory = AppSettings.libraryXMLDirectoryURL {
            return directory.appendingPathComponent(MetadataTransferPackage.libraryFileName)
        }
        return root.appendingPathComponent(MetadataTransferPackage.libraryFileName)
    }

    private func choosePackage() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Library Metadata"
        panel.message = "Choose a \(MetadataTransferPackage.fileName) file exported from another Mac."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [MetadataTransferPackage.contentType, .zip]
        panel.prompt = "Import"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct MetadataTransferView: View {
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @StateObject private var viewModel = MetadataTransferViewModel()
    @ObservedObject private var requests = MetadataTransferRequests.shared

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Export to Other Desktop")
                    .font(.title2.weight(.semibold))
                    .nestPrimaryForeground()
                Text("Move album details, favorites, barcodes and all artwork to another Mac, or import them here. Audio files aren’t included — copy your FLAC folder separately.")
                    .font(.callout)
                    .nestSecondaryForeground()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 16) {
                MetadataTransferOptionTile(
                    title: "Export",
                    systemImage: "square.and.arrow.up",
                    description: "Pack metadata and every image into \(MetadataTransferPackage.fileName) in a folder you choose."
                ) {
                    viewModel.startExport(libraryVM: libraryVM)
                }
                .disabled(libraryVM.library.albums.isEmpty || libraryVM.isLibraryBusy)

                MetadataTransferOptionTile(
                    title: "Import",
                    systemImage: "square.and.arrow.down",
                    description: "Unpack an export on this Mac, then choose the folder your FLAC files were moved to."
                ) {
                    viewModel.startImport(libraryVM: libraryVM)
                }
                .disabled(libraryVM.isLibraryBusy)
            }
            .disabled(viewModel.isWorking)

            statusView
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .padding(28)
        .frame(width: 560)
        .nestMacWindowChrome()
        .onAppear(perform: startPendingImportIfReady)
        .onChange(of: requests.pendingImportURL) { _, _ in startPendingImportIfReady() }
        .onChange(of: libraryVM.isLibraryBusy) { _, _ in startPendingImportIfReady() }
    }

    private func startPendingImportIfReady() {
        guard requests.pendingImportURL != nil, !libraryVM.isLibraryBusy, !viewModel.isWorking,
              let url = requests.consumePendingImport() else { return }
        DispatchQueue.main.async {
            viewModel.startImport(libraryVM: libraryVM, packageURL: url)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.status {
        case .idle:
            Text("Both Macs need FlacNest. Copy the FLAC files separately — they can sit anywhere under the folder you choose.")
                .font(.caption)
                .nestSecondaryForeground()
                .multilineTextAlignment(.center)

        case .working(let title, let detail, let fraction):
            VStack(spacing: 8) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .nestPrimaryForeground()
                if let fraction {
                    ProgressView(value: fraction)
                        .frame(maxWidth: 320)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .nestSecondaryForeground()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

        case .succeeded(let title, let message, let revealURL):
            resultView(
                systemImage: "checkmark.circle.fill",
                tint: .green,
                title: title,
                message: message
            ) {
                if let revealURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([revealURL])
                    }
                }
            }

        case .failed(let title, let message):
            resultView(
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                title: title,
                message: message
            ) {
                EmptyView()
            }
        }
    }

    private func resultView<Actions: View>(
        systemImage: String,
        tint: Color,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .nestPrimaryForeground()
                Text(message)
                    .font(.callout)
                    .nestSecondaryForeground()
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    actions()
                    Button("Done") { viewModel.reset() }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

private struct MetadataTransferOpenerRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            MetadataTransferRequests.shared.registerWindowOpener(openWindow)
        }
    }
}

extension View {
    /// Lets packages opened from Finder bring up the Export to Other Desktop window even when it isn't open yet.
    func registersMetadataTransferOpener() -> some View {
        modifier(MetadataTransferOpenerRegistration())
    }
}

private struct MetadataTransferOptionTile: View {
    let title: String
    let systemImage: String
    let description: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.nestThemePalette) private var palette
    @State private var isHovering = false

    private var accent: Color {
        palette?.accent ?? Color.accentColor
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 64, height: 64)
                    .background(accent.opacity(0.14), in: Circle())

                Text(title)
                    .font(.headline)
                    .nestPrimaryForeground()

                Text(description)
                    .font(.callout)
                    .nestSecondaryForeground()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(isHovering && isEnabled ? 0.07 : 0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isHovering && isEnabled ? accent.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .accessibilityHint(description)
    }
}
