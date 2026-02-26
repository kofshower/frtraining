import SwiftUI

enum HealthThemePalette {
    static let accent = Color(red: 0.18, green: 0.68, blue: 0.47)

    static func canvasTop(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.09, green: 0.10, blue: 0.12)
            : Color(red: 0.95, green: 0.97, blue: 0.99)
    }

    static func canvasBottom(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.06, green: 0.07, blue: 0.09)
            : Color(red: 0.91, green: 0.94, blue: 0.97)
    }

    static func surfaceFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.80)
    }

    static func surfaceStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.55)
    }

    static func softShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.08)
    }
}

struct HealthCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    HealthThemePalette.canvasTop(for: colorScheme),
                    HealthThemePalette.canvasBottom(for: colorScheme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    HealthThemePalette.accent.opacity(colorScheme == .dark ? 0.12 : 0.10),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 820
            )
        }
    }
}

struct HealthCardGroupBoxStyle: GroupBoxStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.headline.weight(.semibold))
            configuration.content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(HealthThemePalette.surfaceFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(HealthThemePalette.surfaceStroke(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: HealthThemePalette.softShadow(for: colorScheme), radius: 14, x: 0, y: 8)
    }
}

private struct HealthSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(HealthThemePalette.surfaceFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(HealthThemePalette.surfaceStroke(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: HealthThemePalette.softShadow(for: colorScheme), radius: 12, x: 0, y: 8)
    }
}

extension View {
    func healthSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(HealthSurfaceModifier(cornerRadius: cornerRadius))
    }
}

