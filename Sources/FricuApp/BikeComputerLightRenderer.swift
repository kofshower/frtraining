import SwiftUI

struct BikeComputerLightHeroMetric: Identifiable {
    let title: String
    let value: String
    let meta: String
    let tint: Color

    var id: String { title }
}

struct BikeComputerLightFactRow: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

struct BikeComputerLightAlert: Identifiable {
    let title: String
    let systemImage: String
    let tint: Color

    var id: String { title }
}

struct BikeComputerLightZoneRow: Identifiable {
    let name: String
    let seconds: Int
    let percent: Double
    let color: Color

    var id: String { name }
}

struct BikeComputerLightZoneGroup: Identifiable {
    let title: String
    let summary: String
    let rows: [BikeComputerLightZoneRow]
    let tint: Color

    var id: String { title }
}

struct BikeComputerLightLinePoint: Identifiable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}

struct BikeComputerLightChart: Identifiable {
    let storageKey: String
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let points: [BikeComputerLightLinePoint]
    let fixedYDomain: ClosedRange<Double>?
    let yAxisFormat: LightChartAxisFormat

    var id: String { storageKey }
}

struct BikeComputerLightRouteProfilePoint: Identifiable {
    let distanceKm: Double
    let elevationM: Double

    var id: Double { distanceKm }
}

struct BikeComputerLightRouteProfileMarker: Identifiable {
    let id: String
    let title: String
    let distanceKm: Double
    let elevationM: Double
    let tint: Color
    let prominent: Bool
}

struct LightTimeSeriesPoint: Identifiable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}

enum LightTimeSeriesRenderStyle {
    case line
    case step
    case areaLine
    case bar
}

struct LightTimeSeriesSeries: Identifiable {
    let id: String
    let title: String
    let tint: Color
    let points: [LightTimeSeriesPoint]
    let renderStyle: LightTimeSeriesRenderStyle
    let dashed: Bool

    init(
        id: String,
        title: String,
        tint: Color,
        points: [LightTimeSeriesPoint],
        renderStyle: LightTimeSeriesRenderStyle,
        dashed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.tint = tint
        self.points = points
        self.renderStyle = renderStyle
        self.dashed = dashed
    }
}

struct LightTimeSeriesBand: Identifiable {
    let id: String
    let label: String?
    let lower: Double
    let upper: Double
    let tint: Color
    let opacity: Double

    init(
        id: String,
        label: String? = nil,
        lower: Double,
        upper: Double,
        tint: Color,
        opacity: Double
    ) {
        self.id = id
        self.label = label
        self.lower = lower
        self.upper = upper
        self.tint = tint
        self.opacity = opacity
    }
}

struct LightTimeSeriesRule: Identifiable {
    let id: String
    let value: Double
    let tint: Color
    let dashed: Bool
}

struct LightTimeSeriesCardModel {
    let storageKey: String
    let title: String
    let valueText: String
    let detailText: String
    let footerNotes: [LightChartNote]
    let yDomain: ClosedRange<Double>
    let yAxisFormat: LightChartAxisFormat
    let series: [LightTimeSeriesSeries]
    let bands: [LightTimeSeriesBand]
    let rules: [LightTimeSeriesRule]
    let tint: Color
    let plotHeight: CGFloat
}

struct LightCategoricalPoint: Identifiable {
    let id: String
    let label: String
    let value: Double
    let tint: Color
}

struct LightCategoricalCardModel {
    let storageKey: String
    let title: String
    let valueText: String
    let detailText: String
    let footerNotes: [LightChartNote]
    let yDomain: ClosedRange<Double>?
    let yAxisFormat: LightChartAxisFormat
    let tint: Color
    let points: [LightCategoricalPoint]
    let plotHeight: CGFloat
}

struct LightScatterXYPoint: Identifiable {
    let id: String
    let x: Double
    let y: Double
}

struct LightScatterSample: Identifiable {
    let id: String
    let x: Double
    let y: Double
    let tint: Color
    let size: CGFloat
}

struct LightScatterCurve: Identifiable {
    let id: String
    let tint: Color
    let points: [LightScatterXYPoint]
    let dashed: Bool
}

struct LightScatterRule: Identifiable {
    enum Axis {
        case x
        case y
    }

    let id: String
    let axis: Axis
    let value: Double
    let tint: Color
    let dashed: Bool
}

struct LightScatterBand: Identifiable {
    let id: String
    let lowerX: Double
    let upperX: Double
    let lowerY: Double
    let upperY: Double
    let tint: Color
    let opacity: Double
}

struct LightScatterCardModel {
    let storageKey: String
    let title: String
    let valueText: String
    let detailText: String
    let footerNotes: [LightChartNote]
    let tint: Color
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>
    let yAxisFormat: LightChartAxisFormat
    let bands: [LightScatterBand]
    let samples: [LightScatterSample]
    let curves: [LightScatterCurve]
    let rules: [LightScatterRule]
    let plotHeight: CGFloat
}

enum LightChartLegendStyle {
    case solid
    case dashed
}

struct LightChartLegendItem: Identifiable {
    let label: String
    let tint: Color
    let style: LightChartLegendStyle

    var id: String { label }
}

enum LightChartNoteStyle {
    case standard
    case monospaced
}

struct LightChartNote: Identifiable {
    let text: String
    let style: LightChartNoteStyle

    var id: String { "\(style)-\(text)" }
}

enum LightChartScaleMode: String, CaseIterable, Identifiable {
    case auto
    case fixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return L10n.choose(simplifiedChinese: "自动", english: "Auto")
        case .fixed:
            return L10n.choose(simplifiedChinese: "固定", english: "Fixed")
        }
    }

    static func storageKey(for chartKey: String) -> String {
        "\(PersistedChartDisplayModeKeys.perChartScalePrefix)\(chartKey)"
    }
}

enum LightChartAxisFormat {
    case number(decimals: Int = 0, suffix: String = "")
    case duration

    func string(for value: Double) -> String {
        switch self {
        case let .number(decimals, suffix):
            let numberText: String
            if decimals > 0 {
                numberText = String(format: "%.\(decimals)f", value)
            } else {
                numberText = String(Int(value.rounded()))
            }
            guard !suffix.isEmpty else { return numberText }
            if suffix == "%" {
                return "\(numberText)%"
            }
            return "\(numberText) \(suffix)"
        case .duration:
            let total = max(0, Int(value.rounded()))
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let seconds = total % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

struct BikeComputerLightDashboardModel {
    let title: String
    let subtitle: String
    let headlineItems: [BikeComputerLightFactRow]
    let heroMetrics: [BikeComputerLightHeroMetric]
    let summaryRows: [BikeComputerLightFactRow]
    let alerts: [BikeComputerLightAlert]
    let zoneGroups: [BikeComputerLightZoneGroup]
    let charts: [BikeComputerLightChart]
}

enum BikeComputerChartDisplayMode: String, CaseIterable, Identifiable {
    case line
    case area
    case bar
    case stackedBar
    case scatter
    case step
    case lollipop
    case pie
    case donut
    case flame

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line:
            return L10n.choose(simplifiedChinese: "折线", english: "Line")
        case .area:
            return L10n.choose(simplifiedChinese: "面积", english: "Area")
        case .bar:
            return L10n.choose(simplifiedChinese: "柱状", english: "Bar")
        case .stackedBar:
            return L10n.choose(simplifiedChinese: "堆叠柱", english: "Stacked")
        case .scatter:
            return L10n.choose(simplifiedChinese: "散点", english: "Scatter")
        case .step:
            return L10n.choose(simplifiedChinese: "阶梯", english: "Step")
        case .lollipop:
            return L10n.choose(simplifiedChinese: "棒棒糖", english: "Lollipop")
        case .pie:
            return L10n.choose(simplifiedChinese: "饼图", english: "Pie")
        case .donut:
            return L10n.choose(simplifiedChinese: "环图", english: "Donut")
        case .flame:
            return L10n.choose(simplifiedChinese: "火焰", english: "Flame")
        }
    }

    var symbol: String {
        switch self {
        case .line:
            return "chart.line.uptrend.xyaxis"
        case .area:
            return "chart.xyaxis.line"
        case .bar:
            return "chart.bar.xaxis"
        case .stackedBar:
            return "square.stack.3d.up.fill"
        case .scatter:
            return "circle.grid.cross"
        case .step:
            return "stairs"
        case .lollipop:
            return "chart.bar.doc.horizontal"
        case .pie:
            return "chart.pie"
        case .donut:
            return "smallcircle.filled.circle"
        case .flame:
            return "flame"
        }
    }

    var isCircular: Bool {
        self == .pie || self == .donut
    }
}

struct ChartModeMenuButton: View {
    @Binding var selection: BikeComputerChartDisplayMode

