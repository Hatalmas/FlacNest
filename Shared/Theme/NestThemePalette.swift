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

    static let darkNest = NestThemePalette(
        background: Color(hex: 0x302821),
        accent: Color(hex: 0x788A59),
        primary: Color(hex: 0xFDF6EB),
        secondary: Color(hex: 0xFDF6EB, opacity: 0.65),
        surface: Color(hex: 0x452A12)
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
    var showsBackdrop = true

    func body(content: Content) -> some View {
        if let palette {
            content
                .preferredColorScheme(colorScheme ?? .light)
                .tint(palette.accent)
                .environment(\.nestThemePalette, palette)
                .background {
                    if showsBackdrop {
                        NestLiquidBackdrop(palette: palette)
                            .ignoresSafeArea()
                    }
                }
                .nestToolbarBackground(palette.background.opacity(0.001))
        } else {
            content
                .preferredColorScheme(colorScheme)
                .environment(\.nestThemePalette, nil)
                .background {
                    if showsBackdrop {
                        NestLiquidBackdrop(palette: nil)
                            .ignoresSafeArea()
                    }
                }
        }
    }
}

private struct NestThemedScrollSurfaceModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        if palette != nil {
            content
                .scrollContentBackground(.hidden)
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
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.surface.opacity(NestGlassSupport.isAvailable ? 0.35 : 0.82))
                )
                .listRowSeparatorTint(palette.secondary.opacity(0.2))
        } else {
            content
        }
    }
}

private struct NestThemedScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NestSurfaceBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.nestGlassSurface(cornerRadius: 0)
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

private struct NestGroupBoxStyle: GroupBoxStyle {
    @Environment(\.nestThemePalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.headline)
                .foregroundStyle(labelColor)

            configuration.content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nestGlassSurface(cornerRadius: 10)
        }
    }

    private var labelColor: Color {
        if let palette {
            return palette.primary
        }
        return Color.primary
    }
}

private struct NestThemedPlaceholderSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.nestGlassSurface(cornerRadius: cornerRadius)
    }
}

private struct NestThemedGroupBoxModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        if palette != nil {
            content.groupBoxStyle(NestGroupBoxStyle())
        } else {
            content
        }
    }
}

extension View {
    func nestAppTheme(palette: NestThemePalette?, colorScheme: ColorScheme?, showsBackdrop: Bool = true) -> some View {
        modifier(NestAppThemeModifier(palette: palette, colorScheme: colorScheme, showsBackdrop: showsBackdrop))
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

    func nestThemedGroupBoxes() -> some View {
        modifier(NestThemedGroupBoxModifier())
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
