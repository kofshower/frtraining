import SwiftUI

enum AppChartDisplayMode: String, CaseIterable, Identifiable {
    case line
    case bar
    case pie
    case flame

    static let storageKey = "fricu.chart.display.mode.v1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line:
            return L10n.choose(simplifiedChinese: "折线图", english: "Line")
        case .bar:
            return L10n.choose(simplifiedChinese: "柱状图", english: "Bar")
        case .pie:
            return L10n.choose(simplifiedChinese: "饼图", english: "Pie")
        case .flame:
            return L10n.choose(simplifiedChinese: "火焰图", english: "Flame")
        }
    }

    var symbol: String {
        switch self {
        case .line:
            return "chart.line.uptrend.xyaxis"
        case .bar:
            return "chart.bar.xaxis"
        case .pie:
            return "chart.pie"
        case .flame:
            return "flame"
        }
    }
}

private struct AppChartDisplayModeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppChartDisplayMode = .line
}

extension EnvironmentValues {
    var appChartDisplayMode: AppChartDisplayMode {
        get { self[AppChartDisplayModeEnvironmentKey.self] }
        set { self[AppChartDisplayModeEnvironmentKey.self] = newValue }
    }
}
