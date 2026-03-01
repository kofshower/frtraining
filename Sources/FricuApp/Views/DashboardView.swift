import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(\.appChartDisplayMode) private var chartDisplayMode
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    private enum LoadDisplayMode: String, CaseIterable, Identifiable {
        case raw
        case smooth7d

        var id: String { rawValue }

        var label: String {
            switch self {
            case .raw: return "原始"
            case .smooth7d: return "平滑 7d"
            }
        }
    }

    private enum DashboardTimeRange: String, CaseIterable, Identifiable {
        case days30
        case days90
        case days180
        case days365
        case all

        var id: String { rawValue }

        var label: String {
            switch self {
            case .days30: return "30d"
            case .days90: return "90d"
            case .days180: return "180d"
            case .days365: return "365d"
            case .all: return "All"
            }
        }

        var days: Int? {
            switch self {
            case .days30: return 30
            case .days90: return 90
            case .days180: return 180
            case .days365: return 365
            case .all: return nil
            }
        }
    }

    private struct DashboardStatCardItem: Identifiable {
        let id: String
        let title: String
        let value: String
        let method: String
        let tint: Color
        let emphasis: Double

        init(
            id: String? = nil,
            title: String,
            value: String,
            method: String,
            tint: Color,
            emphasis: Double = 0.45
        ) {
            self.id = id ?? title
            self.title = title
            self.value = value
            self.method = method
            self.tint = tint
            self.emphasis = min(max(emphasis, 0.0), 1.0)
        }
    }

    private struct DashboardStatGroup: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let cards: [DashboardStatCardItem]
    }

    private struct DashboardHighlightItem: Identifiable {
        let id: String
        let title: String
        let value: String
        let trendText: String
        let tint: Color
    }

    @EnvironmentObject private var store: AppStore
    @State private var loadDisplayMode: LoadDisplayMode = .raw
    @State private var selectedTimeRange: DashboardTimeRange = .days180

    private var rangeStartDate: Date? {
        guard let days = selectedTimeRange.days else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -days + 1, to: today)
    }

    private func inSelectedTimeRange(_ date: Date) -> Bool {
        guard let start = rangeStartDate else { return true }
        return Calendar.current.startOfDay(for: date) >= start
    }

    private var rangeFilteredActivities: [Activity] {
        store.filteredActivities.filter { inSelectedTimeRange($0.date) }
    }

    private var recentLoad: [DailyLoadPoint] {
        store.loadSeries.filter { inSelectedTimeRange($0.date) }
    }

    private var fitnessLoad: [DailyLoadPoint] {
        recentLoad
    }

    private var displayedFitnessLoad: [DailyLoadPoint] {
        switch loadDisplayMode {
        case .raw:
            return fitnessLoad
        case .smooth7d:
            return smoothedLoadSeries(fitnessLoad, window: 7)
        }
    }

    private var latestLoadPoint: DailyLoadPoint? {
        fitnessLoad.last ?? recentLoad.last
    }

    private var latestDisplayedLoadPoint: DailyLoadPoint? {
        displayedFitnessLoad.last ?? latestLoadPoint
    }

    private var currentFitness: Double {
        latestDisplayedLoadPoint?.ctl ?? 0
    }

    private var currentFatigue: Double {
        latestDisplayedLoadPoint?.atl ?? 0
    }

    private var currentForm: Double {
        latestDisplayedLoadPoint?.tsb ?? 0
    }

    private var currentStatusValuePercent: Int {
        let fitness = max(currentFitness, 1.0)
        let ratio = 1.0 - (currentFatigue / fitness)
        let clamped = min(max(ratio * 100.0, 0), 100)
        return Int(clamped.rounded())
    }

    private var loadMethodText: String {
        "计算: CTL_d=CTL_(d-1)+(TSS_d-CTL_(d-1))/42; ATL_d=ATL_(d-1)+(TSS_d-ATL_(d-1))/7; TSB_d=CTL_d-ATL_d"
    }

    private var loadParameterLines: [String] {
        let latest = recentLoad.last
        let latestTSS = latest?.tss ?? 0
        let latestCTL = latest?.ctl ?? 0
        let latestATL = latest?.atl ?? 0
        let latestTSB = latest?.tsb ?? 0
        let latestAerobicLTS = latest?.aerobicLongTermStress ?? 0
        let latestAnaerobicLTS = latest?.anaerobicLongTermStress ?? 0
        let latestAerobicSTS = latest?.aerobicShortTermStress ?? 0
        let latestAnaerobicSTS = latest?.anaerobicShortTermStress ?? 0
        return [
            "参数: 初始CTL=45.0, 初始ATL=50.0, τCTL=42d, τATL=7d",
            String(
                format: "参数: 窗口=%d天, 最新TSS=%.1f, 最新CTL=%.1f, 最新ATL=%.1f, 最新TSB=%.1f",
                recentLoad.count, latestTSS, latestCTL, latestATL, latestTSB
            ),
            String(
                format: "参数: AerLTS=%.1f, AnaLTS=%.1f, AerSTS=%.1f, AnaSTS=%.1f",
                latestAerobicLTS, latestAnaerobicLTS, latestAerobicSTS, latestAnaerobicSTS
            )
        ]
    }

    private var dailyTSSMethodText: String {
        "计算: DailyTSS_d = Σ(当天所有活动TSS)"
    }

    private var dailyTSSParameterLines: [String] {
        let values = recentLoad.map(\.tss)
        let avg7 = recentLoad.suffix(7).map(\.tss).average
        let maxTSS = values.max() ?? 0
        let latestTSS = values.last ?? 0
        let activeDays = values.filter { $0 > 0 }.count
        return [
            String(format: "参数: 窗口=%d天, 有训练天数=%d", recentLoad.count, activeDays),
            String(format: "参数: 最新DailyTSS=%.1f, 7天均值=%.1f, 窗口最大=%.1f", latestTSS, avg7, maxTSS)
        ]
    }

    private var dashboardStats: DashboardActivityStats {
        DashboardActivityStatsBuilder.build(
            activities: rangeFilteredActivities,
            profile: store.profile
        )
    }

    private var rangeSummary: DashboardSummary {
        LoadCalculator.summary(activities: rangeFilteredActivities, series: recentLoad)
    }

    private var rangeMetricStories: [MetricStory] {
        MetricStoryEngine.buildStories(
            summary: rangeSummary,
            loadSeries: recentLoad,
            activities: rangeFilteredActivities,
            recommendation: store.recommendation,
            profile: store.profile,
            wellness: store.athleteScopedWellnessSamples.filter { inSelectedTimeRange($0.date) }
        )
    }

    private var wellnessDescending: [WellnessSample] {
        store.athleteScopedWellnessSamples.sortedByDateDescending()
    }

    private var latestWellnessSample: WellnessSample? {
        wellnessDescending.first
    }

    private var avg7HRV: Double? {
        wellnessDescending.averageMostRecent(7, keyPath: \.hrv)
    }

    private var avg7RHR: Double? {
        wellnessDescending.averageMostRecent(7, keyPath: \.restingHR)
    }

    private var avg7SleepHours: Double? {
        wellnessDescending.averageMostRecent(7, keyPath: \.sleepHours)
    }

    private func oneDecimal(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f", value)
    }

    private func clampLevel(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private var dashboardStatCards: [DashboardStatCardItem] {
        let summary = rangeSummary
        let latest = latestLoadPoint
        let hrvToday = oneDecimal(latestWellnessSample?.hrv)
        let hrv7 = oneDecimal(avg7HRV)
        let rhrToday = oneDecimal(latestWellnessSample?.restingHR)
        let rhr7 = oneDecimal(avg7RHR)
        let sleepToday = oneDecimal(latestWellnessSample?.sleepHours)
        let sleep7 = oneDecimal(avg7SleepHours)
        let sleepScore = latestWellnessSample?.sleepScore.map { String(format: "%.0f", $0) } ?? "--"
        let hrvTodayValue = latestWellnessSample?.hrv ?? 0
        let rhrTodayValue = latestWellnessSample?.restingHR ?? 0
        let sleepTodayValue = latestWellnessSample?.sleepHours ?? 0

        return [
            DashboardStatCardItem(
                id: "weekly_tss",
                title: "Weekly TSS",
                value: "\(summary.weeklyTSS)",
                method: "计算: 本周每日 TSS 求和",
                tint: .blue,
                emphasis: clampLevel(Double(summary.weeklyTSS) / 700.0)
            ),
            DashboardStatCardItem(
                id: "monthly_distance",
                title: "Monthly Distance",
                value: String(format: "%.0f km", summary.monthlyDistanceKm),
                method: "计算: 本月每日距离求和",
                tint: .green,
                emphasis: clampLevel(summary.monthlyDistanceKm / 1200.0)
            ),
            DashboardStatCardItem(
                id: "atl",
                title: "Coggan Acute Training Load (ATL)",
                value: String(format: "%.1f", summary.currentATL),
                method: "计算: ATL_d = ATL_(d-1) + (TSS_d - ATL_(d-1))/7",
                tint: .orange,
                emphasis: clampLevel(summary.currentATL / 120.0)
            ),
            DashboardStatCardItem(
                id: "ctl",
                title: "Coggan Chronic Training Load (CTL)",
                value: String(format: "%.1f", summary.currentCTL),
                method: "计算: CTL_d = CTL_(d-1) + (TSS_d - CTL_(d-1))/42",
                tint: .blue,
                emphasis: clampLevel(summary.currentCTL / 120.0)
            ),
            DashboardStatCardItem(
                id: "tsb",
                title: "Coggan Training Stress Balance (TSB)",
                value: String(format: "%.1f", summary.currentTSB),
                method: "计算: TSB = CTL - ATL",
                tint: summary.currentTSB >= 0 ? .mint : .red,
                emphasis: clampLevel(abs(summary.currentTSB) / 30.0)
            ),
            DashboardStatCardItem(
                id: "aer_tiss_day",
                title: "Aerobic TISS (Day)",
                value: String(format: "%.1f", latest?.aerobicTISS ?? 0),
                method: "计算: AerTISS_d = TSS_d × (1 - AnaShare(IF))",
                tint: .teal,
                emphasis: clampLevel((latest?.aerobicTISS ?? 0) / 130.0)
            ),
            DashboardStatCardItem(
                id: "ana_tiss_day",
                title: "Anaerobic TISS (Day)",
                value: String(format: "%.1f", latest?.anaerobicTISS ?? 0),
                method: "计算: AnaTISS_d = TSS_d × AnaShare(IF)",
                tint: .pink,
                emphasis: clampLevel((latest?.anaerobicTISS ?? 0) / 80.0)
            ),
            DashboardStatCardItem(
                id: "aer_lts",
                title: "Aerobic TISS Long Term Stress",
                value: String(format: "%.1f", latest?.aerobicLongTermStress ?? 0),
                method: "计算: AerLTS_d = AerLTS_(d-1) + (AerTISS_d - AerLTS_(d-1))/42",
                tint: .teal,
                emphasis: clampLevel((latest?.aerobicLongTermStress ?? 0) / 90.0)
            ),
            DashboardStatCardItem(
                id: "ana_lts",
                title: "Anaerobic TISS Long Term Stress",
                value: String(format: "%.1f", latest?.anaerobicLongTermStress ?? 0),
                method: "计算: AnaLTS_d = AnaLTS_(d-1) + (AnaTISS_d - AnaLTS_(d-1))/42",
                tint: .purple,
                emphasis: clampLevel((latest?.anaerobicLongTermStress ?? 0) / 70.0)
            ),
            DashboardStatCardItem(
                id: "aer_sts",
                title: "Aerobic TISS Short Term Stress",
                value: String(format: "%.1f", latest?.aerobicShortTermStress ?? 0),
                method: "计算: AerSTS_d = AerSTS_(d-1) + (AerTISS_d - AerSTS_(d-1))/7",
                tint: .cyan,
                emphasis: clampLevel((latest?.aerobicShortTermStress ?? 0) / 130.0)
            ),
            DashboardStatCardItem(
                id: "ana_sts",
                title: "Anaerobic TISS Short Term Stress",
                value: String(format: "%.1f", latest?.anaerobicShortTermStress ?? 0),
                method: "计算: AnaSTS_d = AnaSTS_(d-1) + (AnaTISS_d - AnaSTS_(d-1))/7",
                tint: .pink,
                emphasis: clampLevel((latest?.anaerobicShortTermStress ?? 0) / 85.0)
            ),
            DashboardStatCardItem(
                id: "hrv",
                title: "HRV (Today / 7d)",
                value: "\(hrvToday) / \(hrv7)",
                method: String(
                    format: "计算: Today=最新样本; 7d=最近7天有效样本平均; 参数: HRV_today=%@, HRV_7d=%@, Baseline=%.1f",
                    hrvToday,
                    hrv7,
                    store.profile.hrvBaseline as CVarArg
                ),
                tint: .cyan,
                emphasis: clampLevel(
                    hrvTodayValue > 0 && store.profile.hrvBaseline > 0
                        ? (hrvTodayValue / store.profile.hrvBaseline) / 1.2
                        : 0.0
                )
            ),
            DashboardStatCardItem(
                id: "rhr",
                title: "RHR (Today / 7d)",
                value: "\(rhrToday) / \(rhr7) bpm",
                method: String(
                    format: "计算: Today=最新样本; 7d=最近7天有效样本平均; 参数: RHR_today=%@, RHR_7d=%@",
                    rhrToday,
                    rhr7
                ),
                tint: .pink,
                emphasis: clampLevel(rhrTodayValue > 0 ? (95.0 - rhrTodayValue) / 35.0 : 0.0)
            ),
            DashboardStatCardItem(
                id: "sleep",
                title: "Sleep (Today / 7d)",
                value: "\(sleepToday) / \(sleep7) h",
                method: String(
                    format: "计算: Sleep(h)=平台秒/分钟换算; 参数: Sleep_today=%@h, Sleep_7d=%@h, SleepScore=%@",
                    sleepToday,
                    sleep7,
                    sleepScore
                ),
                tint: .indigo,
                emphasis: clampLevel(sleepTodayValue / 8.0)
            )
        ]
    }

    private var dashboardHighlights: [DashboardHighlightItem] {
        let summary = rangeSummary
        let tsbTrend = summary.currentTSB >= 0
            ? L10n.choose(simplifiedChinese: "状态偏积极", english: "Positive readiness")
            : L10n.choose(simplifiedChinese: "建议恢复", english: "Recovery advised")
        let loadTrend = summary.currentATL > summary.currentCTL
            ? L10n.choose(simplifiedChinese: "短期负荷高", english: "High short-term load")
            : L10n.choose(simplifiedChinese: "负荷平衡", english: "Balanced load")

        return [
            DashboardHighlightItem(
                id: "focus_ctl",
                title: "CTL",
                value: String(format: "%.1f", summary.currentCTL),
                trendText: loadTrend,
                tint: .blue
            ),
            DashboardHighlightItem(
                id: "focus_tsb",
                title: "TSB",
                value: String(format: "%.1f", summary.currentTSB),
                trendText: tsbTrend,
                tint: summary.currentTSB >= 0 ? .mint : .orange
            ),
            DashboardHighlightItem(
                id: "focus_weekly",
                title: "Weekly TSS",
                value: "\(summary.weeklyTSS)",
                trendText: L10n.choose(simplifiedChinese: "最近 7 天", english: "Recent 7 days"),
                tint: .purple
            ),
            DashboardHighlightItem(
                id: "focus_hrv",
                title: "HRV",
                value: oneDecimal(latestWellnessSample?.hrv),
                trendText: L10n.choose(simplifiedChinese: "今日恢复指标", english: "Today recovery marker"),
                tint: .cyan
            )
        ]
    }

    private var highlightsColumnCount: Int {
        #if os(iOS)
        horizontalSizeClass == .regular ? 4 : 2
        #else
        4
        #endif
    }

    private var groupedDashboardStatCards: [DashboardStatGroup] {
        let byID = Dictionary(uniqueKeysWithValues: dashboardStatCards.map { ($0.id, $0) })
        let loadIDs = ["weekly_tss", "monthly_distance", "ctl", "atl", "tsb"]
        let tissIDs = ["aer_tiss_day", "ana_tiss_day", "aer_lts", "ana_lts", "aer_sts", "ana_sts"]
        let recoveryIDs = ["hrv", "rhr", "sleep"]

        func rows(_ ids: [String]) -> [DashboardStatCardItem] {
            ids.compactMap { byID[$0] }
        }

        return [
            DashboardStatGroup(
                id: "load_core",
                title: L10n.choose(simplifiedChinese: "负荷核心", english: "Load Core"),
                subtitle: L10n.choose(simplifiedChinese: "本周/本月与 CTL/ATL/TSB 主指标", english: "Weekly-monthly load and CTL/ATL/TSB"),
                cards: rows(loadIDs)
            ),
            DashboardStatGroup(
                id: "stress_split",
                title: L10n.choose(simplifiedChinese: "有氧-无氧压力", english: "Aerobic/Anaerobic Stress"),
                subtitle: L10n.choose(simplifiedChinese: "TISS 日负荷与长短期压力拆分", english: "Daily and short/long stress split"),
                cards: rows(tissIDs)
            ),
            DashboardStatGroup(
                id: "recovery_signal",
                title: L10n.choose(simplifiedChinese: "恢复信号", english: "Recovery Signals"),
                subtitle: L10n.choose(simplifiedChinese: "HRV / RHR / Sleep 与 7 天基线", english: "HRV / RHR / sleep against 7d baseline"),
                cards: rows(recoveryIDs)
            )
        ]
    }

    private var dayActivityAggregates: [Date: DayActivityAggregate] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: rangeFilteredActivities) { calendar.startOfDay(for: $0.date) }
        return grouped.mapValues { items in
            DayActivityAggregate(
                tss: items.reduce(0.0) { $0 + Double($1.tss) },
                distanceKm: items.reduce(0.0) { $0 + $1.distanceKm }
            )
        }
    }

    private var metricTrendSeries: [MetricTrendSeries] {
        let calendar = Calendar.current
        let points = fitnessLoad
        guard !points.isEmpty else { return [] }

        let dayMap = dayActivityAggregates
        var rolling7TSS = 0.0
        var weeklyWindow: [Double] = []
        var currentMonthKey: Int?
        var monthDistance = 0.0

        var weeklyPoints: [MetricTrendPoint] = []
        var monthDistancePoints: [MetricTrendPoint] = []
        var aerobicTISSPoints: [MetricTrendPoint] = []
        var anaerobicTISSPoints: [MetricTrendPoint] = []
        var atlPoints: [MetricTrendPoint] = []
        var ctlPoints: [MetricTrendPoint] = []
        var tsbPoints: [MetricTrendPoint] = []
        var aerobicLTSPoints: [MetricTrendPoint] = []
        var anaerobicLTSPoints: [MetricTrendPoint] = []
        var aerobicSTSPoints: [MetricTrendPoint] = []
        var anaerobicSTSPoints: [MetricTrendPoint] = []

        for day in points {
            rolling7TSS += day.tss
            weeklyWindow.append(day.tss)
            if weeklyWindow.count > 7 {
                rolling7TSS -= weeklyWindow.removeFirst()
            }
            weeklyPoints.append(MetricTrendPoint(date: day.date, value: rolling7TSS))

            let comps = calendar.dateComponents([.year, .month], from: day.date)
            let key = (comps.year ?? 0) * 100 + (comps.month ?? 0)
            if currentMonthKey != key {
                currentMonthKey = key
                monthDistance = 0
            }
            monthDistance += dayMap[day.date]?.distanceKm ?? 0
            monthDistancePoints.append(MetricTrendPoint(date: day.date, value: monthDistance))

            aerobicTISSPoints.append(MetricTrendPoint(date: day.date, value: day.aerobicTISS))
            anaerobicTISSPoints.append(MetricTrendPoint(date: day.date, value: day.anaerobicTISS))
            atlPoints.append(MetricTrendPoint(date: day.date, value: day.atl))
            ctlPoints.append(MetricTrendPoint(date: day.date, value: day.ctl))
            tsbPoints.append(MetricTrendPoint(date: day.date, value: day.tsb))
            aerobicLTSPoints.append(MetricTrendPoint(date: day.date, value: day.aerobicLongTermStress))
            anaerobicLTSPoints.append(MetricTrendPoint(date: day.date, value: day.anaerobicLongTermStress))
            aerobicSTSPoints.append(MetricTrendPoint(date: day.date, value: day.aerobicShortTermStress))
            anaerobicSTSPoints.append(MetricTrendPoint(date: day.date, value: day.anaerobicShortTermStress))
        }

        var series: [MetricTrendSeries] = [
            MetricTrendSeries(
                title: "Weekly TSS",
                method: "计算: 周滚动 TSS = 最近7天 DailyTSS 求和",
                tint: .blue,
                unit: "",
                renderStyle: .step,
                points: weeklyPoints
            ),
            MetricTrendSeries(
                title: "Monthly Distance",
                method: "计算: 当月累计距离",
                tint: .green,
                unit: "km",
                renderStyle: .step,
                points: monthDistancePoints
            ),
            MetricTrendSeries(
                title: "Aerobic TISS (Day)",
                method: "计算: AerTISS_d = TSS_d × (1 - AnaShare(IF))",
                tint: .teal,
                unit: "",
                renderStyle: .step,
                points: aerobicTISSPoints
            ),
            MetricTrendSeries(
                title: "Anaerobic TISS (Day)",
                method: "计算: AnaTISS_d = TSS_d × AnaShare(IF)",
                tint: .pink,
                unit: "",
                renderStyle: .step,
                points: anaerobicTISSPoints
            ),
            MetricTrendSeries(
                title: "Coggan ATL",
                method: "计算: ATL_d = ATL_(d-1) + (TSS_d - ATL_(d-1))/7",
                tint: .orange,
                unit: "",
                renderStyle: .line,
                points: atlPoints
            ),
            MetricTrendSeries(
                title: "Coggan CTL",
                method: "计算: CTL_d = CTL_(d-1) + (TSS_d - CTL_(d-1))/42",
                tint: .blue,
                unit: "",
                renderStyle: .line,
                points: ctlPoints
            ),
            MetricTrendSeries(
                title: "Coggan TSB",
                method: "计算: TSB = CTL - ATL",
                tint: .mint,
                unit: "",
                renderStyle: .tsbStepWithZones,
                points: tsbPoints
            ),
            MetricTrendSeries(
                title: "Aerobic TISS Long Term Stress",
                method: "计算: AerLTS_d = AerLTS_(d-1) + (AerTISS_d - AerLTS_(d-1))/42",
                tint: .teal,
                unit: "",
                renderStyle: .line,
                points: aerobicLTSPoints
            ),
            MetricTrendSeries(
                title: "Anaerobic TISS Long Term Stress",
                method: "计算: AnaLTS_d = AnaLTS_(d-1) + (AnaTISS_d - AnaLTS_(d-1))/42",
                tint: .purple,
                unit: "",
                renderStyle: .line,
                points: anaerobicLTSPoints
            ),
            MetricTrendSeries(
                title: "Aerobic TISS Short Term Stress",
                method: "计算: AerSTS_d = AerSTS_(d-1) + (AerTISS_d - AerSTS_(d-1))/7",
                tint: .cyan,
                unit: "",
                renderStyle: .line,
                points: aerobicSTSPoints
            ),
            MetricTrendSeries(
                title: "Anaerobic TISS Short Term Stress",
                method: "计算: AnaSTS_d = AnaSTS_(d-1) + (AnaTISS_d - AnaSTS_(d-1))/7",
                tint: .pink,
                unit: "",
                renderStyle: .line,
                points: anaerobicSTSPoints
            )
        ]

        let wellnessPoints = store.athleteScopedWellnessSamples
            .sorted { $0.date < $1.date }
            .filter { inSelectedTimeRange($0.date) }

        let hrvPoints = wellnessPoints.compactMap { row -> MetricTrendPoint? in
            guard let value = row.hrv else { return nil }
            return MetricTrendPoint(date: row.date, value: value)
        }
        if !hrvPoints.isEmpty {
            series.append(
                MetricTrendSeries(
                    title: "HRV (Daily)",
                    method: "计算: 每日HRV样本原值；7天均值用于对比基线",
                    tint: .cyan,
                    unit: "ms",
                    renderStyle: .line,
                    points: hrvPoints
                )
            )
        }

        let rhrPoints = wellnessPoints.compactMap { row -> MetricTrendPoint? in
            guard let value = row.restingHR else { return nil }
            return MetricTrendPoint(date: row.date, value: value)
        }
        if !rhrPoints.isEmpty {
            series.append(
                MetricTrendSeries(
                    title: "Resting HR (Daily)",
                    method: "计算: 每日静息心率样本原值；7天均值用于观察疲劳",
                    tint: .pink,
                    unit: "bpm",
                    renderStyle: .line,
                    points: rhrPoints
                )
            )
        }

        let sleepPoints = wellnessPoints.compactMap { row -> MetricTrendPoint? in
            guard let value = row.sleepHours else { return nil }
            return MetricTrendPoint(date: row.date, value: value)
        }
        if !sleepPoints.isEmpty {
            series.append(
                MetricTrendSeries(
                    title: "Sleep Hours (Daily)",
                    method: "计算: Sleep(h)=平台上报睡眠时长(秒/分)换算为小时",
                    tint: .indigo,
                    unit: "h",
                    renderStyle: .line,
                    points: sleepPoints
                )
            )
        }

        return series
    }

    private var fitnessYDomain: ClosedRange<Double> {
        let values = displayedFitnessLoad.flatMap { [max(0, $0.ctl), max(0, $0.atl)] }.filter { $0.isFinite }
        guard let maxValue = values.max() else { return 0...100 }
        let top = max(40.0, ceil(maxValue * 1.15 / 10.0) * 10.0)
        return 0...top
    }

    private var tsbYDomain: ClosedRange<Double> {
        let values = displayedFitnessLoad.map(\.tsb).filter { $0.isFinite }
        guard let minValue = values.min(), let maxValue = values.max() else { return -40...40 }
        let lower = floor(min(-40.0, minValue - 4.0) / 5.0) * 5.0
        let upper = ceil(max(40.0, maxValue + 4.0) / 5.0) * 5.0
        return lower...upper
    }

    private func smoothedLoadSeries(_ series: [DailyLoadPoint], window: Int) -> [DailyLoadPoint] {
        guard !series.isEmpty else { return [] }
        let w = max(2, window)
        let alpha = 2.0 / (Double(w) + 1.0)

        var prevCTL = series[0].ctl
        var prevATL = series[0].atl
        var result: [DailyLoadPoint] = []
        result.reserveCapacity(series.count)

        for (index, point) in series.enumerated() {
            if index == 0 {
                result.append(point)
                continue
            }
            prevCTL = alpha * point.ctl + (1.0 - alpha) * prevCTL
            prevATL = alpha * point.atl + (1.0 - alpha) * prevATL

            var row = point
            row.ctl = prevCTL
            row.atl = prevATL
            row.tsb = prevCTL - prevATL
            result.append(row)
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.choose(simplifiedChinese: "训练仪表盘", english: "Performance Dashboard"))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                    Text(
                        L10n.choose(
                            simplifiedChinese: "分组统计卡 + 指标色条，快速看负荷、恢复与训练结构。",
                            english: "Grouped stat cards + metric bars for fast load, recovery, and training structure checks."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Picker("运动", selection: $store.selectedSportFilter) {
                        Text("All Sports").tag(SportType?.none)
                        ForEach(SportType.allCases) { sport in
                            Text(sport.label).tag(Optional(sport))
                        }
                    }
                    .appDropdownTheme()

                    Picker("时间范围", selection: $selectedTimeRange) {
                        ForEach(DashboardTimeRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .appDropdownTheme()

                    Spacer()

                    Text("活动 \(rangeFilteredActivities.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 150), spacing: 10), count: highlightsColumnCount),
                    spacing: 10
                ) {
                    ForEach(dashboardHighlights) { item in
                        DashboardHighlightCard(item: item)
                    }
                }

                let pack = store.scenarioMetricPack
                GroupBox(L10n.choose(simplifiedChinese: "场景化指标", english: "Scenario Metrics")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(L10n.string("Scenario"), selection: $store.selectedScenario) {
                            ForEach(TrainingScenario.allCases) { scenario in
                                Text(scenario.title).tag(scenario)
                            }
                        }
                        .appDropdownTheme()

                        if store.selectedScenario == .enduranceBuild {
                            Picker(L10n.choose(simplifiedChinese: "耐力目标", english: "Endurance Focus"), selection: $store.selectedEnduranceFocus) {
                                ForEach(EnduranceFocus.allCases) { focus in
                                    Text(focus.title).tag(focus)
                                }
                            }
                            .appDropdownTheme()

                            Text(store.selectedEnduranceFocus.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(pack.scenario.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(pack.headline)
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(pack.items) { item in
                                ScenarioMetricCard(item: item)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.choose(simplifiedChinese: "场景动作", english: "Scenario Actions"))
                                .font(.headline)
                            ForEach(pack.actions, id: \.self) { action in
                                Text("• \(action)")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                ForEach(groupedDashboardStatCards) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title)
                            .font(.title3.bold())
                        Text(group.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(minimum: 240)),
                                GridItem(.flexible(minimum: 240)),
                                GridItem(.flexible(minimum: 240))
                            ],
                            spacing: 10
                        ) {
                            ForEach(group.cards) { card in
                                StatCard(
                                    title: card.title,
                                    value: card.value,
                                    method: card.method,
                                    tint: card.tint,
                                    emphasis: card.emphasis
                                )
                            }
                        }
                    }
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Dashboard Metrics Trends")
                        .font(.title3.bold())

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 340)),
                            GridItem(.flexible(minimum: 340))
                        ],
                        spacing: 10
                    ) {
                        ForEach(metricTrendSeries) { series in
                            MetricTrendCard(series: series)
                        }
                    }
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                DashboardActivityStatsPanel(
                    stats: dashboardStats,
                    selectedSport: store.selectedSportFilter
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("指标故事")
                        .font(.title3.bold())

                    ForEach(rangeMetricStories) { story in
                        MetricStoryCard(story: story)
                    }
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Fitness / Fatigue / Status")
                            .font(.title3.bold())
                        Spacer()
                        Picker("显示", selection: $loadDisplayMode) {
                            ForEach(LoadDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .appDropdownTheme()
                    }

                    HStack(spacing: 14) {
                        FitnessHeaderValue(title: "健康度", value: String(format: "%.0f", currentFitness), tint: .blue)
                        FitnessHeaderValue(title: "疲劳度", value: String(format: "%.0f", currentFatigue), tint: .purple)
                        FitnessHeaderValue(
                            title: "状态(TSB)",
                            value: String(format: "%.1f", currentForm),
                            tint: currentForm >= 0 ? .mint : .red
                        )
                        FitnessHeaderValue(title: "状态值", value: "\(currentStatusValuePercent)%", tint: .orange)
                    }
                    .padding(.bottom, 2)

                    if chartDisplayMode == .pie {
                        Chart {
                            if let latest = displayedFitnessLoad.last {
                                SectorMark(
                                    angle: .value("Fatigue", max(0, latest.atl)),
                                    innerRadius: .ratio(0.55),
                                    angularInset: 2
                                )
                                .foregroundStyle(.blue)

                                SectorMark(
                                    angle: .value("Fitness", max(0, latest.ctl)),
                                    innerRadius: .ratio(0.55),
                                    angularInset: 2
                                )
                                .foregroundStyle(.mint)
                            }
                        }
                        .frame(height: 220)
                    } else {
                        Chart(displayedFitnessLoad) { point in
                            switch chartDisplayMode {
                            case .line:
                                // GC 风格上半图：以 Fatigue(ATL) 为主曲线，Fitness(CTL) 作为参考线。
                                AreaMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Fatigue", point.atl)
                                )
                                .foregroundStyle(.blue.opacity(0.18))
                                .interpolationMethod(.linear)

                                LineMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Fatigue", point.atl)
                                )
                                .foregroundStyle(.blue)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.linear)

                                LineMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Fitness", point.ctl)
                                )
                                .foregroundStyle(.blue.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1.2))
                                .interpolationMethod(.linear)
                            case .bar:
                                BarMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Fatigue", max(0, point.atl))
                                )
                                .foregroundStyle(.blue.opacity(0.75))
                            case .pie:
                                BarMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Fatigue", max(0, point.atl))
                                )
                                .foregroundStyle(.blue.opacity(0.75))
                            case .flame:
                                BarMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Fatigue", max(0, point.atl))
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                            }
                        }
                        .frame(height: 220)
                        .chartYScale(domain: fitnessYDomain)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                                    .foregroundStyle(.secondary.opacity(0.25))
                                AxisTick()
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing) { _ in
                                AxisGridLine().foregroundStyle(.secondary.opacity(0.25))
                                AxisTick()
                                AxisValueLabel()
                            }
                        }
                        .chartPlotStyle { plotArea in
                            plotArea.clipped()
                        }
                        .cartesianHoverTip(
                            xTitle: L10n.choose(simplifiedChinese: "日期", english: "Date"),
                            yTitle: L10n.choose(simplifiedChinese: "负荷", english: "Load")
                        )
                    }

                    if chartDisplayMode == .pie {
                        Chart(displayedFitnessLoad.suffix(30)) { point in
                            SectorMark(
                                angle: .value("TSB", max(0, abs(point.tsb))),
                                innerRadius: .ratio(0.55),
                                angularInset: 1
                            )
                            .foregroundStyle(point.tsb >= 0 ? .mint : .orange)
                        }
                        .frame(height: 180)
                    } else {
                        Chart {
                            if let first = displayedFitnessLoad.first?.date, let last = displayedFitnessLoad.last?.date {
                                RectangleMark(
                                    xStart: .value("Start", first),
                                    xEnd: .value("End", last),
                                    yStart: .value("Y Start", -120),
                                    yEnd: .value("Y End", -30)
                                )
                                .foregroundStyle(.red.opacity(0.08))

                                RectangleMark(
                                    xStart: .value("Start", first),
                                    xEnd: .value("End", last),
                                    yStart: .value("Y Start", -30),
                                    yEnd: .value("Y End", -10)
                                )
                                .foregroundStyle(.orange.opacity(0.08))

                                RectangleMark(
                                    xStart: .value("Start", first),
                                    xEnd: .value("End", last),
                                    yStart: .value("Y Start", -10),
                                    yEnd: .value("Y End", 10)
                                )
                                .foregroundStyle(.green.opacity(0.07))

                                RectangleMark(
                                    xStart: .value("Start", first),
                                    xEnd: .value("End", last),
                                    yStart: .value("Y Start", 10),
                                    yEnd: .value("Y End", 25)
                                )
                                .foregroundStyle(.cyan.opacity(0.08))
                            }

                            RuleMark(y: .value("Baseline", 0))
                                .foregroundStyle(.blue.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                            ForEach(displayedFitnessLoad) { point in
                                switch chartDisplayMode {
                                case .line:
                                    LineMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("TSB", point.tsb)
                                    )
                                    .foregroundStyle(.orange)
                                    .interpolationMethod(.linear)
                                case .bar:
                                    BarMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("TSB", point.tsb)
                                    )
                                    .foregroundStyle(.orange.opacity(0.85))
                                case .pie:
                                    BarMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("TSB", point.tsb)
                                    )
                                    .foregroundStyle(.orange.opacity(0.85))
                                case .flame:
                                    BarMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("TSB", abs(point.tsb))
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.yellow, .orange, .red],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                }
                            }

                        }
                        .chartYScale(domain: tsbYDomain)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                                    .foregroundStyle(.secondary.opacity(0.25))
                                AxisTick()
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing) { _ in
                                AxisGridLine().foregroundStyle(.secondary.opacity(0.25))
                                AxisTick()
                                AxisValueLabel()
                            }
                        }
                        .chartPlotStyle { plotArea in
                            plotArea.clipped()
                        }
                        .frame(height: 180)
                        .cartesianHoverTip(
                            xTitle: L10n.choose(simplifiedChinese: "日期", english: "Date"),
                            yTitle: "TSB"
                        )
                    }
                    Text(loadDisplayMode == .smooth7d ? "显示模式: 平滑 7 天（仅影响图表）" : "显示模式: 原始日级（无平滑）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Text("高风险区")
                            .foregroundStyle(.red)
                        Text("过渡期")
                            .foregroundStyle(.orange)
                        Text("最优区")
                            .foregroundStyle(.green)
                        Text("精力充沛")
                            .foregroundStyle(.cyan)
                    }
                    .font(.caption)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(loadMethodText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(loadParameterLines, id: \.self) { line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading) {
                    Text("Daily TSS")
                        .font(.title3.bold())

                    if chartDisplayMode == .pie {
                        Chart(recentLoad.suffix(30)) { point in
                            SectorMark(
                                angle: .value("TSS", max(0, point.tss)),
                                innerRadius: .ratio(0.55),
                                angularInset: 1.0
                            )
                            .foregroundStyle(.indigo.opacity(0.82))
                        }
                        .frame(height: 180)
                    } else {
                        Chart(recentLoad) { point in
                            switch chartDisplayMode {
                            case .line:
                                LineMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("TSS", point.tss)
                                )
                                .foregroundStyle(.indigo)
                                .interpolationMethod(.linear)
                            case .bar:
                                BarMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("TSS", point.tss)
                                )
                                .foregroundStyle(.indigo.gradient)
                            case .pie:
                                BarMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("TSS", point.tss)
                                )
                                .foregroundStyle(.indigo.gradient)
                            case .flame:
                                BarMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("TSS", max(0, point.tss))
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                            }

                        }
                        .frame(height: 180)
                        .cartesianHoverTip(
                            xTitle: L10n.choose(simplifiedChinese: "日期", english: "Date"),
                            yTitle: "TSS"
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(dailyTSSMethodText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(dailyTSSParameterLines, id: \.self) { line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
        .onAppear {
            if store.selectedSportFilter == nil {
                store.selectedSportFilter = .cycling
            }
        }
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

private struct FitnessHeaderValue: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DayActivityAggregate {
    let tss: Double
    let distanceKm: Double
}

private struct MetricTrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

private struct MetricTrendSeries: Identifiable {
    var id: String { title }
    let title: String
    let method: String
    let tint: Color
    let unit: String
    let renderStyle: MetricTrendRenderStyle
    let points: [MetricTrendPoint]
}

private enum MetricTrendRenderStyle {
    case line
    case step
    case tsbStepWithZones
}

private struct MetricTrendCard: View {
    @Environment(\.appChartDisplayMode) private var chartDisplayMode
    let series: MetricTrendSeries

    private var orderedPoints: [MetricTrendPoint] {
        series.points.sorted { $0.date < $1.date }
    }

    private var latestValue: Double {
        orderedPoints.last?.value ?? 0
    }

    private var displayValue: Double {
        latestValue
    }

    private var displayDate: Date? {
        orderedPoints.last?.date
    }

    private var valueText: String {
        if series.unit == "km" {
            return String(format: "%.1f %@", displayValue, series.unit)
        }
        return series.unit.isEmpty ? String(format: "%.1f", displayValue) : String(format: "%.1f %@", displayValue, series.unit)
    }

    private var tsbDomain: ClosedRange<Double> {
        let values = orderedPoints.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return -40...40 }
        let lower = floor(min(-40.0, minValue - 4.0) / 5.0) * 5.0
        let upper = ceil(max(40.0, maxValue + 4.0) / 5.0) * 5.0
        return lower...upper
    }

    private var steppedPositiveDomain: ClosedRange<Double> {
        let values = orderedPoints.map(\.value).filter { $0.isFinite }
        guard let maxValue = values.max() else { return 0...100 }
        return 0...max(40, ceil(maxValue * 1.12 / 10.0) * 10.0)
    }

    private var lineDomain: ClosedRange<Double> {
        let values = orderedPoints.map(\.value).filter { $0.isFinite }
        guard let minValue = values.min(), let maxValue = values.max() else { return 0...100 }
        let span = max(1.0, maxValue - minValue)
        let lower = floor((minValue - span * 0.12) / 5.0) * 5.0
        let upper = ceil((maxValue + span * 0.12) / 5.0) * 5.0
        return lower...max(lower + 10.0, upper)
    }

    private var chartDomain: ClosedRange<Double> {
        switch series.renderStyle {
        case .line:
            return lineDomain
        case .step:
            return steppedPositiveDomain
        case .tsbStepWithZones:
            return tsbDomain
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.title)
                    .font(.headline)
                Spacer()
                Text(valueText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(series.tint)
            }

            if let displayDate {
                Text(displayDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if chartDisplayMode == .pie {
                Chart(orderedPoints.suffix(24)) { point in
                    SectorMark(
                        angle: .value(series.title, max(0, abs(point.value))),
                        innerRadius: .ratio(0.56),
                        angularInset: 1
                    )
                    .foregroundStyle(series.tint.opacity(0.8))
                }
                .frame(height: 120)
            } else {
                Chart {
                    if series.renderStyle == .tsbStepWithZones,
                       let first = orderedPoints.first?.date,
                       let last = orderedPoints.last?.date {
                        RectangleMark(
                            xStart: .value("Start", first),
                            xEnd: .value("End", last),
                            yStart: .value("Y Start", -40),
                            yEnd: .value("Y End", -25)
                        )
                        .foregroundStyle(.red.opacity(0.10))

                        RectangleMark(
                            xStart: .value("Start", first),
                            xEnd: .value("End", last),
                            yStart: .value("Y Start", -25),
                            yEnd: .value("Y End", -10)
                        )
                        .foregroundStyle(.orange.opacity(0.08))

                        RectangleMark(
                            xStart: .value("Start", first),
                            xEnd: .value("End", last),
                            yStart: .value("Y Start", -10),
                            yEnd: .value("Y End", 10)
                        )
                        .foregroundStyle(.green.opacity(0.08))

                        RectangleMark(
                            xStart: .value("Start", first),
                            xEnd: .value("End", last),
                            yStart: .value("Y Start", 10),
                            yEnd: .value("Y End", 25)
                        )
                        .foregroundStyle(.cyan.opacity(0.08))

                        RuleMark(y: .value("Baseline", 0))
                            .foregroundStyle(.secondary.opacity(0.45))
                            .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                    }

                    ForEach(orderedPoints) { point in
                        switch chartDisplayMode {
                        case .line:
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(series.title, point.value)
                            )
                            .foregroundStyle(series.tint)
                            .interpolationMethod(series.renderStyle == .line ? .linear : .stepCenter)
                        case .bar:
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(series.title, point.value)
                            )
                            .foregroundStyle(series.tint.opacity(0.85))
                        case .pie:
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(series.title, point.value)
                            )
                            .foregroundStyle(series.tint.opacity(0.85))
                        case .flame:
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(series.title, max(0, abs(point.value)))
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange, .red],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                        }
                    }
                }
                .frame(height: 120)
                .chartYScale(domain: chartDomain)
                .cartesianHoverTip(
                    xTitle: L10n.choose(simplifiedChinese: "日期", english: "Date"),
                    yTitle: series.unit.isEmpty ? L10n.choose(simplifiedChinese: "数值", english: "Value") : series.unit
                )
            }

            Text(series.method)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(.background.tertiary.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
    }
}


private struct DashboardHighlightCard: View {
    let item: DashboardView.DashboardHighlightItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(item.value)
                .font(.title2.weight(.bold))
                .foregroundStyle(item.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(item.trendText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(item.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let method: String
    let tint: Color
    let emphasis: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.16))
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(6, proxy.size.width * min(max(emphasis, 0), 1)))
                }
            }
            .frame(height: 6)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(tint)
            }
            Text(method)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MetricStoryCard: View {
    let story: MetricStory

    private var color: Color {
        switch story.tone {
        case .positive: return .green
        case .neutral: return .blue
        case .warning: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(story.title)
                .font(.headline)
                .foregroundStyle(color)
            Text(story.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ScenarioMetricCard: View {
    let item: ScenarioMetricItem

    private var color: Color {
        switch item.tone {
        case .good: return .green
        case .watch: return .orange
        case .risk: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.headline)
                .foregroundStyle(color)
            Text(item.value)
                .font(.title3.bold())
            Text(item.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DashboardActivityStatsPanel: View {
    let stats: DashboardActivityStats
    let selectedSport: SportType?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("训练统计")
                    .font(.title3.bold())
                Spacer()
                Text(selectedSport?.label ?? "All Sports")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.background.tertiary, in: Capsule())
            }

            if stats.totalActivities == 0 {
                Text("暂无活动数据。先导入 FIT/TCX/GPX 或同步 Strava / Intervals。")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 110)), count: 6),
                    spacing: 8
                ) {
                    SummaryMiniMetric(title: "活动", value: "\(stats.totalActivities)")
                    SummaryMiniMetric(title: "周数", value: "\(stats.weekCount)")
                    SummaryMiniMetric(title: "天数", value: "\(stats.spanDays)")
                    SummaryMiniMetric(title: "活跃天数", value: "\(stats.activeDays)")
                    SummaryMiniMetric(title: "距离", value: stats.distanceKm.distanceText)
                    SummaryMiniMetric(title: "持续时间", value: stats.durationSec.compactDurationText)
                    SummaryMiniMetric(title: "滑行", value: stats.coastSec.compactDurationText)
                    SummaryMiniMetric(title: "爬升", value: "\(stats.elevationM)m")
                    SummaryMiniMetric(title: "负荷", value: "\(stats.totalLoad)")
                    SummaryMiniMetric(title: "举起的重量", value: "\(stats.liftedKg) kg")
                    SummaryMiniMetric(title: "热量", value: "\(stats.calories)")
                    SummaryMiniMetric(title: "做功", value: "\(stats.workKJ) kJ")
                }

                HStack(spacing: 10) {
                    ForEach(stats.bySport) { row in
                        SportBreakdownCard(row: row)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    ZoneDistributionCard(title: "综合区间", zones: stats.overallZones)
                    ZoneDistributionCard(title: "功率区间", zones: stats.powerZones)
                    ZoneDistributionCard(title: "心率区间", zones: stats.heartRateZones)
                }

                HStack(alignment: .top, spacing: 10) {
                    if let best = stats.bestTemplate {
                        BestTemplateCard(best: best, mix: stats.mix)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(stats.templates) { item in
                                DistributionTemplateCard(item: item)
                            }
                        }
                    }
                }

                Text("说明: 综合区间优先使用功率区间，其次心率区间；滑行/爬升/热量为无原始传感器时的估算。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct SummaryMiniMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.background.tertiary.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SportBreakdownCard: View {
    let row: SportAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.sport.label)
                .font(.headline)
                .foregroundStyle(.blue)
            Text("\(row.durationSec.compactDurationText) · \(row.distanceKm.distanceText)")
                .font(.title3.bold().monospacedDigit())
            Text("\(row.count) 次 · 负荷 \(row.load)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.background.tertiary.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ZoneDistributionCard: View {
    let title: String
    let zones: [ZoneDurationStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
            ForEach(zones) { zone in
                HStack(spacing: 8) {
                    Text(zone.name)
                        .font(.headline)
                        .frame(width: 34, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.background.tertiary)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(zone.color)
                                .frame(width: geo.size.width * zone.ratio)
                        }
                    }
                    .frame(height: 16)
                    Text(zone.durationSec.compactDurationText)
                        .font(.headline.monospacedDigit())
                        .frame(width: 74, alignment: .trailing)
                    Text(String(format: "%.1f%%", zone.percent))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(.background.tertiary.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct BestTemplateCard: View {
    let best: DistributionTemplateScore
    let mix: IntensityMix

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(best.template.title) \(String(format: "%.2f", mix.pyramidIndex))")
                .font(.title3.bold())
            DistributionBars(low: mix.lowPct, mid: mix.midPct, high: mix.highPct)
            Text(String(format: "Z1+2 %.1f%%", mix.lowPct))
                .font(.headline.monospacedDigit())
            Text(String(format: "Z3+4+SS %.1f%%", mix.midPct))
                .font(.headline.monospacedDigit())
            Text(String(format: "Z5+ %.1f%%", mix.highPct))
                .font(.headline.monospacedDigit())
        }
        .frame(width: 240, alignment: .leading)
        .padding(10)
        .background(.background.tertiary.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DistributionTemplateCard: View {
    let item: DistributionTemplateScore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.template.title)
                .font(.headline)
            DistributionBars(low: item.template.lowPct, mid: item.template.midPct, high: item.template.highPct)
            Text(String(format: "拟合 %.1f", item.score))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 150, alignment: .leading)
        .padding(8)
        .background(
            item.isBest ? Color.blue.opacity(0.16) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}

private struct DistributionBars: View {
    let low: Double
    let mid: Double
    let high: Double

    var body: some View {
        VStack(spacing: 6) {
            DistributionBar(value: low, color: .green)
            DistributionBar(value: mid, color: .orange)
            DistributionBar(value: high, color: .pink)
        }
    }
}

private struct DistributionBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(.background.tertiary)
                RoundedRectangle(cornerRadius: 7)
                    .fill(color)
                    .frame(width: geo.size.width * min(max(value / 100.0, 0), 1))
            }
        }
        .frame(height: 14)
    }
}

private struct DashboardActivityStats {
    var totalActivities: Int
    var weekCount: Int
    var spanDays: Int
    var activeDays: Int
    var distanceKm: Double
    var durationSec: Int
    var coastSec: Int
    var elevationM: Int
    var totalLoad: Int
    var liftedKg: Int
    var calories: Int
    var workKJ: Int
    var bySport: [SportAggregate]
    var overallZones: [ZoneDurationStat]
    var powerZones: [ZoneDurationStat]
    var heartRateZones: [ZoneDurationStat]
    var mix: IntensityMix
    var templates: [DistributionTemplateScore]
    var bestTemplate: DistributionTemplateScore?
}

private struct SportAggregate: Identifiable {
    var id: String { sport.rawValue }
    let sport: SportType
    let count: Int
    let durationSec: Int
    let distanceKm: Double
    let load: Int
}

private struct ZoneDurationStat: Identifiable {
    var id: String { name }
    let name: String
    let durationSec: Int
    let percent: Double
    let color: Color

    var ratio: Double {
        percent / 100.0
    }
}

private struct IntensityMix {
    let lowPct: Double
    let midPct: Double
    let highPct: Double

    var pyramidIndex: Double {
        lowPct / max(midPct, 0.1)
    }
}

private struct DistributionTemplateScore: Identifiable {
    var id: String { template.rawValue }
    let template: DistributionTemplate
    let score: Double
    let isBest: Bool
}

private enum DistributionTemplate: String, CaseIterable {
    case polarized
    case pyramidal
    case threshold
    case hiit
    case base
    case even

    var title: String {
        switch self {
        case .polarized: return "极化型"
        case .pyramidal: return "金字塔型"
        case .threshold: return "阈值型"
        case .hiit: return "HIIT型"
        case .base: return "基础型"
        case .even: return "均匀型"
        }
    }

    var lowPct: Double {
        switch self {
        case .polarized: return 75
        case .pyramidal: return 70
        case .threshold: return 45
        case .hiit: return 25
        case .base: return 85
        case .even: return 34
        }
    }

    var midPct: Double {
        switch self {
        case .polarized: return 5
        case .pyramidal: return 20
        case .threshold: return 40
        case .hiit: return 30
        case .base: return 12
        case .even: return 33
        }
    }

    var highPct: Double {
        switch self {
        case .polarized: return 20
        case .pyramidal: return 10
        case .threshold: return 15
        case .hiit: return 45
        case .base: return 3
        case .even: return 33
        }
    }
}

private enum DashboardActivityStatsBuilder {
    private static let zoneOrderWithSS = ["Z1", "Z2", "Z3", "Z4", "Z5", "Z6", "Z7", "SS"]
    private static let zoneOrderNoSS = ["Z1", "Z2", "Z3", "Z4", "Z5", "Z6", "Z7"]

    static func build(activities: [Activity], profile: AthleteProfile) -> DashboardActivityStats {
        let calendar = Calendar.current
        let sorted = activities.sorted { $0.date < $1.date }

        let totalActivities = sorted.count
        let spanDays: Int = {
            guard let first = sorted.first?.date, let last = sorted.last?.date else { return 0 }
            let firstDay = calendar.startOfDay(for: first)
            let lastDay = calendar.startOfDay(for: last)
            return (calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1
        }()

        let weekCount = spanDays > 0 ? Int(ceil(Double(spanDays) / 7.0)) : 0
        let activeDays = Set(sorted.map { calendar.startOfDay(for: $0.date) }).count
        let distanceKm = sorted.reduce(0.0) { $0 + $1.distanceKm }
        let durationSec = sorted.reduce(0) { $0 + $1.durationSec }
        let totalLoad = sorted.reduce(0) { $0 + $1.tss }

        var coastSec = 0
        var elevationM = 0
        var liftedKg = 0
        var calories = 0
        var workKJ = 0

        var overallSec = Dictionary(uniqueKeysWithValues: zoneOrderWithSS.map { ($0, 0) })
        var powerSec = Dictionary(uniqueKeysWithValues: zoneOrderWithSS.map { ($0, 0) })
        var hrSec = Dictionary(uniqueKeysWithValues: zoneOrderNoSS.map { ($0, 0) })

        for activity in sorted {
            guard activity.durationSec > 0 else { continue }
            let sec = activity.durationSec
            let hours = Double(sec) / 3600.0

            if let np = activity.normalizedPower {
                let kJ = Int((Double(np) * Double(sec) / 1000.0).rounded())
                workKJ += kJ
                calories += kJ
            } else {
                calories += Int((hours * 450.0).rounded())
            }

            if activity.sport == .cycling {
                coastSec += Int((Double(sec) * 0.06).rounded())
            }

            elevationM += estimatedElevationMeters(activity: activity)
            if activity.sport == .strength {
                liftedKg += Int((Double(sec) / 60.0 * 55.0).rounded())
            }

            let powerRatio = powerIntensityRatio(activity: activity, profile: profile)
            let hrRatio = heartRateRatio(activity: activity, profile: profile)

            if let powerRatio {
                let zone = powerZoneWithSS(from: powerRatio)
                powerSec[zone, default: 0] += sec
                overallSec[zone, default: 0] += sec
            } else if let hrRatio {
                let zone = heartRateZone(from: hrRatio)
                overallSec[zone, default: 0] += sec
            } else {
                let zone = fallbackZoneByTSSPerHour(activity: activity)
                overallSec[zone, default: 0] += sec
            }

            if let hrRatio {
                let zone = heartRateZone(from: hrRatio)
                hrSec[zone, default: 0] += sec
            }
        }

        let bySport = SportType.allCases.compactMap { sport -> SportAggregate? in
            let rows = sorted.filter { $0.sport == sport }
            guard !rows.isEmpty else { return nil }
            return SportAggregate(
                sport: sport,
                count: rows.count,
                durationSec: rows.reduce(0) { $0 + $1.durationSec },
                distanceKm: rows.reduce(0.0) { $0 + $1.distanceKm },
                load: rows.reduce(0) { $0 + $1.tss }
            )
        }

        let overallZones = buildZoneStats(order: zoneOrderWithSS, source: overallSec)
        let powerZones = buildZoneStats(order: zoneOrderWithSS, source: powerSec)
        let heartRateZones = buildZoneStats(order: zoneOrderNoSS, source: hrSec)

        let mix = buildMix(overall: overallSec)
        let templateScores = DistributionTemplate.allCases.map { template in
            let mse =
                pow(mix.lowPct - template.lowPct, 2) +
                pow(mix.midPct - template.midPct, 2) +
                pow(mix.highPct - template.highPct, 2)
            return (template: template, score: sqrt(mse / 3.0))
        }
        let bestTemplateType = templateScores.min { $0.score < $1.score }?.template
        let templates = templateScores.map {
            DistributionTemplateScore(template: $0.template, score: $0.score, isBest: $0.template == bestTemplateType)
        }
        let bestTemplate = templates.first { $0.isBest }

        return DashboardActivityStats(
            totalActivities: totalActivities,
            weekCount: weekCount,
            spanDays: spanDays,
            activeDays: activeDays,
            distanceKm: distanceKm,
            durationSec: durationSec,
            coastSec: coastSec,
            elevationM: elevationM,
            totalLoad: totalLoad,
            liftedKg: liftedKg,
            calories: calories,
            workKJ: workKJ,
            bySport: bySport,
            overallZones: overallZones,
            powerZones: powerZones,
            heartRateZones: heartRateZones,
            mix: mix,
            templates: templates,
            bestTemplate: bestTemplate
        )
    }

    private static func buildZoneStats(order: [String], source: [String: Int]) -> [ZoneDurationStat] {
        let total = max(1, source.values.reduce(0, +))
        return order.map { name in
            let sec = source[name] ?? 0
            let percent = Double(sec) * 100.0 / Double(total)
            return ZoneDurationStat(
                name: name,
                durationSec: sec,
                percent: percent,
                color: zoneColor(name: name)
            )
        }
    }

    private static func buildMix(overall: [String: Int]) -> IntensityMix {
        let total = max(1, overall.values.reduce(0, +))
        let low = (overall["Z1"] ?? 0) + (overall["Z2"] ?? 0)
        let mid = (overall["Z3"] ?? 0) + (overall["Z4"] ?? 0) + (overall["SS"] ?? 0)
        let high = (overall["Z5"] ?? 0) + (overall["Z6"] ?? 0) + (overall["Z7"] ?? 0)
        return IntensityMix(
            lowPct: Double(low) * 100.0 / Double(total),
            midPct: Double(mid) * 100.0 / Double(total),
            highPct: Double(high) * 100.0 / Double(total)
        )
    }

    private static func powerIntensityRatio(activity: Activity, profile: AthleteProfile) -> Double? {
        guard let np = activity.normalizedPower, np > 0 else { return nil }
        let ftp = max(profile.ftpWatts(for: activity.sport), 1)
        return max(0.3, min(1.8, Double(np) / Double(ftp)))
    }

    private static func heartRateRatio(activity: Activity, profile: AthleteProfile) -> Double? {
        guard let hr = activity.avgHeartRate, hr > 0 else { return nil }
        let threshold = max(profile.thresholdHeartRate(for: activity.sport, on: activity.date), 1)
        return max(0.3, min(1.4, Double(hr) / Double(threshold)))
    }

    private static func powerZoneWithSS(from ratio: Double) -> String {
        switch ratio {
        case ..<0.56: return "Z1"
        case ..<0.76: return "Z2"
        case ..<0.88: return "Z3"
        case ..<0.94: return "SS"
        case ..<1.06: return "Z4"
        case ..<1.21: return "Z5"
        case ..<1.50: return "Z6"
        default: return "Z7"
        }
    }

    private static func heartRateZone(from ratio: Double) -> String {
        switch ratio {
        case ..<0.68: return "Z1"
        case ..<0.78: return "Z2"
        case ..<0.88: return "Z3"
        case ..<0.94: return "Z4"
        case ..<1.00: return "Z5"
        case ..<1.06: return "Z6"
        default: return "Z7"
        }
    }

    private static func fallbackZoneByTSSPerHour(activity: Activity) -> String {
        let hours = max(Double(activity.durationSec) / 3600.0, 1.0 / 60.0)
        let density = Double(activity.tss) / hours
        switch density {
        case ..<40: return "Z1"
        case ..<55: return "Z2"
        case ..<70: return "Z3"
        case ..<85: return "Z4"
        case ..<100: return "Z5"
        case ..<115: return "Z6"
        default: return "Z7"
        }
    }

    private static func estimatedElevationMeters(activity: Activity) -> Int {
        switch activity.sport {
        case .cycling:
            return Int((activity.distanceKm * 18.0).rounded())
        case .running:
            return Int((activity.distanceKm * 9.0).rounded())
        case .swimming, .strength:
            return 0
        }
    }

    private static func zoneColor(name: String) -> Color {
        switch name {
        case "Z1": return .teal
        case "Z2": return .green
        case "Z3": return .yellow
        case "Z4": return .orange
        case "Z5": return .pink
        case "Z6": return .purple
        case "Z7": return .gray
        case "SS": return .mint
        default: return .gray
        }
    }
}

private extension Double {
    var distanceText: String {
        if self >= 100 {
            return String(format: "%.0f km", self)
        }
        return String(format: "%.1f km", self)
    }
}

private extension Int {
    var compactDurationText: String {
        let h = self / 3600
        let m = (self % 3600) / 60
        let s = self % 60
        if h > 0 { return "\(h)h\(m)m" }
        if m > 0 { return "\(m)m\(s)s" }
        return "\(s)s"
    }
}
