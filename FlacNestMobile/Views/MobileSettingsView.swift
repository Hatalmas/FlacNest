import SwiftUI
import UniformTypeIdentifiers

struct MobileSettingsView: View {
    @Environment(MobileLibraryStore.self) private var libraryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MobileThemeSettings.themeKey) private var themeRawValue = MobileAppTheme.nest.rawValue
    @State private var showFolderPicker = false
    var showsCloseButton = false

    private var theme: MobileAppTheme {
        MobileAppTheme(rawValue: themeRawValue) ?? .nest
    }

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: themeBinding) {
                    ForEach(MobileAppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Nest and Dark Nest use FlacNest cream, green, and brown tones. System follows your device appearance.")
            }

            Section {
                LabeledContent("Source", value: libraryStore.libraryFolderSourceLabel)
                if let path = libraryStore.libraryFolderPath {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Folder")
                            .font(.caption)
                            .mobileSecondaryForeground()
                        Text(path)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("No library folder is configured yet.")
                        .mobileSecondaryForeground()
                }
            } header: {
                Text("Library Folder")
            } footer: {
                Text("The default folder is the app Documents directory (visible in Files when USB file sharing is enabled). A custom folder is remembered across launches.")
            }

            Section {
                Button("Choose Library Folder…") {
                    showFolderPicker = true
                }

                Button("Use Default Documents Folder") {
                    libraryStore.useDefaultLibraryFolder()
                }
                .disabled(libraryStore.libraryFolderSource == .default)
            }

            Section {
                if libraryStore.isLoadingLibrary {
                    HStack {
                        ProgressView()
                        Text("Loading library…")
                            .mobileSecondaryForeground()
                    }
                } else if let package = libraryStore.package {
                    LabeledContent("Albums", value: "\(package.albums.count)")
                    LabeledContent("Loaded from", value: package.displayName)
                } else {
                    Text("No library is loaded.")
                        .mobileSecondaryForeground()
                }
            } header: {
                Text("Library")
            }
        }
        .mobileThemedScrollSurface()
        .navigationTitle("Settings")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                libraryStore.openExportRoot(from: url)
            case .failure(let error):
                libraryStore.errorMessage = error.localizedDescription
            }
        }
    }

    private var themeBinding: Binding<MobileAppTheme> {
        Binding(
            get: { theme },
            set: { themeRawValue = $0.rawValue }
        )
    }
}
