import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var libraryPath: String = AppSettings.libraryRootURL?.path ?? ""
    @State private var useCustomXMLLocation: Bool = AppSettings.useCustomLibraryXMLLocation
    @State private var customXMLPath: String = AppSettings.libraryXMLDirectoryURL?.path ?? ""
    @State private var saveLastPlayedPosition: Bool = AppSettings.saveLastPlayedPosition
    @State private var showSpinningCDWhilePlaying: Bool = AppSettings.showSpinningCDWhilePlaying
    @State private var showStatusMenu: Bool = AppSettings.showStatusMenu
    @State private var continuousAlbumPlay: Bool = AppSettings.continuousAlbumPlay
    @State private var theme: AppTheme = AppSettings.theme

    var body: some View {
        Form {
            Section {
                LabeledContent("Library home") {
                    Text(libraryPath.isEmpty ? "Not set" : libraryPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: 280, alignment: .trailing)
                }
                HStack {
                    Button("Choose Folder…") {
                        if let url = FolderPicker.chooseLibraryFolder() {
                            AppSettings.libraryRootURL = url
                            libraryPath = url.path
                            NotificationCenter.default.post(name: .flacNestLibraryRootDidChange, object: nil)
                        }
                    }
                    if !libraryPath.isEmpty {
                        Button("Clear") {
                            AppSettings.libraryRootURL = nil
                            libraryPath = ""
                            NotificationCenter.default.post(name: .flacNestLibraryRootDidChange, object: nil)
                        }
                    }
                }
            } footer: {
                Text("Album CUE sheets and FLAC files are scanned under this folder.")
            }

            Section {
                Toggle("Save flacnest.xml to a custom folder", isOn: customXMLToggle)

                if useCustomXMLLocation {
                    LabeledContent("Library data folder") {
                        Text(customXMLPath.isEmpty ? "Not set" : customXMLPath)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: 280, alignment: .trailing)
                    }
                    Button("Choose Folder…") {
                        chooseCustomXMLDirectory()
                    }
                } else {
                    LabeledContent("Library data file") {
                        Text(defaultXMLPathLabel)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: 280, alignment: .trailing)
                    }
                }
            } footer: {
                if useCustomXMLLocation {
                    Text("flacnest.xml will be stored in the selected folder.")
                } else {
                    Text("flacnest.xml will be stored in your library home folder.")
                }
            }

            Section {
                Picker("Theme", selection: themeBinding) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Choose Light or Dark, or follow your Mac’s appearance setting.")
            }

            Section {
                Toggle("Show status menu", isOn: showStatusMenuToggle)
                Toggle("Save last played album and position", isOn: saveLastPlayedToggle)
                Toggle("Continuous album play", isOn: continuousAlbumPlayToggle)
                Toggle("Show spinning CD while playing", isOn: showSpinningCDToggle)
            } footer: {
                Text("The status menu adds a FlacNest icon to the menu bar with playback controls and now playing info. Continuous album play advances to the next album in the current library sort order when the last track finishes.")
            }

            Section {
                Text("Images provided by Vecteezy.com")
                Button("Go to Vecteezy.com") {
                    openURL(URL(string: "https://www.vecteezy.com")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
        .onAppear {
            syncFromAppSettings()
        }
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { theme },
            set: { newValue in
                theme = newValue
                AppSettings.theme = newValue
            }
        )
    }

    private var showStatusMenuToggle: Binding<Bool> {
        Binding(
            get: { showStatusMenu },
            set: { enabled in
                showStatusMenu = enabled
                AppSettings.showStatusMenu = enabled
            }
        )
    }

    private var continuousAlbumPlayToggle: Binding<Bool> {
        Binding(
            get: { continuousAlbumPlay },
            set: { enabled in
                continuousAlbumPlay = enabled
                AppSettings.continuousAlbumPlay = enabled
            }
        )
    }

    private var showSpinningCDToggle: Binding<Bool> {
        Binding(
            get: { showSpinningCDWhilePlaying },
            set: { enabled in
                showSpinningCDWhilePlaying = enabled
                AppSettings.showSpinningCDWhilePlaying = enabled
            }
        )
    }

    private var saveLastPlayedToggle: Binding<Bool> {
        Binding(
            get: { saveLastPlayedPosition },
            set: { enabled in
                saveLastPlayedPosition = enabled
                AppSettings.saveLastPlayedPosition = enabled
            }
        )
    }

    private var customXMLToggle: Binding<Bool> {
        Binding(
            get: { useCustomXMLLocation },
            set: { enabled in
                if enabled {
                    chooseCustomXMLDirectory()
                } else {
                    _ = applyXMLLocationChange(useCustom: false, directory: nil)
                }
            }
        )
    }

    private var defaultXMLPathLabel: String {
        if libraryPath.isEmpty {
            return "Library home/flacnest.xml"
        }
        return (libraryPath as NSString).appendingPathComponent("flacnest.xml")
    }

    private func chooseCustomXMLDirectory() {
        guard let url = FolderPicker.chooseLibraryXMLFolder() else { return }
        _ = applyXMLLocationChange(useCustom: true, directory: url)
    }

    @discardableResult
    private func applyXMLLocationChange(useCustom: Bool, directory: URL?) -> Bool {
        let previousXMLURL = AppSettings.libraryXMLURL
        let applied = LibraryXMLLocationChange.apply(
            useCustomLocation: useCustom,
            customDirectory: directory,
            previousXMLURL: previousXMLURL
        )
        syncFromAppSettings()
        return applied
    }

    private func syncFromAppSettings() {
        useCustomXMLLocation = AppSettings.useCustomLibraryXMLLocation
        customXMLPath = AppSettings.libraryXMLDirectoryURL?.path ?? ""
        saveLastPlayedPosition = AppSettings.saveLastPlayedPosition
        showSpinningCDWhilePlaying = AppSettings.showSpinningCDWhilePlaying
        showStatusMenu = AppSettings.showStatusMenu
        continuousAlbumPlay = AppSettings.continuousAlbumPlay
        theme = AppSettings.theme
    }
}