    var body: some View {
        Menu {
            ForEach(BikeComputerChartDisplayMode.allCases) { mode in
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

struct BikeComputerLightDashboardView: View {
    let model: BikeComputerLightDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits {
                HStack(alignment: .top, spacing: 16) {
                    heroSection
                    summaryCard.frame(width: 360)
                }
                VStack(alignment: .leading, spacing: 16) {
                    heroSection
                    summaryCard
                }
            }

            if !model.alerts.isEmpty {
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(model.alerts) { alert in
                        Label(alert.title, systemImage: alert.systemImage)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(alert.tint.opacity(0.12), in: Capsule())
                            .foregroundStyle(alert.tint)
                    }
                }
            }

            if !model.zoneGroups.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(model.zoneGroups) { group in
                        BikeComputerLightZoneGroupView(group: group)
                    }
                }
            }

            if !model.charts.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(model.charts) { chart in
                        BikeComputerLightChartCard(chart: chart)
                    }
                }
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    LightChartVisualStyle.surfaceBackground,
                    LightChartVisualStyle.surfaceBackgroundAlt
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LightChartVisualStyle.controlBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(LightChartVisualStyle.ink)
                    Text(model.subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LightChartVisualStyle.secondaryInk)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(model.headlineItems) { item in
                        HStack(spacing: 8) {
                            Text(item.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LightChartVisualStyle.secondaryInk)
                            Text(item.value)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(LightChartVisualStyle.ink)
                        }
                    }
                }
            }

            metricGrid
        }
        .padding(20)
        .background(LightChartVisualStyle.cardBackgroundEmphasis, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var metricGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(model.heroMetrics) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    Text(metric.title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(LightChartVisualStyle.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(metric.meta)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                .padding(14)
                .background(metric.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(metric.tint.opacity(0.22), lineWidth: 1)
                )
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.summaryRows.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.value)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.18))
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 11)
                if index < model.summaryRows.count - 1 {
                    Divider().opacity(0.35)
                }
            }
        }
        .padding(18)
        .background(LightChartVisualStyle.cardBackgroundEmphasis, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct BikeComputerLightZoneGroupView: View {
    let group: BikeComputerLightZoneGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LightChartVisualStyle.strokeTint(group.tint))
            Text(group.summary)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(LightChartVisualStyle.secondaryInk)
                .lineLimit(2)
            VStack(spacing: 8) {
                ForEach(group.rows) { row in
                    HStack(spacing: 8) {
                        Text(row.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LightChartVisualStyle.ink)
                            .frame(width: 28, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(LightChartVisualStyle.gridStroke)
                                Capsule()
                                    .fill(row.color)
                                    .frame(width: geo.size.width * min(max(row.percent, 0), 1))
                            }
                        }
                        .frame(height: 8)
                        Text(row.seconds.asDuration)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(LightChartVisualStyle.secondaryInk)
                            .frame(width: 54, alignment: .trailing)
                        Text(String(format: "%.0f%%", row.percent * 100))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(LightChartVisualStyle.secondaryInk)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .frame(height: 16)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LightChartVisualStyle.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct BikeComputerLightChartCard: View {
    @State private var mode: BikeComputerChartDisplayMode
    @State private var scaleMode: LightChartScaleMode

    let chart: BikeComputerLightChart

    init(chart: BikeComputerLightChart) {
        self.chart = chart
        let stored = UserDefaults.standard.string(forKey: chart.storageKey)
        _mode = State(initialValue: BikeComputerChartDisplayMode(rawValue: stored ?? "") ?? .line)
        let storedScale = UserDefaults.standard.string(forKey: LightChartScaleMode.storageKey(for: chart.storageKey))
        _scaleMode = State(initialValue: LightChartScaleMode(rawValue: storedScale ?? "") ?? .auto)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(chart.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LightChartVisualStyle.secondaryInk)
                Spacer()
                HStack(spacing: 8) {
                    LightChartScaleToggle(selection: $scaleMode)
                    ChartModeMenuButton(selection: $mode)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(chart.value)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LightChartVisualStyle.ink)
                Spacer()
                Text(chart.detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LightChartVisualStyle.secondaryInk)
                    .multilineTextAlignment(.trailing)
            }

            BikeComputerLightChartPlot(
                points: chart.points,
                tint: chart.tint,
                mode: mode,
                scaleMode: scaleMode,
                fixedYDomain: chart.fixedYDomain,
                yAxisFormat: chart.yAxisFormat
            )
            .frame(height: 118)
        }
        .padding(16)
        .background(LightChartVisualStyle.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LightChartVisualStyle.borderTint(chart.tint), lineWidth: 1)
        )
        .onChange(of: mode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: chart.storageKey)
        }
        .onChange(of: scaleMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: LightChartScaleMode.storageKey(for: chart.storageKey))
        }
    }
}

struct BikeComputerLightRouteProfileView: View {
    let title: String
    let distanceAxisLabel: String
    let elevationAxisLabel: String
    let points: [BikeComputerLightRouteProfilePoint]
    let markers: [BikeComputerLightRouteProfileMarker]
    let tint: Color
    let mode: AppChartDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LightChartVisualStyle.secondaryInk)
                Spacer()
                Text("\(distanceAxisLabel) · \(elevationAxisLabel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LightChartVisualStyle.secondaryInk)
            }

            BikeComputerLightRouteProfilePlot(
                points: points,
                markers: markers,
                tint: tint,
                mode: mode
            )
            .frame(height: 170)
        }
        .padding(16)
        .background(LightChartVisualStyle.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LightChartVisualStyle.borderTint(tint), lineWidth: 1)
        )
    }
}

struct LightTimeSeriesCard: View {
    let model: LightTimeSeriesCardModel
    @Binding var mode: AppChartDisplayMode
    @State private var scaleMode: LightChartScaleMode

    init(model: LightTimeSeriesCardModel, mode: Binding<AppChartDisplayMode>) {
        self.model = model
        _mode = mode
        let storedScale = UserDefaults.standard.string(forKey: LightChartScaleMode.storageKey(for: model.storageKey))
        _scaleMode = State(initialValue: LightChartScaleMode(rawValue: storedScale ?? "") ?? .auto)
    }

    private var legendItems: [LightChartLegendItem] {
        guard model.series.count > 1 else { return [] }
        return model.series.map { series in
            LightChartLegendItem(
                label: series.title,
                tint: LightChartVisualStyle.strokeTint(series.tint),
                style: series.dashed ? .dashed : .solid
            )
        }
    }

    private var bandLegendItems: [LightChartLegendItem] {
        model.bands.compactMap { band in
            guard let label = band.label, !label.isEmpty else { return nil }
            return LightChartLegendItem(
                label: label,
                tint: band.tint.opacity(max(0.25, band.opacity + 0.12)),
                style: .solid
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                    Text(model.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LightChartVisualStyle.secondaryInk)
                Spacer()
                HStack(spacing: 8) {
                    LightChartScaleToggle(selection: $scaleMode)
                    AppChartModeMenuButton(selection: $mode)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(model.valueText)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LightChartVisualStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text(model.detailText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LightChartVisualStyle.secondaryInk)
                    .multilineTextAlignment(.trailing)
            }

            LightTimeSeriesPlot(
                model: model,
                mode: mode,
                scaleMode: scaleMode
            )
            .frame(height: model.plotHeight)

            if !legendItems.isEmpty {
                LightChartLegendStrip(items: legendItems)
            }

            if !bandLegendItems.isEmpty {
                LightChartLegendStrip(items: bandLegendItems)
            }

            if !model.footerNotes.isEmpty {
                LightChartNotesBlock(notes: model.footerNotes)
            }
        }
        .padding(16)
        .background(LightChartVisualStyle.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LightChartVisualStyle.borderTint(model.tint), lineWidth: 1)
        )
        .onChange(of: scaleMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: LightChartScaleMode.storageKey(for: model.storageKey))
        }
    }
}

struct LightCategoricalCard: View {
    let model: LightCategoricalCardModel
    @Binding var mode: AppChartDisplayMode
    @State private var scaleMode: LightChartScaleMode

