import SwiftUI
#if os(macOS)
import AppKit
#endif

enum NestGlassSupport {
    static var isAvailable: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        return false
    }
}

struct NestLiquidBackdrop: View {
    var palette: NestThemePalette?

    var body: some View {
        ZStack {
            baseGradient
            accentGlow(color: accentColor.opacity(0.22), size: 320, x: -140, y: -120)
            accentGlow(color: primaryColor.opacity(0.10), size: 260, x: 150, y: 160)
            accentGlow(color: accentColor.opacity(0.12), size: 200, x: 60, y: -40)
        }
        .ignoresSafeArea()
    }

    private var baseGradient: some View {
        Group {
            if let palette {
                LinearGradient(
                    colors: [
                        palette.background,
                        palette.surface.opacity(0.95),
                        palette.background.opacity(0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .controlBackgroundColor).opacity(0.85),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var accentColor: Color {
        palette?.accent ?? Color.accentColor
    }

    private var primaryColor: Color {
        palette?.primary ?? Color.primary
    }

    private func accentGlow(color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: size * 0.28)
            .offset(x: x, y: y)
    }
}

struct NestGlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat
    var tint: Color?

    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                content
                    .padding(padding)
                    .modifier(NestGlassEffectModifier(tint: resolvedTint, shape: shape))
            } else {
                content
                    .padding(padding)
                    .background(fallbackFill, in: shape)
                    .overlay {
                        shape.strokeBorder(strokeColor, lineWidth: 0.6)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
            }
        }
    }

    private var resolvedTint: Color? {
        tint ?? palette?.accent.opacity(0.28)
    }

    private var fallbackFill: some ShapeStyle {
        if let palette {
            return AnyShapeStyle(palette.surface.opacity(0.72))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var strokeColor: Color {
        if let palette {
            return palette.primary.opacity(0.08)
        }
        return Color.primary.opacity(0.08)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct NestGlassEffectModifier: ViewModifier {
    let tint: Color?
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if let tint {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            content.glassEffect(.regular.interactive(), in: shape)
        }
    }
}

struct NestGlassScreenBackgroundModifier: ViewModifier {
    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        ZStack {
            NestLiquidBackdrop(palette: palette)
            content
        }
    }
}

struct NestGlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat

    @Environment(\.nestThemePalette) private var palette

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                content
                    .background {
                        Color.clear
                            .glassEffect(
                                glassStyle(for: palette),
                                in: shape
                            )
                    }
            } else {
                content
                    .background(fallbackFill, in: shape)
                    .overlay {
                        shape.strokeBorder(strokeColor, lineWidth: 0.5)
                    }
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func glassStyle(for palette: NestThemePalette?) -> Glass {
        if let palette {
            return .regular.tint(palette.accent.opacity(0.18))
        }
        return .regular
    }

    private var fallbackFill: some ShapeStyle {
        if let palette {
            return AnyShapeStyle(palette.surface.opacity(0.78))
        }
        return AnyShapeStyle(.thinMaterial)
    }

    private var strokeColor: Color {
        palette?.primary.opacity(0.07) ?? Color.primary.opacity(0.07)
    }
}

extension View {
    func nestGlassPanel(cornerRadius: CGFloat = 18, padding: CGFloat = 0, tint: Color? = nil) -> some View {
        modifier(NestGlassPanelModifier(cornerRadius: cornerRadius, padding: padding, tint: tint))
    }

    func nestLiquidGlassScreenBackground() -> some View {
        modifier(NestGlassScreenBackgroundModifier())
    }

    func nestGlassSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(NestGlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func nestGlassToolbarBackground(cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer {
                self.glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
    }
}
