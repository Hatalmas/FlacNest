import SwiftUI
import UniformTypeIdentifiers

struct MobileRootView: View {
    @Environment(MobileLibraryStore.self) private var libraryStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSettings = false

    private var useSplitLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if useSplitLayout {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            NavigationStack {
                MobileLibraryView(usesSplitSelection: true, onOpenSettings: { showSettings = true })
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 480)
        } content: {
            NavigationStack {
                if let album = libraryStore.selectedAlbum {
                    MobileAlbumDetailView(album: album)
                } else {
                    ContentUnavailableView {
                        Label("No Album Selected", systemImage: "music.note")
                    } description: {
                        Text("Choose an album from the library to view tracks and metadata.")
                    }
                    .mobileThemedScreenBackground()
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            NavigationStack {
                MobilePlayerShellView()
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                MobileSettingsView(showsCloseButton: true)
            }
        }
    }

    private var iPhoneLayout: some View {
        TabView {
            NavigationStack {
                MobileLibraryView(usesSplitSelection: false, onOpenSettings: nil)
            }
            .tabItem {
                Label("Library", systemImage: "music.note.list")
            }

            NavigationStack {
                MobilePlayerShellView()
            }
            .tabItem {
                Label("Player", systemImage: "play.circle")
            }

            NavigationStack {
                MobileSettingsView(showsCloseButton: false)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
