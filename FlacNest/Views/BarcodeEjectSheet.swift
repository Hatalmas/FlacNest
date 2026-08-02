import SwiftUI

struct BarcodeEjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @Environment(PlaybackController.self) private var playback
    @EnvironmentObject private var barcodeEject: BarcodeEjectController

    @StateObject private var scanner = BarcodeScannerSession()
    @State private var pendingBarcode: String?
    @State private var searchText = ""
    @State private var errorMessage: String?

    private var filteredAlbums: [LibraryAlbum] {
        LibraryAlbumSorting
            .sorted(libraryVM.library.albums, by: libraryVM.sortMode)
            .filter { LibraryViewModel.albumMatchesSearch($0, query: searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let pendingBarcode {
                assignmentContent(for: pendingBarcode)
            } else {
                scannerContent
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear {
            scanner.onBarcodeDetected = handleScannedBarcode
            scanner.prepare()
        }
        .onDisappear {
            scanner.stop()
        }
    }

    private var header: some View {
        HStack {
            Text(pendingBarcode == nil ? "Eject — Scan Barcode" : "Assign Barcode to Album")
                .font(.title2)
            Spacer()
            if pendingBarcode != nil {
                Button("Scan Again") {
                    pendingBarcode = nil
                    errorMessage = nil
                    searchText = ""
                    scanner.onBarcodeDetected = handleScannedBarcode
                    scanner.prepare()
                }
            }
            Button("Cancel") {
                barcodeEject.dismiss()
                dismiss()
            }
        }
        .padding()
    }

    private var scannerContent: some View {
        VStack(spacing: 16) {
            if !scanner.availableCameras.isEmpty {
                HStack {
                    Text("Camera")
                        .foregroundStyle(.secondary)
                    Picker("Camera", selection: cameraSelection) {
                        ForEach(scanner.availableCameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }

            if scanner.isRunning {
                ZStack {
                    CameraPreview(session: scanner.captureSession)
                    ScanRegionGuide(
                        normalizedRegion: BarcodeScannerSession.scanGuideRegion,
                        isActive: scanner.isAnalyzingFrames
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                }
                .padding()
            } else if let scannerError = scanner.errorMessage {
                ContentUnavailableView(
                    "Camera Unavailable",
                    systemImage: "camera.fill",
                    description: Text(scannerError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Starting camera…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Text("Center the CD barcode in the highlighted area to scan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
    }

    private var cameraSelection: Binding<String> {
        Binding(
            get: { scanner.selectedCameraID },
            set: { scanner.selectCamera(id: $0) }
        )
    }

    private func assignmentContent(for barcode: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Unknown barcode")
                    .font(.headline)
                Text(barcode)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Choose the album this barcode belongs to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            TextField("Search albums", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if filteredAlbums.isEmpty {
                ContentUnavailableView(
                    "No Matching Albums",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredAlbums) { album in
                    Button {
                        assignBarcode(barcode, to: album)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.displayTitle)
                                .font(.headline)
                            Text(album.performer.isEmpty ? album.flacRelativePath : album.performer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let existingBarcode = album.barcode, !existingBarcode.isEmpty {
                                Text("Current barcode: \(existingBarcode)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
    }

    private func handleScannedBarcode(_ barcode: String) {
        if let album = libraryVM.album(forBarcode: barcode) {
            startPlayback(for: album)
            return
        }

        pendingBarcode = barcode
        errorMessage = nil
    }

    private func assignBarcode(_ barcode: String, to album: LibraryAlbum) {
        do {
            try libraryVM.assignBarcode(barcode, to: album.id)
            guard let updatedAlbum = libraryVM.library.albums.first(where: { $0.id == album.id }) else { return }
            startPlayback(for: updatedAlbum)
        } catch {
            errorMessage = "Could not assign barcode: \(error.localizedDescription)"
        }
    }

    private func startPlayback(for album: LibraryAlbum) {
        libraryVM.selectedAlbumID = album.id
        playback.load(album: album)
        playback.play()
        barcodeEject.dismiss()
        dismiss()
    }
}

private struct BarcodeEjectSheetModifier: ViewModifier {
    @EnvironmentObject private var barcodeEject: BarcodeEjectController
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @Environment(PlaybackController.self) private var playback

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $barcodeEject.isPresenting) {
                BarcodeEjectSheet()
                    .environmentObject(libraryVM)
                    .environment(playback)
                    .environmentObject(barcodeEject)
            }
    }
}

extension View {
    func barcodeEjectSheet() -> some View {
        modifier(BarcodeEjectSheetModifier())
    }
}
