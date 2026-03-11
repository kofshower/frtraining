import Combine
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

enum PersistedChartDisplayModeKeys {
    static let perChartPrefix = "fricu.chart.display.mode.v2."
    private static let trackedPrefixes = [
        perChartPrefix,
        "fricu.chart.real_map.",
        "fricu.chart.whoosh.",
        "fricu.chart.bike."
    ]

    static func isPersistedKey(_ key: String) -> Bool {
        trackedPrefixes.contains { key.hasPrefix($0) }
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

@MainActor
final class PerChartDisplayModeStore: ObservableObject {
    private let namespace: String
    private var defaultsChangeCancellable: AnyCancellable?
    @Published private var cache: [String: AppChartDisplayMode] = [:]

    init(namespace: String) {
        self.namespace = namespace
        defaultsChangeCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cache.removeAll()
                self?.objectWillChange.send()
            }
    }

    func mode(for chartID: String, fallback: AppChartDisplayMode) -> AppChartDisplayMode {
        if let cached = cache[chartID] {
            return cached
        }
        let key = storageKey(for: chartID)
        let resolved = UserDefaults.standard.string(forKey: key)
            .flatMap(AppChartDisplayMode.init(rawValue:))
            ?? fallback
        cache[chartID] = resolved
        return resolved
    }

    func binding(for chartID: String, fallback: AppChartDisplayMode) -> Binding<AppChartDisplayMode> {
        Binding(
            get: { [weak self] in
                self?.mode(for: chartID, fallback: fallback) ?? fallback
            },
            set: { [weak self] newValue in
                self?.setMode(newValue, for: chartID)
            }
        )
    }

    private func setMode(_ mode: AppChartDisplayMode, for chartID: String) {
        cache[chartID] = mode
        UserDefaults.standard.set(mode.rawValue, forKey: storageKey(for: chartID))
    }

    private func storageKey(for chartID: String) -> String {
        let normalized = chartID
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return "fricu.chart.display.mode.v2.\(namespace).\(normalized)"
    }
}

struct AppChartModeMenuButton: View {
    @Binding var selection: AppChartDisplayMode

    var body: some View {
        Menu {
            ForEach(AppChartDisplayMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                }
            }
        } label: {
            AppChartModeMenuLabel(symbol: selection.symbol)
        }
        .buttonStyle(.plain)
    }
}

private enum AppChartModeMenuTokens {
    static let controlHeight: CGFloat = 34
    static let cornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 10
    static let iconSize: CGFloat = 13
    static let chevronSize: CGFloat = 10
    static let iconFrameWidth: CGFloat = 15
    static let spacing: CGFloat = 7
}

struct AppChartModeMenuLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String

    var body: some View {
        HStack(spacing: AppChartModeMenuTokens.spacing) {
            Image(systemName: symbol)
                .font(.system(size: AppChartModeMenuTokens.iconSize, weight: .semibold))
                .frame(width: AppChartModeMenuTokens.iconFrameWidth, alignment: .center)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: AppChartModeMenuTokens.chevronSize, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .frame(height: AppChartModeMenuTokens.controlHeight)
        .padding(.horizontal, AppChartModeMenuTokens.horizontalPadding)
        .background(
            RoundedRectangle(
                cornerRadius: AppChartModeMenuTokens.cornerRadius,
                style: .continuous
            )
            .fill(HealthThemePalette.surfaceFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: AppChartModeMenuTokens.cornerRadius,
                style: .continuous
            )
            .strokeBorder(
                HealthThemePalette.surfaceStroke(for: colorScheme).opacity(0.88),
                lineWidth: 1
            )
        )
        .shadow(
            color: HealthThemePalette.softShadow(for: colorScheme).opacity(0.55),
            radius: 3,
            x: 0,
            y: 1
        )
    }
}
