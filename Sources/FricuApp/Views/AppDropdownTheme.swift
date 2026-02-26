import SwiftUI

private enum AppDropdownThemeTokens {
    static let defaultWidth: CGFloat = 230
    static let cornerRadius: CGFloat = 14
    static let fieldHeight: CGFloat = 40
}

private struct AppDropdownThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var width: CGFloat?

    func body(content: Content) -> some View {
        let fill = HealthThemePalette.surfaceFill(for: colorScheme)
        let stroke = HealthThemePalette.surfaceStroke(for: colorScheme)
        content
            .labelsHidden()
            .pickerStyle(.menu)
            .menuIndicator(.hidden)
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(width: width ?? AppDropdownThemeTokens.defaultWidth, alignment: .leading)
            .frame(height: AppDropdownThemeTokens.fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: AppDropdownThemeTokens.cornerRadius)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDropdownThemeTokens.cornerRadius)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 10)
                    .allowsHitTesting(false)
            }
            .shadow(color: HealthThemePalette.softShadow(for: colorScheme), radius: 6, x: 0, y: 3)
    }
}

extension View {
    func appDropdownTheme(width: CGFloat? = nil) -> some View {
        modifier(AppDropdownThemeModifier(width: width))
    }
}
