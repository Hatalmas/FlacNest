import SwiftUI

@main
struct FlacNestMobileApp: App {
    @State private var libraryStore = MobileLibraryStore()
    @AppStorage(MobileThemeSettings.themeKey) private var themeRawValue = MobileAppTheme.nest.rawValue

    private var theme: MobileAppTheme {
        MobileAppTheme(rawValue: themeRawValue) ?? .nest
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environment(libraryStore)
                .mobileAppTheme(theme)
                .onAppear {
                    libraryStore.loadLibraryIfAvailable()
                }
        }
    }
}
