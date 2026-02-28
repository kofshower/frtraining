import SwiftUI
import Charts

struct InsightsView: View {
    @Environment(\.appChartDisplayMode) private var chartDisplayMode
    @EnvironmentObject private var store: AppStore

    struct InsightStatItem: Identifiable {
        let id: String
        let title: String
        let value: String
        let subtitle: String
        let tint: Color
        let emphasis: Double
    }

    struct InsightStatGroup: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let items: [InsightStatItem]
    }

    private var recentSeries: [DailyLoadPoint] {
        Array(store.loadSeries.suffix(21))
    }

    private var freshnessSeries: [DailyLoadPoint] {
        recentSeries.sorted { $0.date < $1.date }
    }

    private var freshnessYDomain: ClosedRange<Double> {
        guard !freshnessSeries.isEmpty else { return -40...25 }
        let minTSB = freshnessSeries.map(\.tsb).min() ?? -20
        let maxTSB = freshnessSeries.map(\.tsb).max() ?? 10
        let lower = min(-40, floor((minTSB - 4) / 5) * 5)
        let upper = max(25, ceil((maxTSB + 4) / 5) * 5)
        return lower...upper
    }

    private var performanceEstimate: SportPerformanceEstimate {
        SportPerformanceEstimator.estimate(
            activities: store.athleteScopedActivities,
            loadSeries: store.loadSeries,
            profile: store.profile,
            wellness: store.athleteScopedWellnessSamples
        )
    }

    private var sportMix: [SportMixPoint] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -30, to: Date()) else { return [] }

        let grouped = Dictionary(grouping: store.filteredActivities.filter { $0.date >= start }) { $0.sport }
        return grouped.map { sport, activities in
            SportMixPoint(sport: sport, totalTSS: activities.reduce(0) { $0 + $1.tss })
        }
    }

    private var wellnessDescending: [WellnessSample] {
        store.athleteScopedWellnessSamples.sortedByDateDescending()
    }

    private var wellnessTrend: [WellnessTrendPoint] {
        Array(wellnessDescending.prefix(30).reversed()).map {
            WellnessTrendPoint(
                date: $0.date,
                hrv: $0.hrv,
                restingHR: $0.restingHR,
                sleepHours: $0.sleepHours,
                sleepScore: $0.sleepScore
            )
        }
    }

    private var latestWellness: WellnessTrendPoint? {
        wellnessTrend.last
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

    private var plannedLoad: [PlannedLoadPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 20, to: today) else { return [] }

        var minutesByDay: [Date: Int] = [:]
        for workout in store.athleteScopedPlannedWorkouts {
            guard let date = workout.scheduledDate else { continue }
            let day = calendar.startOfDay(for: date)
            guard day >= today, day <= end else { continue }
            minutesByDay[day, default: 0] += workout.totalMinutes
        }

        var rows: [PlannedLoadPoint] = []
        var cursor = today
        while cursor <= end {
            rows.append(PlannedLoadPoint(date: cursor, minutes: minutesByDay[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return rows
    }

    private var upcomingEvents: [CalendarEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 14, to: today) else { return [] }

        return store.athleteScopedCalendarEvents
            .filter { event in
                let day = calendar.startOfDay(for: event.startDate)
                return day >= today && day <= end
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private var eventMix: [EventMixPoint] {
        let grouped = Dictionary(grouping: upcomingEvents) { $0.category }
        return grouped
            .map { EventMixPoint(category: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.category < rhs.category
            }
    }

    private var recentCachedActivityInsights: [RecentActivityInsight] {
        Array(store.filteredActivities.prefix(16))
            .compactMap { activity in
                guard let insight = store.activityMetricInsight(for: activity.id) else { return nil }
                return RecentActivityInsight(activity: activity, insight: insight)
            }
            .sorted { lhs, rhs in
                if lhs.activity.date != rhs.activity.date { return lhs.activity.date > rhs.activity.date }
                return lhs.insight.generatedAt > rhs.insight.generatedAt
            }
    }

    private func oneDecimal(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f", value)
    }

    private func clampLevel(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private var insightStatGroups: [InsightStatGroup] {
        let summary = store.summary
        let latestHRV = latestWellness?.hrv ?? avg7HRV
        let latestRHR = latestWellness?.restingHR ?? avg7RHR
        let latestSleep = latestWellness?.sleepHours ?? avg7SleepHours
        let readiness = store.recommendation?.readinessScore

        let load = InsightStatGroup(
            id: "load",
            title: L10n.choose(simplifiedChinese: "训练状态", english: "Training State"),
            subtitle: L10n.choose(simplifiedChinese: "当前负荷与新鲜度", english: "Current load and freshness"),
            items: [
                InsightStatItem(
                    id: "ctl",
                    title: "CTL",
                    value: String(format: "%.1f", summary.currentCTL),
                    subtitle: L10n.choose(simplifiedChinese: "慢性负荷", english: "Chronic load"),
                    tint: .blue,
                    emphasis: clampLevel(summary.currentCTL / 120.0)
                ),
                InsightStatItem(
                    id: "atl",
                    title: "ATL",
                    value: String(format: "%.1f", summary.currentATL),
                    subtitle: L10n.choose(simplifiedChinese: "急性负荷", english: "Acute load"),
                    tint: .orange,
                    emphasis: clampLevel(summary.currentATL / 120.0)
                ),
                InsightStatItem(
                    id: "tsb",
                    title: "TSB",
                    value: String(format: "%.1f", summary.currentTSB),
                    subtitle: L10n.choose(simplifiedChinese: "新鲜度", english: "Freshness"),
                    tint: summary.currentTSB >= 0 ? .mint : .red,
                    emphasis: clampLevel(abs(summary.currentTSB) / 30.0)
                )
            ]
        )

        let recovery = InsightStatGroup(
            id: "recovery",
            title: L10n.choose(simplifiedChinese: "恢复信号", english: "Recovery Signals"),
            subtitle: L10n.choose(simplifiedChinese: "生理状态概览", english: "Wellness snapshot"),
            items: [
                InsightStatItem(
                    id: "hrv",
                    title: "HRV",
                    value: oneDecimal(latestHRV),
                    subtitle: "RMSSD",
                    tint: .cyan,
                    emphasis: clampLevel(
                        (latestHRV ?? 0) > 0 && store.profile.hrvBaseline > 0
                            ? ((latestHRV ?? 0) / store.profile.hrvBaseline) / 1.2
                            : 0.0
                    )
                ),
                InsightStatItem(
                    id: "rhr",
                    title: "RHR",
                    value: oneDecimal(latestRHR),
                    subtitle: "bpm",
                    tint: .pink,
                    emphasis: clampLevel((95.0 - (latestRHR ?? 0)) / 35.0)
                ),
                InsightStatItem(
                    id: "sleep",
                    title: "Sleep",
                    value: oneDecimal(latestSleep),
                    subtitle: L10n.choose(simplifiedChinese: "小时", english: "hours"),
                    tint: .indigo,
                    emphasis: clampLevel((latestSleep ?? 0) / 8.0)
                )
            ]
        )

        let ai = InsightStatGroup(
            id: "ai",
            title: L10n.choose(simplifiedChinese: "AI 教练", english: "AI Coach"),
            subtitle: L10n.choose(simplifiedChinese: "策略与执行建议", english: "Strategy guidance"),
            items: [
                InsightStatItem(
                    id: "readiness",
                    title: L10n.choose(simplifiedChinese: "准备度", english: "Readiness"),
                    value: readiness.map(String.init) ?? "--",
                    subtitle: "0-100",
                    tint: .green,
                    emphasis: clampLevel(Double(readiness ?? 0) / 100.0)
                ),
                InsightStatItem(
                    id: "phase",
                    title: L10n.choose(simplifiedChinese: "阶段", english: "Phase"),
                    value: store.recommendation?.phase ?? "--",
                    subtitle: store.aiCoachSource,
                    tint: .teal,
                    emphasis: 0.5
                ),
                InsightStatItem(
                    id: "updated",
                    title: L10n.choose(simplifiedChinese: "更新时间", english: "Updated"),
                    value: store.aiCoachUpdatedAt?.formatted(date: .omitted, time: .shortened) ?? "--",
                    subtitle: L10n.choose(simplifiedChinese: "最近 GPT 结果", english: "Latest GPT refresh"),
                    tint: .blue,
                    emphasis: 0.45
                )
            ]
        )

        return [load, recovery, ai]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.choose(simplifiedChinese: "洞察", english: "Insights"))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                    Text(
                        L10n.choose(
                            simplifiedChinese: "分组统计卡聚焦训练状态、恢复信号与 AI 决策优先级。",
                            english: "Grouped cards focus on training state, recovery signals, and AI decision priorities."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                ForEach(insightStatGroups, id: \.id) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title)
                            .font(.title3.bold())
                        Text(group.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(minimum: 220)),
                                GridItem(.flexible(minimum: 220)),
                                GridItem(.flexible(minimum: 220))
                            ],
                            spacing: 10
                        ) {
                            ForEach(group.items, id: \.id) { item in
                                InsightStatCard(item: item)
                            }
                        }
                    }
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                }

                let pack = store.scenarioMetricPack
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "场景视角", english: "Scenario Lens"))
                        .font(.headline)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(L10n.choose(simplifiedChinese: "场景", english: "Scenario"), selection: $store.selectedScenario) {
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

                            Text(pack.headline)
                                .font(.headline)

                            ForEach(pack.items.prefix(3)) { item in
                                HStack {
                                    Text(item.name)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text(item.value)
                                        .font(.subheadline.monospacedDigit())
                                }
                                Text(item.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }

                let recommendation = store.recommendation
                GroupBox(L10n.choose(simplifiedChinese: "AI 教练", english: "AI Coach")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(L10n.choose(simplifiedChinese: "来源", english: "Source")): \(store.aiCoachSource)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let updatedAt = store.aiCoachUpdatedAt {
                                Text("· \(L10n.choose(simplifiedChinese: "更新时间", english: "Updated")) \(updatedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(store.isRefreshingAICoach ? L10n.choose(simplifiedChinese: "刷新中...", english: "Refreshing...") : L10n.choose(simplifiedChinese: "刷新 GPT 教练", english: "Refresh GPT Coach")) {
                                Task { await store.refreshAIRecommendationFromGPT() }
                            }
                            .disabled(store.isRefreshingAICoach)
                        }

                        if let status = store.aiCoachStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let recommendation {
                            Text("\(L10n.choose(simplifiedChinese: "准备度", english: "Readiness")): \(recommendation.readinessScore)/100 · \(recommendation.phase)")
                                .font(.title3.bold())
                            Text(recommendation.todayFocus)
                                .foregroundStyle(.secondary)

                            if !recommendation.weeklyFocus.isEmpty {
                                Divider()
                                Text(L10n.choose(simplifiedChinese: "本周重点", english: "Weekly Focus"))
                                    .font(.headline)
                                ForEach(recommendation.weeklyFocus, id: \.self) { line in
                                    Text("• \(line)")
                                        .font(.subheadline)
                                }
                            }

                            if !recommendation.cautions.isEmpty {
                                Divider()
                                Text(L10n.choose(simplifiedChinese: "风险提示", english: "Risk Flags"))
                                    .font(.headline)
                                ForEach(recommendation.cautions, id: \.self) { line in
                                    Text("• \(line)")
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                }
                            }
                        } else {
                            Text(L10n.choose(simplifiedChinese: "尚无 GPT 结果，请点击刷新 GPT 教练。", english: "No GPT result yet. Click Refresh GPT Coach."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox(L10n.choose(simplifiedChinese: "近期活动 GPT 解读（缓存）", english: "Recent Activity GPT Insights (Cached)")) {
                    if recentCachedActivityInsights.isEmpty {
                        Text(L10n.choose(simplifiedChinese: "暂无缓存活动解读。打开 Activity 详情后会自动生成并持久化，Insights 直接复用。", english: "No cached activity interpretations yet. Open Activity details to generate and persist them, then Insights reuses them."))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recentCachedActivityInsights.prefix(5)) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(row.activity.sport.label) · \(row.activity.date.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.subheadline.bold())
                                        Spacer()
                                        Text("\(L10n.choose(simplifiedChinese: "缓存于", english: "cached")) \(row.insight.generatedAt.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(row.insight.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if row.id != recentCachedActivityInsights.prefix(5).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                let estimate = performanceEstimate
                GroupBox(L10n.choose(simplifiedChinese: "表现评估器（骑行 + 跑步）", english: "Performance Estimator (Cycling + Running)")) {
                    VStack(alignment: .leading, spacing: 12) {
                        PerformanceEstimateCard(
                            title: "Cycling",
                            headline: "60min 功率估算: \(estimate.cycling.estimatedHourPower) W",
                            subheadline: "Readiness \(estimate.cycling.readinessScore)/100 · Confidence \(estimate.cycling.confidence)",
                            method: estimate.cycling.method,
                            parameters: estimate.cycling.parameters
                        )

                        Divider()

                        PerformanceEstimateCard(
                            title: "Running",
                            headline: runningHeadline(estimate.running),
                            subheadline: "Readiness \(estimate.running.readinessScore)/100 · Confidence \(estimate.running.confidence)",
                            method: estimate.running.method,
                            parameters: estimate.running.parameters
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox(L10n.choose(simplifiedChinese: "准备度", english: "Readiness")) {
                    let tsb = store.summary.currentTSB
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: L10n.choose(simplifiedChinese: "当前 TSB: %.1f", english: "Current TSB: %.1f"), tsb))
                            .font(.title3.bold())
                        Text(readinessAdvice(tsb: tsb))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox(L10n.choose(simplifiedChinese: "新鲜度趋势（21天）", english: "Freshness Trend (21d)")) {
                    if freshnessSeries.isEmpty {
                        Text(L10n.choose(simplifiedChinese: "暂无负荷数据。", english: "No load data yet."))
                            .foregroundStyle(.secondary)
                    } else {
                        if chartDisplayMode == .pie {
                            Chart(freshnessSeries) { point in
                                SectorMark(
                                    angle: .value("TSB", max(0, abs(point.tsb))),
                                    innerRadius: .ratio(0.55),
                                    angularInset: 1
                                )
                                .foregroundStyle(point.tsb >= 0 ? .green : .orange)
                            }
                            .frame(height: 190)
                            .padding(.top, 6)
                        } else {
                            Chart {
                                if let first = freshnessSeries.first?.date, let last = freshnessSeries.last?.date {
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
                                }

                                RuleMark(y: .value("Baseline", 0))
                                    .foregroundStyle(.secondary.opacity(0.45))
                                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                                ForEach(freshnessSeries) { point in
                                    switch chartDisplayMode {
                                    case .line:
                                        LineMark(
                                            x: .value("Date", point.date, unit: .day),
                                            y: .value("TSB", point.tsb)
                                        )
                                        .foregroundStyle(.orange)
                                        .interpolationMethod(.stepCenter)
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
                            .frame(height: 190)
                            .chartYScale(domain: freshnessYDomain)
                            .chartYAxis {
                                AxisMarks(position: .trailing)
                            }
                            .cartesianHoverTip(
                                xTitle: L10n.choose(simplifiedChinese: "日期", english: "Date"),
                                yTitle: "TSB"
                            )
                            .padding(.top, 6)
                        }

                        HStack(spacing: 10) {
                            Text(L10n.choose(simplifiedChinese: "高风险", english: "High Risk"))
                                .foregroundStyle(.red)
                            Text(L10n.choose(simplifiedChinese: "过渡", english: "Transition"))
                                .foregroundStyle(.orange)
                            Text(L10n.choose(simplifiedChinese: "最优", english: "Optimal"))
                                .foregroundStyle(.green)
                            Text(L10n.choose(simplifiedChinese: "精力充沛", english: "Very Fresh"))
                                .foregroundStyle(.cyan)
                        }
                        .font(.caption2)
                    }
                }

                GroupBox(L10n.choose(simplifiedChinese: "30天运动负荷分布（按 TSS）", english: "30-Day Sport Mix by TSS")) {
                    if sportMix.isEmpty {
                        Text(L10n.choose(simplifiedChinese: "数据不足。", english: "Not enough data."))
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(sportMix) { point in
                            switch chartDisplayMode {
                            case .line:
                                LineMark(
                                    x: .value("Sport", point.sport.label),
                                    y: .value("TSS", point.totalTSS)
                                )
                                .foregroundStyle(by: .value("Sport", point.sport.label))
                            case .bar:
                                BarMark(
                                    x: .value("Sport", point.sport.label),
                                    y: .value("TSS", point.totalTSS)
                                )
                                .foregroundStyle(by: .value("Sport", point.sport.label))
                            case .pie:
                                SectorMark(
                                    angle: .value("TSS", point.totalTSS),
                                    innerRadius: .ratio(0.55),
                                    angularInset: 2
                                )
                                .foregroundStyle(by: .value("Sport", point.sport.label))
                            case .flame:
                                BarMark(
                                    x: .value("Sport", point.sport.label),
                                    y: .value("TSS", point.totalTSS)
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
                        .chartLegend(position: .trailing, alignment: .center)
                        .frame(height: 240)
                    }
                }

                GroupBox(L10n.choose(simplifiedChinese: "计划负荷（未来21天）", english: "Planned Load (Next 21d)")) {
                    Chart(plannedLoad) { point in
                        switch chartDisplayMode {
                        case .line:
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Minutes", point.minutes)
                            )
                            .foregroundStyle(.blue)
                        case .bar:
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Minutes", point.minutes)
                            )
                            .foregroundStyle(.blue.gradient)
                            .opacity(point.minutes > 0 ? 1.0 : 0.2)
                        case .pie:
                            SectorMark(
                                angle: .value("Minutes", max(0, point.minutes)),
                                innerRadius: .ratio(0.55),
                                angularInset: 1
                            )
                            .foregroundStyle(.blue.opacity(point.minutes > 0 ? 0.85 : 0.22))
                        case .flame:
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Minutes", max(0, point.minutes))
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange, .red],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .opacity(point.minutes > 0 ? 1.0 : 0.2)
                        }
                    }
                    .frame(height: 220)
                    .cartesianHoverTip(
                        xTitle: L10n.choose(simplifiedChinese: "日期", english: "Date"),
                        yTitle: L10n.choose(simplifiedChinese: "分钟", english: "Minutes")
                    )
                }
            }
            .padding(24)
        }
        .task {
            await store.ensureAICoachReady()
        }
    }

    private func readinessAdvice(tsb: Double) -> String {
        if tsb < -20 {
            return L10n.choose(
                simplifiedChinese: "疲劳较高：优先恢复并降低强度。",
                english: "High fatigue: prioritize recovery and reduce intensity."
            )
        }
        if tsb < -5 {
            return L10n.choose(
                simplifiedChinese: "处于有效负荷区：维持质量课，关注睡眠与 HRV。",
                english: "Productive load zone: maintain quality sessions, watch sleep and HRV."
            )
        }
        if tsb <= 15 {
            return L10n.choose(
                simplifiedChinese: "状态较新鲜：适合安排比赛配速或阈值训练。",
                english: "Fresh and trainable: good window for race-pace or threshold work."
            )
        }
        return L10n.choose(
            simplifiedChinese: "非常新鲜：可考虑高质量课或比赛模拟。",
            english: "Very fresh: consider a high-quality session or race simulation."
        )
    }

    private func runningHeadline(_ running: RunningPerformanceEstimate) -> String {
        guard let thresholdPace = running.estimatedThresholdPaceMinPerKm else {
            return L10n.choose(
                simplifiedChinese: "跑步样本不足，先积累 3 次以上有效跑步活动",
                english: "Insufficient running samples. Accumulate at least 3 valid runs first."
            )
        }

        var headline = L10n.choose(
            simplifiedChinese: "阈值配速估算: \(thresholdPace.mmssPerKm)",
            english: "Estimated threshold pace: \(thresholdPace.mmssPerKm)"
        )
        if let tenK = running.estimated10kTimeSec {
            headline += L10n.choose(
                simplifiedChinese: " · 10k 估算: \(tenK.hhmmss)",
                english: " · Estimated 10k: \(tenK.hhmmss)"
            )
        }
        return headline
    }

    private func wellnessChip(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SportMixPoint: Identifiable {
    var id: String { sport.rawValue }
    let sport: SportType
    let totalTSS: Int
}

private struct InsightStatCard: View {
    let item: InsightsView.InsightStatItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(item.tint.opacity(0.16))
                GeometryReader { proxy in
                    Capsule()
                        .fill(item.tint.gradient)
                        .frame(width: max(6, proxy.size.width * min(max(item.emphasis, 0), 1)))
                }
            }
            .frame(height: 6)

            Text(item.title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(item.value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(item.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(item.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct WellnessTrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let hrv: Double?
    let restingHR: Double?
    let sleepHours: Double?
    let sleepScore: Double?
}

private struct PlannedLoadPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let minutes: Int
}

private struct EventMixPoint: Identifiable {
    var id: String { category }
    let category: String
    let count: Int
}

private struct RecentActivityInsight: Identifiable {
    var id: UUID { activity.id }
    let activity: Activity
    let insight: ActivityMetricInsight
}

private struct PerformanceEstimateCard: View {
    let title: String
    let headline: String
    let subheadline: String
    let method: String
    let parameters: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(headline)
                .font(.subheadline.bold())
            Text(subheadline)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("方法: \(method)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(parameters, id: \.self) { parameter in
                Text("参数: \(parameter)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Double {
    var mmssPerKm: String {
        guard self.isFinite, self > 0 else { return "--/km" }
        let totalSec = Int((self * 60).rounded())
        let m = totalSec / 60
        let s = totalSec % 60
        return String(format: "%d:%02d /km", m, s)
    }
}

private extension Int {
    var hhmmss: String {
        guard self >= 0 else { return "--:--" }
        let h = self / 3600
        let m = (self % 3600) / 60
        let s = self % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
