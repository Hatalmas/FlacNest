import SwiftUI

struct PrepareExportView: View {
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @StateObject private var viewModel = PrepareExportViewModel()

    var body: some View {
        Form {
            Section {
                Text("Convert each album FLAC to a single MP3 for iPhone/iPad. Track boundaries come from CUE metadata. Resume skips albums listed in process.txt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Encoding") {
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
                .disabled(viewModel.isRunning)

                Picker("MP3 layout", selection: $viewModel.mp3Layout) {
                    ForEach(MobileExportLayout.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .disabled(viewModel.isRunning)
            }

            Section("Destination") {
                LabeledContent("Export folder") {
                    Text(viewModel.exportDirectoryPath.isEmpty ? "Not chosen" : viewModel.exportDirectoryPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: 280, alignment: .trailing)
                        .textSelection(.enabled)
                }

                Button("Choose Folder…") {
                    viewModel.chooseExportDirectory()
                }
                .disabled(viewModel.isRunning)
            }

            Section("Progress") {
                LabeledContent(viewModel.progress.title) {
                    if viewModel.progress.total > 0 {
                        Text("\(viewModel.progress.processed) / \(viewModel.progress.total)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: viewModel.progress.fractionCompleted)

                if !viewModel.progress.currentItem.isEmpty {
                    Text(viewModel.progress.currentItem)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            Section("Process log") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if viewModel.progress.logLines.isEmpty {
                            Text("Log output appears when export starts.")
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
                .frame(height: 140)
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 520)
        .nestThemedScrollSurface()
        .nestThemedScreenBackground()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if viewModel.isRunning {
                    Button("Cancel") {
                        viewModel.cancelExport()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button("Flatten Export") {
                    viewModel.flattenExport()
                }
                .disabled(!viewModel.canFlatten)
                .help("Move MP3s to the export root and update flacnestmobile.xml.")

                Button("Start Export") {
                    viewModel.startExport(library: libraryVM.library) { album in
                        libraryVM.artworkURL(for: album)
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!viewModel.canStart || libraryVM.library.albums.isEmpty)
            }
        }
        .nestMacWindowChrome()
    }
}