    init(model: LightCategoricalCardModel, mode: Binding<AppChartDisplayMode>) {
        self.model = model
        _mode = mode
        let storedScale = UserDefaults.standard.string(forKey: LightChartScaleMode.storageKey(for: model.storageKey))
        _scaleMode = State(initialValue: LightChartScaleMode(rawValue: storedScale ?? "") ?? .auto)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                    Text(model.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LightChartVisualStyle.secondaryInk)
                Spacer()
                HStack(spacing: 8) {
                    LightChartScaleToggle(selection: $scaleMode)
                    AppChartModeMenuButton(selection: $mode)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(model.valueText)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LightChartVisualStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text(model.detailText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LightChartVisualStyle.secondaryInk)
                    .multilineTextAlignment(.trailing)
            }

            LightCategoricalPlot(model: model, mode: mode, scaleMode: scaleMode)
                .frame(height: model.plotHeight)

            if !model.footerNotes.isEmpty {
                LightChartNotesBlock(notes: model.footerNotes)
            }
        }
        .padding(16)
        .background(LightChartVisualStyle.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LightChartVisualStyle.borderTint(model.tint), lineWidth: 1)
        )
        .onChange(of: scaleMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: LightChartScaleMode.storageKey(for: model.storageKey))
        }
    }
}

struct LightScatterCard: View {
    let model: LightScatterCardModel
    @Binding var mode: AppChartDisplayMode
    @State private var scaleMode: LightChartScaleMode

    init(model: LightScatterCardModel, mode: Binding<AppChartDisplayMode>) {
        self.model = model
        _mode = mode
        let storedScale = UserDefaults.standard.string(forKey: LightChartScaleMode.storageKey(for: model.storageKey))
        _scaleMode = State(initialValue: LightChartScaleMode(rawValue: storedScale ?? "") ?? .auto)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                    Text(model.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LightChartVisualStyle.secondaryInk)
                Spacer()
                HStack(spacing: 8) {
                    LightChartScaleToggle(selection: $scaleMode)
                    AppChartModeMenuButton(selection: $mode)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(model.valueText)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LightChartVisualStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text(model.detailText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LightChartVisualStyle.secondaryInk)
                    .multilineTextAlignment(.trailing)
            }

            LightScatterPlot(model: model, mode: mode, scaleMode: scaleMode)
                .frame(height: model.plotHeight)

            if !model.footerNotes.isEmpty {
                LightChartNotesBlock(notes: model.footerNotes)
            }
        }
        .padding(16)
        .background(LightChartVisualStyle.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LightChartVisualStyle.borderTint(model.tint), lineWidth: 1)
        )
        .onChange(of: scaleMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: LightChartScaleMode.storageKey(for: model.storageKey))
        }
    }
}

struct LightChartLegendStrip: View {
    let items: [LightChartLegendItem]

