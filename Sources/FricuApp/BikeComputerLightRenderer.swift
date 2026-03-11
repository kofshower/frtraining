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
}

struct LightTimeSeriesBand: Identifiable {
    let id: String
    let lower: Double
    let upper: Double
    let tint: Color
    let opacity: Double
}

struct LightTimeSeriesRule: Identifiable {
    let id: String
    let value: Double
    let tint: Color
    let dashed: Bool
}

struct LightTimeSeriesCardModel {
    let title: String
    let valueText: String
    let detailText: String
    let footerLines: [String]
    let yDomain: ClosedRange<Double>
    let series: [LightTimeSeriesSeries]
    let bands: [LightTimeSeriesBand]
    let rules: [LightTimeSeriesRule]
    let tint: Color
    let plotHeight: CGFloat
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
                    Color(red: 0.95, green: 0.92, blue: 0.85),
                    Color(red: 0.97, green: 0.95, blue: 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.18))
                    Text(model.subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(model.headlineItems) { item in
                        HStack(spacing: 8) {
                            Text(item.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(item.value)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.18))
                        }
                    }
                }
            }

            metricGrid
        }
        .padding(20)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.18))
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
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct BikeComputerLightZoneGroupView: View {
    let group: BikeComputerLightZoneGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(group.tint)
            Text(group.summary)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            VStack(spacing: 8) {
                ForEach(group.rows) { row in
                    HStack(spacing: 8) {
                        Text(row.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.18))
                            .frame(width: 28, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.black.opacity(0.06))
                                Capsule()
                                    .fill(row.color)
                                    .frame(width: geo.size.width * min(max(row.percent, 0), 1))
                            }
                        }
                        .frame(height: 8)
                        Text(row.seconds.asDuration)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .trailing)
                        Text(String(format: "%.0f%%", row.percent * 100))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .frame(height: 16)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct BikeComputerLightChartCard: View {
    @State private var mode: BikeComputerChartDisplayMode

    let chart: BikeComputerLightChart

    init(chart: BikeComputerLightChart) {
        self.chart = chart
        let stored = UserDefaults.standard.string(forKey: chart.storageKey)
        _mode = State(initialValue: BikeComputerChartDisplayMode(rawValue: stored ?? "") ?? .line)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(chart.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ChartModeMenuButton(selection: $mode)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(chart.value)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.18))
                Spacer()
                Text(chart.detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            BikeComputerLightChartPlot(
                points: chart.points,
                tint: chart.tint,
                mode: mode
            )
            .frame(height: 118)
        }
        .padding(16)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(chart.tint.opacity(0.18), lineWidth: 1)
        )
        .onChange(of: mode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: chart.storageKey)
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
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(distanceAxisLabel) · \(elevationAxisLabel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
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
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct LightTimeSeriesCard: View {
    let model: LightTimeSeriesCardModel
    @Binding var mode: AppChartDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                AppChartModeMenuButton(selection: $mode)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(model.valueText)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text(model.detailText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            LightTimeSeriesPlot(
                model: model,
                mode: mode
            )
            .frame(height: model.plotHeight)

            if !model.footerLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.footerLines, id: \.self) { line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(model.tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct BikeComputerLightChartPlot: View {
    let points: [BikeComputerLightLinePoint]
    let tint: Color
    let mode: BikeComputerChartDisplayMode

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
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.07))
                    BikeComputerLightGrid()
                        .stroke(Color.black.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    BikeComputerLightCartesianPlot(
                        points: points,
                        tint: tint,
                        mode: mode,
                        size: size
                    )
                }
            }
        }
    }
}

