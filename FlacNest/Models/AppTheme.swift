import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case nest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .nest: return "Nest"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .nest: return .light
        case .dark: return .dark
        }
    }

    var palette: NestThemePalette? {
        switch self {
        case .nest: return .nest
        case .system, .light, .dark: return nil
        }
    }
}

extension View {
    func appTheme(_ theme: AppTheme) -> some View {
        nestAppTheme(palette: theme.palette, colorScheme: theme.colorScheme)
    }
}
