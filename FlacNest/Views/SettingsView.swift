import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case library
    case playback
    case appearance
    case mobile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .playback: return "Playback"
        case .appearance: return "Appearance"
        case .mobile: return "Mobile"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "folder"
        case .playback: return "play.circle"
        case .appearance: return "paintpalette"
        case .mobile: return "iphone"
        }
    }
}

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var libraryVM: LibraryViewModel
    @State private var selectedTab: SettingsTab = .library
    @State private var libraryPath: String = AppSettings.libraryRootURL?.path ?? ""
    @State private var useCustomXMLLocation: Bool = AppSettings.useCustomLibraryXMLLocation
    @State private var customXMLPath: String = AppSettings.libraryXMLDirectoryURL?.path ?? ""
    @State private var saveLastPlayedPosition: Bool = AppSettings.saveLastPlayedPosition
    @State private var showSpinningCDWhilePlaying: Bool = AppSettings.showSpinningCDWhilePlaying
    @State private var cdSpinUpSoundMode: CDSpinUpSoundMode = AppSettings.cdSpinUpSoundMode
    @State private var cdSpinUpSoundVolume: CDSpinUpSoundVolume = AppSettings.cdSpinUpSoundVolume
    @State private var cdSpinUpDelaySeconds: Double = AppSettings.cdSpinUpDelaySeconds
    @State private var cdSpinUpOutputDeviceUID: String = AppSettings.cdSpinUpOutputDeviceUID ?? ""
    @State private var audioOutputDevices: [AudioOutputDevice] = []
    @State private var showStatusMenu: Bool = AppSettings.showStatusMenu
    @State private var dockMiniPlayerOrientation: DockMiniPlayerOrientation = AppSettings.dockMiniPlayerOrientation
    @State private var continuousAlbumPlay: Bool = AppSettings.continuousAlbumPlay
    @State private var playbackSmoothingRampMilliseconds: Double = AppSettings.playbackSmoothingRampMilliseconds
    @State private var theme: AppTheme = AppSettings.theme
    @State private var exportStatusMessage: String?
    @State private var exportErrorMessage: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            libraryTab
                .tabItem { Label(SettingsTab.library.title, systemImage: SettingsTab.library.systemImage) }
                .tag(SettingsTab.library)

            playbackTab
                .tabItem { Label(SettingsTab.playback.title, systemImage: SettingsTab.playback.systemImage) }
                .tag(SettingsTab.playback)

            appearanceTab
                .tabItem { Label(SettingsTab.appearance.title, systemImage: SettingsTab.appearance.systemImage) }
                .tag(SettingsTab.appearance)

            mobileTab
                .tabItem { Label(SettingsTab.mobile.title, systemImage: SettingsTab.mobile.systemImage) }
                .tag(SettingsTab.mobile)
        }
        .formStyle(.grouped)
        .nestThemedScrollSurface()
        .frame(width: 560)
        .frame(minHeight: 420)
        .onAppear {
            syncFromAppSettings()
            refreshAudioOutputDevices()
        }
    }

    private var libraryTab: some View {
        Form {
            Section {
                LabeledContent("Library home") {
                    Text(libraryPath.isEmpty ? "Not set" : libraryPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300, alignment: .trailing)
                        .textSelection(.enabled)
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
                        Button("Re-locate Folder…") {
                            relocateLibraryHome()
                        }
                        .disabled(libraryVM.library.albums.isEmpty)

                        Button("Clear", role: .destructive) {
                            AppSettings.libraryRootURL = nil
                            libraryPath = ""
                            NotificationCenter.default.post(name: .flacNestLibraryRootDidChange, object: nil)
                        }
                    }
                }
            } footer: {
                Text("Album CUE sheets and FLAC files are scanned under this folder. Use Re-locate Folder when your library has moved.")
            }

            Section {
                Toggle("Save flacnest.xml to a custom folder", isOn: customXMLToggle)

                if useCustomXMLLocation {
                    LabeledContent("Library data folder") {
                        Text(customXMLPath.isEmpty ? "Not set" : customXMLPath)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .trailing)
                            .textSelection(.enabled)
                    }
                    Button("Choose Folder…") {
                        chooseCustomXMLDirectory()
                    }
                } else {
                    LabeledContent("Library data file") {
                        Text(defaultXMLPathLabel)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .trailing)
                            .textSelection(.enabled)
                    }
                }
            } footer: {
                Text(useCustomXMLLocation
                     ? "flacnest.xml will be stored in the selected folder."
                     : "flacnest.xml will be stored in your library home folder.")
            }

            Section {
                LabeledContent("Other desktop") {
                    Button("Export to Other Desktop…") {
                        openWindow(id: "transferMetadata")
                    }
                    .disabled(libraryVM.isLibraryBusy)
                }
            } footer: {
                Text("Pack album metadata and all artwork into \(MetadataTransferPackage.fileName) for another Mac, or import one there after moving your FLAC folder.")
            }
        }
    }

    private var playbackTab: some View {
        Form {
            Section {
                Toggle("Save last played album and position", isOn: saveLastPlayedToggle)
                Toggle("Continuous album play", isOn: continuousAlbumPlayToggle)
                Toggle("Show spinning CD while playing", isOn: showSpinningCDToggle)
                LabeledContent("Smoothing ramp") {
                    HStack(spacing: 12) {
                        Slider(
                            value: playbackSmoothingRampBinding,
                            in: AppSettings.playbackSmoothingRampMillisecondsRange,
                            step: 1
                        )
                        Text(playbackSmoothingRampLabel)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Continuous play advances to the next album in the current library sort order when the last track finishes. Smoothing ramp fades in audio for that many milliseconds when you press play or resume.")
            }

            Section {
                Picker("Play CD spin up sound", selection: cdSpinUpSoundModeBinding) {
                    ForEach(CDSpinUpSoundMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Picker("CD spin up volume", selection: cdSpinUpSoundVolumeBinding) {
                    ForEach(CDSpinUpSoundVolume.allCases) { volume in
                        Text(volume.label).tag(volume)
                    }
                }
                .disabled(cdSpinUpSoundMode == .never)
                LabeledContent("Spin-up delay") {
                    HStack(spacing: 12) {
                        Slider(
                            value: cdSpinUpDelayBinding,
                            in: AppSettings.cdSpinUpDelaySecondsRange,
                            step: 0.5
                        )
                        Text(cdSpinUpDelayLabel)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                .disabled(cdSpinUpSoundMode == .never)
                Picker("CD spin up output", selection: cdSpinUpOutputDeviceBinding) {
                    Text("System Default").tag("")
                    ForEach(audioOutputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .disabled(cdSpinUpSoundMode == .never)
            } footer: {
                Text("The spin-up sound plays when you start from pause or stop. If a delay is set, FLAC playback waits that long so the spin-up can play first. Choose a different output — for example the MacBook speakers — so it doesn’t mix into your DAC or headphones.")
            }

            Section {
                Toggle("Show status menu", isOn: showStatusMenuToggle)
                Picker("Dock mini player layout", selection: dockMiniPlayerOrientationBinding) {
                    ForEach(DockMiniPlayerOrientation.allCases) { orientation in
                        Text(orientation.label).tag(orientation)
                    }
                }
            } footer: {
                Text("The status menu adds a menu bar icon with playback controls. The dock mini player is a compact window beside the Dock.")
            }
        }
    }

    private var appearanceTab: some View {
        Form {
            Section {
                Picker("Theme", selection: themeBinding) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Nest themes use FlacNest cream, green, and brown tones. System follows your Mac appearance.")
            }

            Section {
                Text("Images provided by Vecteezy.com")
                Button("Go to Vecteezy.com") {
                    openURL(URL(string: "https://www.vecteezy.com")!)
                }
            }
        }
    }

    private var mobileTab: some View {
        Form {
            Section {
                Button("Export to Mobile App…") {
                    openWindow(id: "prepareExport")
                }
                .disabled(libraryVM.library.albums.isEmpty || libraryVM.isLibraryBusy)

                Button("Export Mobile Metadata Package…") {
                    exportPortableLibrary()
                }
                .disabled(libraryVM.library.albums.isEmpty || libraryVM.isLibraryBusy)

                if let exportStatusMessage {
                    Text(exportStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let exportErrorMessage {
                    Text(exportErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Export to Mobile App converts FLAC to MP3 and writes flacnestmobile.xml for the iOS app. The mobile metadata package is a read-only .flacnestexport bundle (no audio).")
            }
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
                DockIconVisibility.sync()
            }
        )
    }

    private var dockMiniPlayerOrientationBinding: Binding<DockMiniPlayerOrientation> {
        Binding(
            get: { dockMiniPlayerOrientation },
            set: { orientation in
                dockMiniPlayerOrientation = orientation
                AppSettings.dockMiniPlayerOrientation = orientation
                DockMiniPlayerWindowSizing.applyOrientation(orientation)
                DockMiniPlayerWindowSizing.restoreSize(for: orientation)
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

    private var playbackSmoothingRampBinding: Binding<Double> {
        Binding(
            get: { playbackSmoothingRampMilliseconds },
            set: { milliseconds in
                playbackSmoothingRampMilliseconds = milliseconds
                AppSettings.playbackSmoothingRampMilliseconds = milliseconds
            }
        )
    }

    private var playbackSmoothingRampLabel: String {
        if playbackSmoothingRampMilliseconds <= 0 {
            return "None"
        }
        return "\(Int(playbackSmoothingRampMilliseconds.rounded())) ms"
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

    private var cdSpinUpSoundModeBinding: Binding<CDSpinUpSoundMode> {
        Binding(
            get: { cdSpinUpSoundMode },
            set: { mode in
                cdSpinUpSoundMode = mode
                AppSettings.cdSpinUpSoundMode = mode
            }
        )
    }

    private var cdSpinUpSoundVolumeBinding: Binding<CDSpinUpSoundVolume> {
        Binding(
            get: { cdSpinUpSoundVolume },
            set: { volume in
                cdSpinUpSoundVolume = volume
                AppSettings.cdSpinUpSoundVolume = volume
            }
        )
    }

    private var cdSpinUpDelayBinding: Binding<Double> {
        Binding(
            get: { cdSpinUpDelaySeconds },
            set: { delay in
                cdSpinUpDelaySeconds = delay
                AppSettings.cdSpinUpDelaySeconds = delay
            }
        )
    }

    private var cdSpinUpDelayLabel: String {
        if cdSpinUpDelaySeconds <= 0 {
            return "None"
        }
        if cdSpinUpDelaySeconds.rounded() == cdSpinUpDelaySeconds {
            return "\(Int(cdSpinUpDelaySeconds)) s"
        }
        return String(format: "%.1f s", cdSpinUpDelaySeconds)
    }

    private var cdSpinUpOutputDeviceBinding: Binding<String> {
        Binding(
            get: { cdSpinUpOutputDeviceUID },
            set: { uid in
                cdSpinUpOutputDeviceUID = uid
                AppSettings.cdSpinUpOutputDeviceUID = uid.isEmpty ? nil : uid
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
        cdSpinUpSoundMode = AppSettings.cdSpinUpSoundMode
        cdSpinUpSoundVolume = AppSettings.cdSpinUpSoundVolume
        cdSpinUpDelaySeconds = AppSettings.cdSpinUpDelaySeconds
        cdSpinUpOutputDeviceUID = AppSettings.cdSpinUpOutputDeviceUID ?? ""
        showStatusMenu = AppSettings.showStatusMenu
        dockMiniPlayerOrientation = AppSettings.dockMiniPlayerOrientation
        continuousAlbumPlay = AppSettings.continuousAlbumPlay
        playbackSmoothingRampMilliseconds = AppSettings.playbackSmoothingRampMilliseconds
        theme = AppSettings.theme
        exportStatusMessage = nil
        exportErrorMessage = nil
    }

    private func exportPortableLibrary() {
        exportErrorMessage = nil
        exportStatusMessage = nil

        do {
            let packageURL = try PortableLibraryExportPresenter.exportLibrary(libraryVM.library) { album in
                libraryVM.artworkURL(for: album)
            }
            exportStatusMessage = packageURL.map { "Exported to \($0.path)" } ?? "Export finished."
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func refreshAudioOutputDevices() {
        audioOutputDevices = AudioOutputDeviceList.devices()
        if !cdSpinUpOutputDeviceUID.isEmpty,
           !audioOutputDevices.contains(where: { $0.uid == cdSpinUpOutputDeviceUID }) {
            cdSpinUpOutputDeviceUID = ""
            AppSettings.cdSpinUpOutputDeviceUID = nil
        }
    }

    private func relocateLibraryHome() {
        if let newRoot = LibraryRootRelocation.relocateLibrary(currentLibrary: libraryVM.library) {
            libraryPath = newRoot.path
        }
    }
}
