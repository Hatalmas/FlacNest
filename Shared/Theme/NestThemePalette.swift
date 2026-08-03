import SwiftUI

struct NestThemePalette: Equatable {
    let background: Color
    let accent: Color
    let primary: Color
    let secondary: Color
    let surface: Color

    static let nest = NestThemePalette(
        background: Color(hex: 0xFCF5EC),
        accent: Color(hex: 0x8A9C6A),
        primary: Color(hex: 0x48321B),
        secondary: Color(hex: 0x48321B, opacity: 0.65),
        surface: Color(hex: 0xF3EBDF)
    )
}

private struct NestThemePaletteKey: EnvironmentKey {
    static let defaultValue: NestThemePalette? = nil
}

extension EnvironmentValues {
    var nestThemePalette: NestThemePalette? {
        get { self[NestThemePaletteKey.self] }
        set { self[NestThemePaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct NestAppThemeModifier: ViewModifier {
    let palette: NestThemePalette?
    let colorScheme: ColorScheme?

    func body(content: Content) -> some View {
        if let palette {
            content
                .preferredColorScheme(colorScheme ?? .light)
                .tint(palette.accent)
                .environment(\.nestThemePalette, palette)
                .background(palette.background.ignoresSafeArea())
                .nestToolbarBackground(palette.background)
        } else {
            content
                .preferredColorScheme(colorScheme)
                .environment(\.nestThemePalette, nil)
        }
    }
}

private struct NestThemedScrollSurfaceModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        if let palette {
            content
                .scrollContentBackground(.hidden)
                .background(palette.background)
        } else {
            content
        }
    }
}

private struct NestThemedListSurfaceModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        if let palette {
            content
                .scrollContentBackground(.hidden)
                .background(palette.background)
                .listRowBackground(palette.surface)
                .listRowSeparatorTint(palette.secondary.opacity(0.25))
        } else {
            content
        }
    }
}

private struct NestThemedScreenBackgroundModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        if let palette {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background)
        } else {
            content
        }
    }
}

private struct NestSurfaceBackgroundModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        if let palette {
            content.background(palette.surface)
        } else {
            content.background(.bar)
        }
    }
}

private struct NestSecondaryForegroundModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        if let palette {
            content.foregroundStyle(palette.secondary)
        } else {
            content.foregroundStyle(.secondary)
        }
    }
}

private struct NestPrimaryForegroundModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        if let palette {
            content.foregroundStyle(palette.primary)
        } else {
            content
        }
    }
}

private struct NestThemedPlaceholderSurfaceModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if let palette {
            content
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .nestDefaultPlaceholderSurface(cornerRadius: cornerRadius)
        }
    }
}

extension View {
    func nestAppTheme(palette: NestThemePalette?, colorScheme: ColorScheme?) -> some View {
        modifier(NestAppThemeModifier(palette: palette, colorScheme: colorScheme))
    }

    func nestThemedScrollSurface() -> some View {
        modifier(NestThemedScrollSurfaceModifier())
    }

    func nestThemedListSurface() -> some View {
        modifier(NestThemedListSurfaceModifier())
    }

    func nestThemedScreenBackground() -> some View {
        modifier(NestThemedScreenBackgroundModifier())
    }

    func nestSurfaceBackground() -> some View {
        modifier(NestSurfaceBackgroundModifier())
    }

    func nestSecondaryForeground() -> some View {
        modifier(NestSecondaryForegroundModifier())
    }

    func nestPrimaryForeground() -> some View {
        modifier(NestPrimaryForegroundModifier())
    }

    func nestThemedPlaceholderSurface(cornerRadius: CGFloat = 8) -> some View {
        modifier(NestThemedPlaceholderSurfaceModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    fileprivate func nestDefaultPlaceholderSurface(cornerRadius: CGFloat) -> some View {
        #if os(iOS)
        background(Color(.quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #else
        background(Color(nsColor: .quaternaryLabelColor).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    @ViewBuilder
    fileprivate func nestToolbarBackground(_ color: Color) -> some View {
        #if os(iOS)
        toolbarBackground(color, for: .navigationBar, .tabBar)
            .toolbarBackground(.visible, for: .navigationBar, .tabBar)
        #else
        toolbarBackground(color, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
        #endif
    }
}
