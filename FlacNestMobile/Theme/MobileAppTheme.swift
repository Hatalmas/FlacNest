import SwiftUI

enum MobileAppTheme: String, CaseIterable, Identifiable {
    case nest
    case darkNest
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nest: return "Nest"
        case .darkNest: return "Dark Nest"
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .nest, .light: return .light
        case .darkNest, .dark: return .dark
        case .system: return nil
        }
    }

    var palette: NestThemePalette? {
        switch self {
        case .nest: return .nest
        case .darkNest: return .darkNest
        case .system, .light, .dark: return nil
        }
    }
}

enum MobileThemeSettings {
    static let themeKey = "mobileAppTheme"

    static var theme: MobileAppTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: themeKey),
                  let theme = MobileAppTheme(rawValue: raw) else {
                return .nest
            }
            return theme
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: themeKey)
        }
    }
}

extension View {
    func mobileAppTheme(_ theme: MobileAppTheme) -> some View {
        nestAppTheme(palette: theme.palette, colorScheme: theme.colorScheme)
    }

    func mobileThemedScrollSurface() -> some View {
        nestThemedScrollSurface()
    }

    func mobileThemedListSurface() -> some View {
        nestThemedListSurface()
    }

    func mobileThemedScreenBackground() -> some View {
        nestThemedScreenBackground()
    }

    func mobileSecondaryForeground() -> some View {
        nestSecondaryForeground()
    }

    func mobilePrimaryForeground() -> some View {
        nestPrimaryForeground()
    }

    func mobileThemedPlaceholderSurface(cornerRadius: CGFloat = 8) -> some View {
        nestThemedPlaceholderSurface(cornerRadius: cornerRadius)
    }
}
