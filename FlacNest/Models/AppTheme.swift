import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case nest
    case darkNest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .nest: return "Nest"
        case .darkNest: return "Dark Nest"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .nest: return .light
        case .dark, .darkNest: return .dark
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

extension View {
    func appTheme(_ theme: AppTheme) -> some View {
        nestAppTheme(palette: theme.palette, colorScheme: theme.colorScheme)
    }
}
