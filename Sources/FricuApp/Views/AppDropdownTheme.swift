import SwiftUI

private enum AppDropdownThemeTokens {
    static let defaultWidth: CGFloat = 230
    static let cornerRadius: CGFloat = 14
    static let fieldHeight: CGFloat = 40
    static let compactCornerRadius: CGFloat = 12
    static let compactFieldHeight: CGFloat = 34
}

private struct AppDropdownThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var width: CGFloat?
    var compact: Bool

    func body(content: Content) -> some View {
        let fill = HealthThemePalette.surfaceFill(for: colorScheme)
        let stroke = HealthThemePalette.surfaceStroke(for: colorScheme)
        let cornerRadius = compact ? AppDropdownThemeTokens.compactCornerRadius : AppDropdownThemeTokens.cornerRadius
        let fieldHeight = compact ? AppDropdownThemeTokens.compactFieldHeight : AppDropdownThemeTokens.fieldHeight
        let font = Font.system(size: compact ? 14 : 16, weight: compact ? .medium : .semibold)
        content
            .labelsHidden()
            .pickerStyle(.menu)
            .menuIndicator(.hidden)
            .font(font)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(width: width ?? AppDropdownThemeTokens.defaultWidth, alignment: .leading)
            .frame(height: fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, compact ? 8 : 10)
                    .allowsHitTesting(false)
            }
            .shadow(color: HealthThemePalette.softShadow(for: colorScheme), radius: compact ? 3 : 6, x: 0, y: compact ? 1 : 3)
    }
}

extension View {
    func appDropdownTheme(width: CGFloat? = nil, compact: Bool = false) -> some View {
        modifier(AppDropdownThemeModifier(width: width, compact: compact))
    }
}