private struct LightTimeSeriesPlot: View {
    let model: LightTimeSeriesCardModel
    let mode: AppChartDisplayMode

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
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(model.tint.opacity(0.07))
                    BikeComputerLightGrid()
                        .stroke(Color.black.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    LightTimeSeriesCartesianPlot(
                        model: model,
                        mode: mode,
                        size: size
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

private struct LightTimeSeriesCartesianPlot: View {
    let model: LightTimeSeriesCardModel
    let mode: AppChartDisplayMode
    let size: CGSize

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
        let samples = positions(for: series.points)
        switch series.renderStyle {
        case .areaLine:
            BikeComputerAreaShape(samples: samples)
                .fill(
                    LinearGradient(
                        colors: [series.tint.opacity(0.22), series.tint.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            BikeComputerLineShape(samples: samples)
                .stroke(series.tint, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
        case .step:
            BikeComputerStepShape(samples: samples)
                .stroke(series.tint, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
        case .line, .bar:
            BikeComputerLineShape(samples: samples)
                .stroke(series.tint, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
        }
    }

    @ViewBuilder
    private func barSeriesView(_ series: LightTimeSeriesSeries, flame: Bool) -> some View {
        let samples = positions(for: series.points)
        let barWidth = max(3, plotWidth / CGFloat(max(series.points.count, 1)))
        ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
            let valueY = sample.y
            let barHeight = abs(baselineY - valueY)
            let centerY = min(baselineY, valueY) + barHeight / 2
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    flame
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [.yellow.opacity(0.95), .orange.opacity(0.92), series.tint.opacity(0.9)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        : AnyShapeStyle(series.tint.opacity(0.82))
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
            rule.tint.opacity(0.5),
            style: StrokeStyle(lineWidth: 1, dash: rule.dashed ? [4, 4] : [])
        )
    }

    private func positions(for points: [LightTimeSeriesPoint]) -> [CGPoint] {
        LightTimeSeriesLayout.positions(for: points, in: size, yDomain: model.yDomain)
    }

    private func yPosition(for value: Double) -> CGFloat {
        LightTimeSeriesLayout.yPosition(for: value, in: size, yDomain: model.yDomain)
    }
}

private enum LightTimeSeriesLayout {
    static func positions(
        for points: [LightTimeSeriesPoint],
        in size: CGSize,
        yDomain: ClosedRange<Double>
    ) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let plotHeight = max(1, size.height - 16)
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

    private var samples: [CGPoint] {
        BikeComputerLightPathLayout.positions(for: points, in: size)
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
    static func positions(for points: [BikeComputerLightLinePoint], in size: CGSize) -> [CGPoint] {
        guard points.count >= 2 else { return [] }
        let leftPadding: CGFloat = 8
        let rightPadding: CGFloat = 8
        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 10
        let values = points.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let span = max(0.0001, maxValue - minValue)
        let width = max(1, size.width - leftPadding - rightPadding)
        let height = max(1, size.height - topPadding - bottomPadding)
        return points.enumerated().map { index, point in
            let x = leftPadding + CGFloat(index) / CGFloat(max(points.count - 1, 1)) * width
            let normalized = (point.value - minValue) / span
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
                .init(storageKey: "fricu.chart.bike.power", title: "Power", value: latestPower.map { "\($0) W" } ?? "--", detail: "Avg \(averagePower.map { "\($0) W" } ?? "--")", tint: .orange, points: powerTrace.enumerated().map { offset, value in .init(timestamp: endDate.addingTimeInterval(Double(offset - powerTrace.count)), value: value) }),
                .init(storageKey: "fricu.chart.bike.heart_rate", title: "Heart Rate", value: latestHeartRate.map { "\($0) bpm" } ?? "--", detail: "Avg \(averageHeartRate.map { "\($0) bpm" } ?? "--")", tint: .red, points: heartRateTrace.enumerated().map { offset, value in .init(timestamp: endDate.addingTimeInterval(Double(offset - heartRateTrace.count)), value: value) }),
                .init(storageKey: "fricu.chart.bike.cadence", title: "Cadence", value: latestCadence.map { "\($0) rpm" } ?? "--", detail: "Avg \(averageCadence.map { "\($0) rpm" } ?? "--")", tint: .green, points: cadenceTrace.enumerated().map { offset, value in .init(timestamp: endDate.addingTimeInterval(Double(offset - cadenceTrace.count)), value: value) })
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
