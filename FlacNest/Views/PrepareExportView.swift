import SwiftUI

struct PrepareExportView: View {
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @StateObject private var viewModel = PrepareExportViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            destinationSection
            progressSection
            logSection
            actionSection

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 460)
        .nestThemedScreenBackground()
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prepare Export")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Convert each album FLAC to a single MP3 for iPhone/iPad. Track boundaries come from the CUE metadata, same as on desktop. Files listed in process.txt are skipped when you resume.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Bitrate", selection: $viewModel.bitrate) {
                ForEach(MobileExportBitrate.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isRunning)

            Picker("Conversion threads", selection: $viewModel.parallelism) {
                ForEach(MobileExportParallelism.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .disabled(viewModel.isRunning)

            HStack(spacing: 8) {
                TextField("Export directory", text: $viewModel.exportDirectoryPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button("Choose…") {
                    viewModel.chooseExportDirectory()
                }
                .disabled(viewModel.isRunning)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.progress.title)
                    .font(.headline)
                Spacer()
                if viewModel.progress.total > 0 {
                    Text("\(viewModel.progress.processed) / \(viewModel.progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: viewModel.progress.fractionCompleted)
                .progressViewStyle(.linear)

            if !viewModel.progress.currentItem.isEmpty {
                Text(viewModel.progress.currentItem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Process Log")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if viewModel.progress.logLines.isEmpty {
                        Text("Log output will appear here when export starts.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(Array(viewModel.progress.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(height: 160)
            .padding(8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actionSection: some View {
        HStack {
            if viewModel.isRunning {
                Button("Cancel") {
                    viewModel.cancelExport()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            Spacer()

            Button("Start Export") {
                viewModel.startExport(library: libraryVM.library) { album in
                    libraryVM.artworkURL(for: album)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!viewModel.canStart || libraryVM.library.albums.isEmpty)
        }
    }
}