    var body: some View {
        FlowLayout(horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Group {
                        if item.style == .solid {
                            Capsule()
                                .fill(item.tint)
                        } else {
                            DashedLegendLine()
                                .stroke(item.tint, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        }
                    }
                    .frame(width: 20, height: 6)

                    Text(item.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .font(.caption2)
                .foregroundStyle(LightChartVisualStyle.secondaryInk)
            }
        }
    }
}

struct LightChartNotesBlock: View {
    let notes: [LightChartNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(notes) { note in
                Text(note.text)
                    .font(note.style == .monospaced ? .caption2.monospaced() : .caption2)
                    .foregroundStyle(LightChartVisualStyle.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LightChartScaleToggle: View {
    @Binding var selection: LightChartScaleMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LightChartScaleMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == mode ? Color.white : LightChartVisualStyle.secondaryInk)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == mode ? LightChartVisualStyle.controlSelected : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(LightChartVisualStyle.controlBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(LightChartVisualStyle.controlBorder, lineWidth: 1)
        )
    }
}

private struct LightChartBoundsOverlay: View {
    let maxText: String
    let minText: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(maxText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(LightChartVisualStyle.tertiaryInk)
            Spacer()
            Text(minText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(LightChartVisualStyle.tertiaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .allowsHitTesting(false)
    }
}

private enum LightChartVisualStyle {
    static let surfaceBackground = Color(red: 0.94, green: 0.92, blue: 0.87)
    static let surfaceBackgroundAlt = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let cardBackground = Color(red: 0.975, green: 0.968, blue: 0.948).opacity(0.94)
    static let cardBackgroundEmphasis = Color(red: 0.985, green: 0.978, blue: 0.958).opacity(0.96)
    static let ink = Color(red: 0.10, green: 0.14, blue: 0.19)
    static let secondaryInk = Color(red: 0.38, green: 0.40, blue: 0.41)
    static let tertiaryInk = Color(red: 0.56, green: 0.58, blue: 0.58)
    static let gridStroke = Color(red: 0.41, green: 0.42, blue: 0.40).opacity(0.11)
    static let controlBackground = Color(red: 0.99, green: 0.985, blue: 0.968).opacity(0.9)
    static let controlBorder = Color(red: 0.58, green: 0.50, blue: 0.38).opacity(0.30)
    static let controlSelected = Color(red: 0.07, green: 0.13, blue: 0.20)

    static func borderTint(_ tint: Color) -> Color {
        tinted(tint, amount: 0.22).opacity(0.42)
    }

    static func plotBackground(_ tint: Color) -> Color {
        tinted(tint, amount: 0.12).opacity(0.22)
    }

    static func strokeTint(_ tint: Color) -> Color {
        tinted(tint, amount: 0.72)
    }

    static func secondaryStrokeTint(_ tint: Color) -> Color {
        tinted(tint, amount: 0.58)
    }

    static func pointTint(_ tint: Color) -> Color {
        tinted(tint, amount: 0.68)
    }

    static func ruleTint(_ tint: Color) -> Color {
        tinted(tint, amount: 0.34)
    }

    static func areaGradient(for tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [tinted(tint, amount: 0.24), tinted(tint, amount: 0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func barFill(_ tint: Color) -> AnyShapeStyle {
        AnyShapeStyle(tinted(tint, amount: 0.56))
    }

    static func flameFill(_ tint: Color) -> AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.80, blue: 0.63).opacity(0.56),
                    Color(red: 0.88, green: 0.70, blue: 0.52).opacity(0.58),
                    tinted(tint, amount: 0.56)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    private static func tinted(_ tint: Color, amount: Double) -> Color {
        tint.opacity(amount)
    }
}

private struct DashedLegendLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct BikeComputerLightChartPlot: View {
    let points: [BikeComputerLightLinePoint]
    let tint: Color
    let mode: BikeComputerChartDisplayMode
    let scaleMode: LightChartScaleMode
    let fixedYDomain: ClosedRange<Double>?
    let yAxisFormat: LightChartAxisFormat

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if points.count < 2 {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.08))
                    .overlay(
                        Text(L10n.choose(simplifiedChinese: "等待数据", english: "Waiting"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            } else if mode.isCircular {
                BikeComputerLightCircularPlot(
                    points: points,
                    tint: tint,
                    isDonut: mode == .donut
                )
            } else {
                let yDomain = BikeComputerLightChartDomainResolver.yDomain(
                    points: points,
                    fixedYDomain: fixedYDomain,
                    scaleMode: scaleMode
                )
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LightChartVisualStyle.plotBackground(tint))
                    BikeComputerLightGrid()
                        .stroke(LightChartVisualStyle.gridStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    BikeComputerLightCartesianPlot(
                        points: points,
                        tint: tint,
                        mode: mode,
                        size: size,
                        yDomain: yDomain
                    )
                    LightChartBoundsOverlay(
                        maxText: yAxisFormat.string(for: yDomain.upperBound),
                        minText: yAxisFormat.string(for: yDomain.lowerBound)
                    )
                }
            }
        }
    }
}

private struct LightTimeSeriesPlot: View {
    let model: LightTimeSeriesCardModel
    let mode: AppChartDisplayMode
    let scaleMode: LightChartScaleMode

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if model.series.allSatisfy({ $0.points.isEmpty }) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(model.tint.opacity(0.08))
                    .overlay(
                        Text(L10n.choose(simplifiedChinese: "等待数据", english: "Waiting"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            } else if mode == .pie {
                LightTimeSeriesCircularPlot(model: model)
            } else {
                let yDomain = LightTimeSeriesDomainResolver.yDomain(for: model, scaleMode: scaleMode)
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LightChartVisualStyle.plotBackground(model.tint))
                    BikeComputerLightGrid()
                        .stroke(LightChartVisualStyle.gridStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    LightTimeSeriesCartesianPlot(
                        model: model,
                        mode: mode,
                        size: size,
                        yDomain: yDomain
                    )
                    LightChartBoundsOverlay(
                        maxText: model.yAxisFormat.string(for: yDomain.upperBound),
                        minText: model.yAxisFormat.string(for: yDomain.lowerBound)
                    )
                }
            }
        }
    }
}

private struct LightCategoricalPlot: View {
    let model: LightCategoricalCardModel
    let mode: AppChartDisplayMode
    let scaleMode: LightChartScaleMode

    var body: some View {
        GeometryReader { proxy in
            if model.points.isEmpty {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(model.tint.opacity(0.08))
                    .overlay(
                        Text(L10n.choose(simplifiedChinese: "等待数据", english: "Waiting"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            } else if mode == .pie {
                LightCategoricalCircularPlot(model: model)
            } else {
                let yDomain = LightCategoricalDomainResolver.yDomain(for: model, scaleMode: scaleMode)
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LightChartVisualStyle.plotBackground(model.tint))
                    BikeComputerLightGrid()
                        .stroke(LightChartVisualStyle.gridStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    LightCategoricalCartesianPlot(model: model, mode: mode, size: proxy.size, yDomain: yDomain)
                    LightChartBoundsOverlay(
                        maxText: model.yAxisFormat.string(for: yDomain.upperBound),
                        minText: model.yAxisFormat.string(for: yDomain.lowerBound)
                    )
                }
            }
        }
    }
}

private struct LightScatterPlot: View {
    let model: LightScatterCardModel
    let mode: AppChartDisplayMode
    let scaleMode: LightChartScaleMode

    var body: some View {
        GeometryReader { proxy in
            if model.samples.isEmpty && model.curves.allSatisfy({ $0.points.isEmpty }) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(model.tint.opacity(0.08))
                    .overlay(
                        Text(L10n.choose(simplifiedChinese: "等待数据", english: "Waiting"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            } else if mode == .pie {
                LightScatterCircularPlot(model: model)
            } else {
                let domains = LightScatterDomainResolver.domains(for: model, scaleMode: scaleMode)
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LightChartVisualStyle.plotBackground(model.tint))
                    BikeComputerLightGrid()
                        .stroke(LightChartVisualStyle.gridStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    LightScatterCartesianPlot(model: model, mode: mode, size: proxy.size, xDomain: domains.x, yDomain: domains.y)
                    LightChartBoundsOverlay(
                        maxText: model.yAxisFormat.string(for: domains.y.upperBound),
                        minText: model.yAxisFormat.string(for: domains.y.lowerBound)
                    )
                }
            }
        }
    }
}

private struct LightTimeSeriesCircularPlot: View {
    let model: LightTimeSeriesCardModel

    private struct Slice: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let tint: Color
        let opacity: Double
    }

    private var slices: [Slice] {
        let values: [(String, Double, Color)] = {
            if model.series.count > 1 {
                return model.series.compactMap { series in
                    guard let latest = series.points.last?.value else { return nil }
                    return (series.id, abs(latest), series.tint)
                }
            }
            guard let series = model.series.first else { return [] }
            let recent = series.points.suffix(24)
            return recent.enumerated().map { index, point in
                ("\(series.id)-\(index)", abs(point.value), series.tint.opacity(0.35 + (Double(index + 1) / Double(max(recent.count, 1))) * 0.55))
            }
        }()
        let total = max(0.001, values.map(\.1).reduce(0, +))
        var cursor = 0.0
        return values.map { id, value, tint in
            let fraction = value / total
            let slice = Slice(id: id, start: cursor, end: cursor + fraction, tint: tint, opacity: 1)
            cursor += fraction
            return slice
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let frame = CGRect(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2,
                width: side,
                height: side
            )
            ZStack {
                Circle()
                    .fill(model.tint.opacity(0.08))
                ForEach(slices) { slice in
                    BikeComputerSectorShape(
                        startFraction: slice.start,
                        endFraction: slice.end,
                        innerRatio: 0.56
                    )
                    .fill(slice.tint)
                }
                Circle()
                    .stroke(model.tint.opacity(0.22), lineWidth: 1)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }
}

private struct LightCategoricalCircularPlot: View {
    let model: LightCategoricalCardModel

    private struct Slice: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let tint: Color
    }

    private var slices: [Slice] {
        let total = max(0.001, model.points.map(\.value).reduce(0, +))
        var cursor = 0.0
        return model.points.map { point in
            let fraction = max(0, point.value) / total
            let slice = Slice(id: point.id, start: cursor, end: cursor + fraction, tint: point.tint)
            cursor += fraction
            return slice
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let frame = CGRect(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2,
                width: side,
                height: side
            )
            ZStack {
                Circle().fill(model.tint.opacity(0.08))
                ForEach(slices) { slice in
                    BikeComputerSectorShape(startFraction: slice.start, endFraction: slice.end, innerRatio: 0.56)
                        .fill(slice.tint)
                }
                Circle()
                    .stroke(model.tint.opacity(0.22), lineWidth: 1)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }
}

private struct LightScatterCircularPlot: View {
    let model: LightScatterCardModel

    private struct Slice: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let tint: Color
    }

    private var slices: [Slice] {
        let total = max(0.001, model.samples.map { max(0, $0.y) }.reduce(0, +))
        var cursor = 0.0
        return model.samples.map { point in
            let fraction = max(0, point.y) / total
            let slice = Slice(id: point.id, start: cursor, end: cursor + fraction, tint: point.tint)
            cursor += fraction
            return slice
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let frame = CGRect(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2,
                width: side,
                height: side
            )
            ZStack {
                Circle().fill(model.tint.opacity(0.08))
                ForEach(slices) { slice in
                    BikeComputerSectorShape(startFraction: slice.start, endFraction: slice.end, innerRatio: 0.56)
                        .fill(slice.tint)
                }
                Circle()
                    .stroke(model.tint.opacity(0.22), lineWidth: 1)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }
}

private struct LightTimeSeriesCartesianPlot: View {
    let model: LightTimeSeriesCardModel
    let mode: AppChartDisplayMode
    let size: CGSize
    let yDomain: ClosedRange<Double>

    private var plotWidth: CGFloat { max(1, size.width - 12) }
    private var plotHeight: CGFloat { max(1, size.height - 16) }
    private var baselineY: CGFloat {
        yPosition(for: 0)
    }

    var body: some View {
        ZStack {
            ForEach(model.bands) { band in
                bandView(band)
            }

            ForEach(model.rules) { rule in
                ruleView(rule)
            }

            switch mode {
            case .line:
                ForEach(model.series) { series in
                    lineSeriesView(series)
                }
            case .bar, .flame:
                if let primary = model.series.first {
                    barSeriesView(primary, flame: mode == .flame)
                }
            case .pie:
                EmptyView()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func lineSeriesView(_ series: LightTimeSeriesSeries) -> some View {
        let segments = lineSegments(for: series.points)
        switch series.renderStyle {
        case .areaLine:
            ForEach(Array(segments.enumerated()), id: \.offset) { _, samples in
                BikeComputerAreaShape(samples: samples)
                    .fill(LightChartVisualStyle.areaGradient(for: series.tint))
            }
            ForEach(Array(segments.enumerated()), id: \.offset) { _, samples in
                BikeComputerLineShape(samples: samples)
                    .stroke(
                        LightChartVisualStyle.strokeTint(series.tint),
                        style: LightTimeSeriesRendererStyle.lineStrokeStyle(width: 2.3, dashed: series.dashed)
                    )
            }
        case .step:
            ForEach(Array(segments.enumerated()), id: \.offset) { _, samples in
                BikeComputerStepShape(samples: samples)
                    .stroke(
                        LightChartVisualStyle.secondaryStrokeTint(series.tint),
                        style: LightTimeSeriesRendererStyle.lineStrokeStyle(width: 2.1, dashed: series.dashed)
                    )
            }
        case .line, .bar:
            ForEach(Array(segments.enumerated()), id: \.offset) { _, samples in
                BikeComputerLineShape(samples: samples)
                    .stroke(
                        LightChartVisualStyle.strokeTint(series.tint),
                        style: LightTimeSeriesRendererStyle.lineStrokeStyle(width: 2.1, dashed: series.dashed)
                    )
            }
        }
    }

    @ViewBuilder
    private func barSeriesView(_ series: LightTimeSeriesSeries, flame: Bool) -> some View {
        let samples = pointPositions(for: series.points)
        let barWidth = max(3, plotWidth / CGFloat(max(series.points.count, 1)))
        ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
            let valueY = sample.y
            let barHeight = abs(baselineY - valueY)
            let centerY = min(baselineY, valueY) + barHeight / 2
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    flame
                        ? LightChartVisualStyle.flameFill(series.tint)
                        : LightChartVisualStyle.barFill(series.tint)
                )
                .frame(width: barWidth, height: max(3, barHeight))
                .position(x: sample.x, y: centerY)
        }
    }

    private func bandView(_ band: LightTimeSeriesBand) -> some View {
        let top = yPosition(for: band.upper)
        let bottom = yPosition(for: band.lower)
        return RoundedRectangle(cornerRadius: 0, style: .continuous)
            .fill(band.tint.opacity(band.opacity))
            .frame(width: plotWidth, height: max(2, bottom - top))
            .position(x: 6 + plotWidth / 2, y: top + max(2, bottom - top) / 2)
    }

    private func ruleView(_ rule: LightTimeSeriesRule) -> some View {
        Path { path in
            let y = yPosition(for: rule.value)
            path.move(to: CGPoint(x: 6, y: y))
            path.addLine(to: CGPoint(x: 6 + plotWidth, y: y))
        }
        .stroke(
            LightChartVisualStyle.ruleTint(rule.tint),
            style: StrokeStyle(lineWidth: 1, dash: rule.dashed ? [4, 4] : [])
        )
    }

    private func lineSegments(for points: [LightTimeSeriesPoint]) -> [[CGPoint]] {
        LightTimeSeriesLayout.segments(for: points, in: size, yDomain: yDomain)
    }

    private func pointPositions(for points: [LightTimeSeriesPoint]) -> [CGPoint] {
        LightTimeSeriesLayout.positions(for: points, in: size, yDomain: yDomain)
            .filter { $0.x.isFinite && $0.y.isFinite }
    }

    private func yPosition(for value: Double) -> CGFloat {
        LightTimeSeriesLayout.yPosition(for: value, in: size, yDomain: yDomain)
    }
}

private struct LightCategoricalCartesianPlot: View {
    let model: LightCategoricalCardModel
    let mode: AppChartDisplayMode
    let size: CGSize
    let yDomain: ClosedRange<Double>

    private var plotWidth: CGFloat { max(1, size.width - 12) }
    private var plotHeight: CGFloat { max(1, size.height - 16) }

    var body: some View {
        let samples = positions
        ZStack {
            if mode == .line {
                BikeComputerLineShape(samples: samples)
                    .stroke(LightChartVisualStyle.strokeTint(model.tint), style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    Circle()
                        .fill(LightChartVisualStyle.pointTint(model.points[index].tint))
                        .frame(width: 8, height: 8)
                        .position(sample)
                }
            } else {
                let barWidth = max(8, plotWidth / CGFloat(max(model.points.count, 1)) * 0.58)
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    let barHeight = plotHeight - sample.y + 8
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            mode == .flame
                                ? LightChartVisualStyle.flameFill(model.points[index].tint)
                                : LightChartVisualStyle.barFill(model.points[index].tint)
                        )
                        .frame(width: barWidth, height: max(3, barHeight))
                        .position(x: sample.x, y: sample.y + max(3, barHeight) / 2)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private var positions: [CGPoint] {
        guard !model.points.isEmpty else { return [] }
        if model.points.count == 1 {
            let y = yPosition(for: model.points[0].value)
            return [CGPoint(x: 6 + plotWidth / 2, y: y)]
        }
        return model.points.enumerated().map { index, point in
            let x = CGFloat(index) / CGFloat(max(model.points.count - 1, 1)) * plotWidth + 6
            let y = yPosition(for: point.value)
            return CGPoint(x: x, y: y)
        }
    }

    private func yPosition(for value: Double) -> CGFloat {
        let clamped = min(max(value, yDomain.lowerBound), yDomain.upperBound)
        let ratio = (clamped - yDomain.lowerBound) / max(yDomain.upperBound - yDomain.lowerBound, 0.001)
        return (1 - ratio) * plotHeight + 8
    }
}

private struct LightScatterCartesianPlot: View {
    let model: LightScatterCardModel
    let mode: AppChartDisplayMode
    let size: CGSize
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>

    private var plotWidth: CGFloat { max(1, size.width - 12) }
    private var plotHeight: CGFloat { max(1, size.height - 16) }

    var body: some View {
        ZStack {
            ForEach(model.bands) { band in
                bandView(band)
            }

            ForEach(model.rules) { rule in
                ruleView(rule)
            }

            ForEach(model.curves) { curve in
                let samples = curve.points.map(position(for:))
                BikeComputerLineShape(samples: samples)
                    .stroke(
                        LightChartVisualStyle.strokeTint(curve.tint),
                        style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round, dash: curve.dashed ? [4, 4] : [])
                    )
            }

            if mode == .line {
                ForEach(model.samples) { sample in
                    Circle()
                        .fill(LightChartVisualStyle.pointTint(sample.tint))
                        .frame(width: sample.size, height: sample.size)
                        .position(position(for: sample.x, y: sample.y))
                }
            } else {
                let barWidth = max(4, plotWidth / CGFloat(max(model.samples.count, 1)) * 0.4)
                ForEach(model.samples) { sample in
                    let point = position(for: sample.x, y: sample.y)
                    let barHeight = plotHeight - point.y + 8
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            mode == .flame
                                ? LightChartVisualStyle.flameFill(sample.tint)
                                : LightChartVisualStyle.barFill(sample.tint)
                        )
                        .frame(width: barWidth, height: max(3, barHeight))
                        .position(x: point.x, y: point.y + max(3, barHeight) / 2)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private func bandView(_ band: LightScatterBand) -> some View {
        let rect = LightScatterRendererLayout.bandRect(
            for: band,
            size: size,
            xDomain: xDomain,
            yDomain: yDomain
        )
        return RoundedRectangle(cornerRadius: 0, style: .continuous)
            .fill(band.tint.opacity(band.opacity))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func position(for point: LightScatterXYPoint) -> CGPoint {
        position(for: point.x, y: point.y)
    }

    private func position(for x: Double, y: Double) -> CGPoint {
        let clampedX = min(max(x, xDomain.lowerBound), xDomain.upperBound)
        let xRatio = (clampedX - xDomain.lowerBound) / max(xDomain.upperBound - xDomain.lowerBound, 0.001)
        let clampedY = min(max(y, yDomain.lowerBound), yDomain.upperBound)
        let yRatio = (clampedY - yDomain.lowerBound) / max(yDomain.upperBound - yDomain.lowerBound, 0.001)
        return CGPoint(
            x: CGFloat(xRatio) * plotWidth + 6,
            y: CGFloat(1 - yRatio) * plotHeight + 8
        )
    }

    private func ruleView(_ rule: LightScatterRule) -> some View {
        Path { path in
            switch rule.axis {
            case .x:
                let point = position(for: rule.value, y: yDomain.lowerBound)
                path.move(to: CGPoint(x: point.x, y: 8))
                path.addLine(to: CGPoint(x: point.x, y: 8 + plotHeight))
            case .y:
                let point = position(for: xDomain.lowerBound, y: rule.value)
                path.move(to: CGPoint(x: 6, y: point.y))
                path.addLine(to: CGPoint(x: 6 + plotWidth, y: point.y))
            }
        }
        .stroke(
            LightChartVisualStyle.ruleTint(rule.tint),
            style: StrokeStyle(lineWidth: 1, dash: rule.dashed ? [4, 4] : [])
        )
    }
}

enum LightTimeSeriesLayout {
    static func positions(
        for points: [LightTimeSeriesPoint],
        in size: CGSize,
        yDomain: ClosedRange<Double>
    ) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let plotWidth = max(1, size.width - 12)
        let minTime = points.first?.timestamp.timeIntervalSinceReferenceDate ?? 0
        let maxTime = points.last?.timestamp.timeIntervalSinceReferenceDate ?? minTime + 1
        let timeSpan = max(1, maxTime - minTime)
        return points.map { point in
            let x = ((point.timestamp.timeIntervalSinceReferenceDate - minTime) / timeSpan) * plotWidth + 6
            let y = yPosition(for: point.value, in: size, yDomain: yDomain)
            return CGPoint(x: x, y: y)
        }
    }

    static func segments(
        for points: [LightTimeSeriesPoint],
        in size: CGSize,
        yDomain: ClosedRange<Double>
    ) -> [[CGPoint]] {
        guard !points.isEmpty else { return [] }

        let threshold = gapThreshold(for: points)
        let minTime = points.first?.timestamp.timeIntervalSinceReferenceDate ?? 0
        let maxTime = points.last?.timestamp.timeIntervalSinceReferenceDate ?? minTime + 1
        let timeSpan = max(1, maxTime - minTime)
        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []
        var lastTimestamp: TimeInterval?

        for point in points {
            guard point.value.isFinite else {
                if !current.isEmpty {
                    segments.append(current)
                    current = []
                }
                lastTimestamp = nil
                continue
            }

            let currentTimestamp = point.timestamp.timeIntervalSinceReferenceDate
            if let lastTimestamp, currentTimestamp - lastTimestamp > threshold, !current.isEmpty {
                segments.append(current)
                current = []
            }

            let x = ((currentTimestamp - minTime) / timeSpan) * max(1, size.width - 12) + 6
            let y = yPosition(for: point.value, in: size, yDomain: yDomain)
            current.append(CGPoint(x: x, y: y))
            lastTimestamp = currentTimestamp
        }

        if !current.isEmpty {
            segments.append(current)
        }
        return segments.filter { !$0.isEmpty }
    }

    private static func gapThreshold(for points: [LightTimeSeriesPoint]) -> TimeInterval {
        let valid = points
            .filter { $0.value.isFinite }
            .map(\.timestamp.timeIntervalSinceReferenceDate)
        guard valid.count > 2 else { return .infinity }

        let intervals = zip(valid, valid.dropFirst())
            .map { $1 - $0 }
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        guard !intervals.isEmpty else { return .infinity }
        let median = intervals[intervals.count / 2]
        return max(1, median * 1.8)
    }

    static func yPosition(
        for value: Double,
        in size: CGSize,
        yDomain: ClosedRange<Double>
    ) -> CGFloat {
        let plotHeight = max(1, size.height - 16)
        let clamped = min(max(value, yDomain.lowerBound), yDomain.upperBound)
        let ratio = (clamped - yDomain.lowerBound) / max(yDomain.upperBound - yDomain.lowerBound, 0.001)
        return (1 - ratio) * plotHeight + 8
    }
}

private enum LightTimeSeriesDomainResolver {
    static func yDomain(for model: LightTimeSeriesCardModel, scaleMode: LightChartScaleMode) -> ClosedRange<Double> {
        if scaleMode == .fixed {
            return model.yDomain
        }
        let values = model.series.flatMap { $0.points.map(\.value) } + model.bands.flatMap { [$0.lower, $0.upper] } + model.rules.map(\.value)
        return paddedDomain(values: values, fallback: model.yDomain)
    }
}

private enum LightCategoricalDomainResolver {
    static func yDomain(for model: LightCategoricalCardModel, scaleMode: LightChartScaleMode) -> ClosedRange<Double> {
        let auto = paddedDomain(
            values: [0] + model.points.map(\.value),
            fallback: model.yDomain ?? 0...1,
            preferZeroLowerBound: true
        )
        guard scaleMode == .fixed, let fixed = model.yDomain else {
            return auto
        }
        return fixed
    }
}

private enum LightScatterDomainResolver {
    static func domains(for model: LightScatterCardModel, scaleMode: LightChartScaleMode) -> (x: ClosedRange<Double>, y: ClosedRange<Double>) {
        if scaleMode == .fixed {
            return (model.xDomain, model.yDomain)
        }
        let xValues = model.samples.map(\.x) + model.curves.flatMap { $0.points.map(\.x) } + model.rules.compactMap { $0.axis == .x ? $0.value : nil } + model.bands.flatMap { [$0.lowerX, $0.upperX] }
        let yValues = model.samples.map(\.y) + model.curves.flatMap { $0.points.map(\.y) } + model.rules.compactMap { $0.axis == .y ? $0.value : nil } + model.bands.flatMap { [$0.lowerY, $0.upperY] }
        return (
            paddedDomain(values: xValues, fallback: model.xDomain),
            paddedDomain(values: yValues, fallback: model.yDomain)
        )
    }
}

private enum BikeComputerLightChartDomainResolver {
    static func yDomain(
        points: [BikeComputerLightLinePoint],
        fixedYDomain: ClosedRange<Double>?,
        scaleMode: LightChartScaleMode
    ) -> ClosedRange<Double> {
        if scaleMode == .fixed, let fixedYDomain {
            return fixedYDomain
        }
        return paddedDomain(values: points.map(\.value), fallback: fixedYDomain ?? 0...1)
    }
}

private func paddedDomain(
    values: [Double],
    fallback: ClosedRange<Double>,
    preferZeroLowerBound: Bool = false
) -> ClosedRange<Double> {
    let finiteValues = values.filter(\.isFinite)
    guard let minValue = finiteValues.min(), let maxValue = finiteValues.max() else {
        return fallback
    }
    if abs(maxValue - minValue) < 0.0001 {
        let padding = max(1.0, abs(maxValue) * 0.15)
        let lower = preferZeroLowerBound ? min(0, minValue - padding) : minValue - padding
        let upper = maxValue + padding
        return lower...max(lower + 0.001, upper)
    }
    let span = maxValue - minValue
    let padding = max(0.001, span * 0.12)
    let lower = preferZeroLowerBound ? min(0, minValue - padding) : minValue - padding
    let upper = maxValue + padding
    return lower...max(lower + 0.001, upper)
}

enum LightTimeSeriesRendererStyle {
    static func lineDashPattern(dashed: Bool) -> [CGFloat] {
        dashed ? [5, 4] : []
    }

    static func lineStrokeStyle(width: CGFloat, dashed: Bool) -> StrokeStyle {
        StrokeStyle(
            lineWidth: width,
            lineCap: .round,
            lineJoin: .round,
            dash: lineDashPattern(dashed: dashed)
        )
    }
}

enum LightScatterRendererLayout {
    static func bandRect(
        for band: LightScatterBand,
        size: CGSize,
        xDomain: ClosedRange<Double>,
        yDomain: ClosedRange<Double>
    ) -> CGRect {
        let plotWidth = max(1, size.width - 12)
        let plotHeight = max(1, size.height - 16)

        func point(x: Double, y: Double) -> CGPoint {
            let clampedX = min(max(x, xDomain.lowerBound), xDomain.upperBound)
            let xRatio = (clampedX - xDomain.lowerBound) / max(xDomain.upperBound - xDomain.lowerBound, 0.001)
            let clampedY = min(max(y, yDomain.lowerBound), yDomain.upperBound)
            let yRatio = (clampedY - yDomain.lowerBound) / max(yDomain.upperBound - yDomain.lowerBound, 0.001)
            return CGPoint(
                x: CGFloat(xRatio) * plotWidth + 6,
                y: CGFloat(1 - yRatio) * plotHeight + 8
            )
        }

        let lower = point(x: band.lowerX, y: band.lowerY)
        let upper = point(x: band.upperX, y: band.upperY)
        return CGRect(
            x: min(lower.x, upper.x),
            y: min(lower.y, upper.y),
            width: max(2, abs(upper.x - lower.x)),
            height: max(2, abs(upper.y - lower.y))
        )
    }
}

private struct BikeComputerLightRouteProfilePlot: View {
    let points: [BikeComputerLightRouteProfilePoint]
    let markers: [BikeComputerLightRouteProfileMarker]
    let tint: Color
    let mode: AppChartDisplayMode

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if points.count < 2 {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.08))
                    .overlay(
                        Text(L10n.choose(simplifiedChinese: "等待路线数据", english: "Waiting for route"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            } else if mode == .pie {
                BikeComputerLightRouteCircularPlot(points: points, tint: tint)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.07))
                    BikeComputerLightGrid()
                        .stroke(Color.black.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    BikeComputerLightRouteCartesianPlot(
                        points: points,
                        markers: markers,
                        tint: tint,
                        mode: mode,
                        size: size
                    )
                }
            }
        }
    }
}

private struct BikeComputerLightRouteCircularPlot: View {
    let points: [BikeComputerLightRouteProfilePoint]
    let tint: Color

    private var slices: [(start: Double, end: Double, opacity: Double)] {
        let totalDistance = max(0.001, (points.last?.distanceKm ?? 0) - (points.first?.distanceKm ?? 0))
        let maxElevation = max(1, points.map(\.elevationM).max() ?? 1)
        return zip(points, points.dropFirst()).map { current, next in
            let start = (current.distanceKm - (points.first?.distanceKm ?? 0)) / totalDistance
            let end = (next.distanceKm - (points.first?.distanceKm ?? 0)) / totalDistance
            let elevation = max(0, current.elevationM)
            let opacity = 0.22 + 0.58 * min(max(elevation / maxElevation, 0), 1)
            return (start, end, opacity)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let frame = CGRect(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2,
                width: side,
                height: side
            )
            ZStack {
                Circle()
                    .fill(tint.opacity(0.08))
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    BikeComputerSectorShape(
                        startFraction: slice.start,
                        endFraction: slice.end,
                        innerRatio: 0.56
                    )
                    .fill(tint.opacity(slice.opacity))
                }
                Circle()
                    .stroke(tint.opacity(0.22), lineWidth: 1)
                Text(L10n.choose(simplifiedChinese: "路线分布", english: "Route"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }
}

private struct BikeComputerLightRouteCartesianPlot: View {
    let points: [BikeComputerLightRouteProfilePoint]
    let markers: [BikeComputerLightRouteProfileMarker]
    let tint: Color
    let mode: AppChartDisplayMode
    let size: CGSize

    private var samples: [CGPoint] {
        BikeComputerLightRouteProfileLayout.positions(for: points, in: size)
    }

    private var markerSamples: [(BikeComputerLightRouteProfileMarker, CGPoint)] {
        BikeComputerLightRouteProfileLayout.markerPositions(for: markers, points: points, in: size)
    }

    var body: some View {
        ZStack {
            switch mode {
            case .line:
                BikeComputerAreaShape(samples: samples)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.24), tint.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                BikeComputerLineShape(samples: samples)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            case .bar, .flame:
                routeBars(flame: mode == .flame)
            case .pie:
                EmptyView()
            }

            ForEach(Array(markerSamples.enumerated()), id: \.offset) { _, entry in
                let marker = entry.0
                let point = entry.1
                Path { path in
                    path.move(to: CGPoint(x: point.x, y: size.height - 8))
                    path.addLine(to: point)
                }
                .stroke(
                    marker.tint.opacity(marker.prominent ? 0.55 : 0.35),
                    style: StrokeStyle(lineWidth: marker.prominent ? 1.6 : 1.1, dash: [4, 4])
                )

                Circle()
                    .fill(marker.tint)
                    .frame(width: marker.prominent ? 11 : 8, height: marker.prominent ? 11 : 8)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )
                    .position(point)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func routeBars(flame: Bool) -> some View {
        let barWidth = max(3, (size.width - 12) / CGFloat(max(points.count, 1)))
        let maxElevation = max(1, points.map(\.elevationM).max() ?? 1)
        ForEach(Array(samples.enumerated()), id: \.offset) { index, point in
            let value = max(0, points[index].elevationM)
            let normalized = min(max(value / maxElevation, 0), 1)
            let height = (size.height - 18) * normalized
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    flame
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [.yellow.opacity(0.95), .orange.opacity(0.92), tint.opacity(0.9)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        : AnyShapeStyle(tint.opacity(0.82))
                )
                .frame(width: barWidth, height: max(3, height))
                .position(x: point.x, y: size.height - 8 - max(3, height) / 2)
        }
    }
}

private enum BikeComputerLightRouteProfileLayout {
    static func positions(for points: [BikeComputerLightRouteProfilePoint], in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let maxDistance = max(points.last?.distanceKm ?? 1, points.first?.distanceKm ?? 0.001)
        let minDistance = points.first?.distanceKm ?? 0
        let maxElevation = max(points.map(\.elevationM).max() ?? 1, 1)
        let minElevation = min(points.map(\.elevationM).min() ?? 0, 0)
        let plotHeight = max(1, size.height - 16)
        let plotWidth = max(1, size.width - 12)
        return points.map { point in
            let x = ((point.distanceKm - minDistance) / max(maxDistance - minDistance, 0.001)) * plotWidth + 6
            let yRatio = (point.elevationM - minElevation) / max(maxElevation - minElevation, 0.001)
            let y = (1 - yRatio) * plotHeight + 8
            return CGPoint(x: x, y: y)
        }
    }

    static func markerPositions(
        for markers: [BikeComputerLightRouteProfileMarker],
        points: [BikeComputerLightRouteProfilePoint],
        in size: CGSize
    ) -> [(BikeComputerLightRouteProfileMarker, CGPoint)] {
        guard !markers.isEmpty, !points.isEmpty else { return [] }
        let routeSamples = positions(for: points, in: size)
        let baseDistance = points.first?.distanceKm ?? 0
        let totalDistance = max((points.last?.distanceKm ?? 0) - baseDistance, 0.001)
        let maxElevation = max(points.map(\.elevationM).max() ?? 1, 1)
        let minElevation = min(points.map(\.elevationM).min() ?? 0, 0)
        let plotHeight = max(1, size.height - 16)
        let plotWidth = max(1, size.width - 12)
        return markers.map { marker in
            let x = ((marker.distanceKm - baseDistance) / totalDistance) * plotWidth + 6
            let yRatio = (marker.elevationM - minElevation) / max(maxElevation - minElevation, 0.001)
            let y = (1 - yRatio) * plotHeight + 8
            let fallback = routeSamples.min { abs($0.x - x) < abs($1.x - x) } ?? CGPoint(x: x, y: y)
            return (marker, CGPoint(x: x, y: fallback.y.isFinite ? fallback.y : y))
        }
    }
}

private struct BikeComputerLightGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = 4
        for row in 1..<rows {
            let y = rect.minY + rect.height * CGFloat(row) / CGFloat(rows)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct BikeComputerLightCartesianPlot: View {
    let points: [BikeComputerLightLinePoint]
    let tint: Color
    let mode: BikeComputerChartDisplayMode
    let size: CGSize
    let yDomain: ClosedRange<Double>

    private var samples: [CGPoint] {
        BikeComputerLightPathLayout.positions(for: points, in: size, yDomain: yDomain)
    }

    var body: some View {
        ZStack {
            switch mode {
            case .area:
                BikeComputerAreaShape(samples: samples)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                BikeComputerLineShape(samples: samples)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            case .bar, .stackedBar, .flame:
                barsView(flame: mode == .flame, stacked: mode == .stackedBar)
            case .scatter:
                pointsView(showStems: false)
            case .step:
                BikeComputerStepShape(samples: samples)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
            case .lollipop:
                pointsView(showStems: true)
            case .line, .pie, .donut:
                BikeComputerLineShape(samples: samples)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func pointsView(showStems: Bool) -> some View {
        ForEach(Array(samples.enumerated()), id: \.offset) { _, point in
            if showStems {
                Path { path in
                    path.move(to: CGPoint(x: point.x, y: size.height - 8))
                    path.addLine(to: point)
                }
                .stroke(tint.opacity(0.45), lineWidth: 1)
            }
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .position(point)
        }
    }

    @ViewBuilder
    private func barsView(flame: Bool, stacked: Bool) -> some View {
        let baseline = size.height - 10
        let top = 8.0
        let barWidth = max(4, (size.width - 12) / CGFloat(max(samples.count, 1)) * 0.62)
        ForEach(Array(samples.enumerated()), id: \.offset) { _, point in
            let height = max(2, baseline - point.y)
            let y = baseline - height / 2
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    flame
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [.yellow.opacity(0.95), .orange.opacity(0.9), tint.opacity(0.85)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    : AnyShapeStyle(tint.opacity(stacked ? 0.72 : 0.84))
                )
                .frame(width: barWidth, height: height)
                .position(x: point.x, y: y)

            if stacked {
                let topHeight = max(1, height * 0.36)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.30))
                    .frame(width: barWidth, height: topHeight)
                    .position(x: point.x, y: max(top, y - height * 0.24))
            }
        }
    }
}

private struct BikeComputerLightCircularPlot: View {
    let points: [BikeComputerLightLinePoint]
    let tint: Color
    let isDonut: Bool

    private var bins: [Double] {
        let values = points.map { max(0, $0.value) }
        guard !values.isEmpty else { return [] }
        let bucketCount = min(10, max(4, values.count / 6))
        let chunk = max(1, values.count / bucketCount)
        var output: [Double] = []
        var index = 0
        while index < values.count {
            let slice = values[index..<min(values.count, index + chunk)]
            output.append(slice.reduce(0, +))
            index += chunk
        }
        return output
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 12, dy: 12)
            let total = max(bins.reduce(0, +), 0.0001)
            ZStack {
                ForEach(Array(bins.enumerated()), id: \.offset) { index, value in
                    let start = bins.prefix(index).reduce(0, +) / total
                    let end = (bins.prefix(index).reduce(0, +) + value) / total
                    BikeComputerSectorShape(startFraction: start, endFraction: end, innerRatio: isDonut ? 0.55 : 0.0)
                        .fill(tint.opacity(0.25 + (Double(index) / Double(max(bins.count, 1))) * 0.55))
                }
                if isDonut {
                    VStack(spacing: 2) {
                        Text(L10n.choose(simplifiedChinese: "分布", english: "Distribution"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(points.count)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.18))
                    }
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
    }
}

private struct BikeComputerSectorShape: Shape {
    let startFraction: Double
    let endFraction: Double
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) * 0.5
        let innerRadius = outerRadius * innerRatio
        let startAngle = Angle.degrees(-90 + startFraction * 360)
        let endAngle = Angle.degrees(-90 + endFraction * 360)

        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        if innerRadius > 0 {
            path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        } else {
            path.addLine(to: center)
        }
        path.closeSubpath()
        return path
    }
}

private enum BikeComputerLightPathLayout {
    static func positions(for points: [BikeComputerLightLinePoint], in size: CGSize, yDomain: ClosedRange<Double>) -> [CGPoint] {
        guard points.count >= 2 else { return [] }
        let leftPadding: CGFloat = 8
        let rightPadding: CGFloat = 8
        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 10
        let width = max(1, size.width - leftPadding - rightPadding)
        let height = max(1, size.height - topPadding - bottomPadding)
        return points.enumerated().map { index, point in
            let x = leftPadding + CGFloat(index) / CGFloat(max(points.count - 1, 1)) * width
            let clamped = min(max(point.value, yDomain.lowerBound), yDomain.upperBound)
            let normalized = (clamped - yDomain.lowerBound) / max(0.0001, yDomain.upperBound - yDomain.lowerBound)
            let y = topPadding + (1 - CGFloat(normalized)) * height
            return CGPoint(x: x, y: y)
        }
    }
}

private struct BikeComputerLineShape: Shape {
    let samples: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = samples.first else { return path }
        path.move(to: first)
        for sample in samples.dropFirst() {
            path.addLine(to: sample)
        }
        return path
    }
}

private struct BikeComputerStepShape: Shape {
    let samples: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = samples.first else { return path }
        path.move(to: first)
        for sample in samples.dropFirst() {
            if let current = path.currentPoint {
                path.addLine(to: CGPoint(x: sample.x, y: current.y))
            }
            path.addLine(to: sample)
        }
        return path
    }
}

private struct BikeComputerAreaShape: Shape {
    let samples: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = samples.first, let last = samples.last else { return path }
        path.move(to: CGPoint(x: first.x, y: rect.maxY))
        path.addLine(to: first)
        for sample in samples.dropFirst() {
            path.addLine(to: sample)
        }
        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FlowLayout<Content: View>: View {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    @ViewBuilder let content: Content

    init(horizontalSpacing: CGFloat, verticalSpacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        _FlowLayout(horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
            content
        }
    }
}

private struct _FlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 1000
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }
    }
}

extension TrainerBikeComputerSnapshotPayload {
    func lightDashboardModel(title: String, subtitle: String, alerts: [BikeComputerLightAlert]) -> BikeComputerLightDashboardModel {
        let powerZoneRows = Self.makeZoneRows(
            seconds: powerZoneSec,
            colors: [.blue, .teal, .green, .yellow, .orange, .red, .purple]
        )
        let heartZoneRows = Self.makeZoneRows(
            seconds: heartRateZoneSec,
            colors: [.mint, .green, .yellow, .orange, .red, .pink, .purple]
        )

        return BikeComputerLightDashboardModel(
            title: title,
            subtitle: subtitle,
            headlineItems: [
                .init(label: "时长", value: Self.durationText(elapsedSec)),
                .init(label: "移动", value: Self.durationText(movingSec)),
                .init(label: "距离", value: String(format: "%.2f km", distanceKm)),
                .init(label: "热量", value: estimatedCaloriesKCal.map { String(format: "%.0f kcal", $0) } ?? "--")
            ],
            heroMetrics: [
                .init(title: "Power", value: latestPower.map { "\($0) W" } ?? "--", meta: "Avg \(averagePower.map { "\($0) W" } ?? "--") · NP \(normalizedPower.map { "\($0) W" } ?? "--")", tint: .orange),
                .init(title: "Heart Rate", value: latestHeartRate.map { "\($0) bpm" } ?? "--", meta: "Avg \(averageHeartRate.map { "\($0) bpm" } ?? "--") · Max \(maxHeartRate.map { "\($0) bpm" } ?? "--")", tint: .red),
                .init(title: "Cadence", value: latestCadence.map { "\($0) rpm" } ?? "--", meta: "Avg \(averageCadence.map { "\($0) rpm" } ?? "--")", tint: .green),
                .init(title: "Speed", value: latestSpeedKPH.map { String(format: "%.1f km/h", $0) } ?? "--", meta: "Avg \(averageSpeedKPH.map { String(format: "%.1f km/h", $0) } ?? "--")", tint: .blue),
                .init(title: "Balance", value: Self.balanceText(left: balanceLeftPercent, right: balanceRightPercent), meta: "Power split", tint: .purple),
                .init(title: "5s / 30s", value: "\(Self.powerText(power5s)) / \(Self.powerText(power30s))", meta: "Best short power", tint: .pink),
                .init(title: "1m / 20m", value: "\(Self.powerText(power1m)) / \(Self.powerText(power20m))", meta: "Tempo / threshold", tint: .teal),
                .init(title: "60m", value: Self.powerText(power60m), meta: "Long steady power", tint: .brown)
            ],
            summaryRows: [
                .init(label: "开始", value: IntervalsDateFormatter.dateTimeLocal.string(from: startDate)),
                .init(label: "结束", value: IntervalsDateFormatter.dateTimeLocal.string(from: endDate)),
                .init(label: "FTP 区间", value: "\(maxHeartRateForZones) bpm MaxHR"),
                .init(label: "Max Power", value: maxPower.map { "\($0) W" } ?? "--"),
                .init(label: "Max Speed", value: maxSpeedKPH.map { String(format: "%.1f km/h", $0) } ?? "--"),
                .init(label: "Distance", value: String(format: "%.2f km", distanceKm)),
                .init(label: "Calories", value: estimatedCaloriesKCal.map { String(format: "%.0f kcal", $0) } ?? "--"),
                .init(label: "Rider", value: riderName)
            ],
            alerts: alerts,
            zoneGroups: [
                .init(title: "Power Zones", summary: Self.zoneSummaryText(powerZoneRows), rows: powerZoneRows, tint: .orange),
                .init(title: "Heart Rate Zones", summary: "MaxHR \(maxHeartRateForZones) bpm · \(Self.zoneSummaryText(heartZoneRows))", rows: heartZoneRows, tint: .red)
            ],
            charts: [
                .init(storageKey: "fricu.chart.bike.power", title: "Power", value: latestPower.map { "\($0) W" } ?? "--", detail: "Avg \(averagePower.map { "\($0) W" } ?? "--")", tint: .orange, points: powerTrace.enumerated().map { offset, value in .init(timestamp: endDate.addingTimeInterval(Double(offset - powerTrace.count)), value: value) }, fixedYDomain: 0...600, yAxisFormat: .number(decimals: 0, suffix: "W")),
                .init(storageKey: "fricu.chart.bike.heart_rate", title: "Heart Rate", value: latestHeartRate.map { "\($0) bpm" } ?? "--", detail: "Avg \(averageHeartRate.map { "\($0) bpm" } ?? "--")", tint: .red, points: heartRateTrace.enumerated().map { offset, value in .init(timestamp: endDate.addingTimeInterval(Double(offset - heartRateTrace.count)), value: value) }, fixedYDomain: 40...200, yAxisFormat: .number(decimals: 0, suffix: "bpm")),
                .init(storageKey: "fricu.chart.bike.cadence", title: "Cadence", value: latestCadence.map { "\($0) rpm" } ?? "--", detail: "Avg \(averageCadence.map { "\($0) rpm" } ?? "--")", tint: .green, points: cadenceTrace.enumerated().map { offset, value in .init(timestamp: endDate.addingTimeInterval(Double(offset - cadenceTrace.count)), value: value) }, fixedYDomain: 40...130, yAxisFormat: .number(decimals: 0, suffix: "rpm"))
            ]
        )
    }

    private static func durationText(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private static func powerText(_ value: Double?) -> String {
        value.map { String(format: "%.0f W", $0) } ?? "--"
    }

    private static func balanceText(left: Double?, right: Double?) -> String {
        guard let left, let right else { return "--" }
        return String(format: "L%.1f%% / R%.1f%%", left, right)
    }

    private static func makeZoneRows(seconds: [Int], colors: [Color]) -> [BikeComputerLightZoneRow] {
        let total = max(1, seconds.reduce(0, +))
        return seconds.enumerated().map { index, value in
            BikeComputerLightZoneRow(
                name: "Z\(index + 1)",
                seconds: value,
                percent: Double(value) / Double(total),
                color: colors[min(index, colors.count - 1)]
            )
        }
    }

    private static func zoneSummaryText(_ rows: [BikeComputerLightZoneRow]) -> String {
        rows
            .map { "\($0.name) \($0.seconds.asDuration)" }
            .joined(separator: " · ")
    }
}
