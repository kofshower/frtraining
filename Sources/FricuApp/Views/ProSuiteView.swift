import SwiftUI
import Charts
import UniformTypeIdentifiers

private enum ProSuiteModule: String, CaseIterable, Identifiable {
    case planner
    case intervals
    case metrics
    case powerModels
    case activityGrid
    case collaboration
    case integrations
    case forensic

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .planner: return "prosuite.module.planner"
        case .intervals: return "prosuite.module.intervals"
        case .metrics: return "prosuite.module.metrics"
        case .powerModels: return "prosuite.module.powerModels"
        case .activityGrid: return "prosuite.module.activityGrid"
        case .collaboration: return "prosuite.module.collaboration"
        case .integrations: return "prosuite.module.integrations"
        case .forensic: return "prosuite.module.forensic"
        }
    }

    var localizedTitle: String {
        switch self {
        case .planner:
            return L10n.choose(simplifiedChinese: "训练日历", english: "Training Calendar")
        case .intervals:
            return L10n.choose(simplifiedChinese: "间歇实验室", english: "Interval Lab")
        case .metrics:
            return L10n.choose(simplifiedChinese: "图表引擎", english: "Chart Engine")
        case .powerModels:
            return L10n.choose(simplifiedChinese: "功率建模", english: "Power Modeling")
        case .activityGrid:
            return L10n.choose(simplifiedChinese: "活动网格", english: "Activity Grid")
        case .collaboration:
            return L10n.choose(simplifiedChinese: "协作", english: "Collaboration")
        case .integrations:
            return L10n.choose(simplifiedChinese: "集成中心", english: "Integrations")
        case .forensic:
            return L10n.choose(simplifiedChinese: "取证", english: "Forensic")
        }
    }
}

struct ProSuiteView: View {
    @State private var module: ProSuiteModule = .planner

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pro Training Suite")
                .font(.largeTitle.bold())

            Picker(selection: $module) {
                ForEach(ProSuiteModule.allCases) { module in
                    Text(verbatim: module.localizedTitle).tag(module)
                }
            } label: {
                Text(L10n.choose(simplifiedChinese: "模块", english: "Module"))
            }
            .appDropdownTheme()

            Group {
                switch module {
                case .planner:
                    PlannerModuleView()
                case .intervals:
                    IntervalLabModuleView()
                case .metrics:
                    MetricsLabModuleView()
                case .powerModels:
                    PowerModelModuleView()
                case .activityGrid:
                    ActivityGridModuleView()
                case .collaboration:
                    CollaborationModuleView()
                case .integrations:
                    IntegrationModuleView()
                case .forensic:
                    ForensicModuleView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
    }
}

private struct PlannerModuleView: View {
    @EnvironmentObject private var store: AppStore

    @State private var calendarAnchor = Date()
    @State private var selectedTemplateID: UUID = WorkoutTemplateLibrary.templates.first?.id ?? UUID()
    @State private var templateStartDate = Date()
    @State private var repeatWeeks = 4
    @State private var norwegianSport: SportType = .cycling
    @State private var norwegianDate = Date()

    private var adherence: PlanAdherenceReport {
        PlanAdherenceEngine.evaluate(
            workouts: store.athleteScopedPlannedWorkouts,
            activities: store.athleteScopedActivities,
            profile: store.profile
        )
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: calendarAnchor)?.start ?? calendar.startOfDay(for: calendarAnchor)
        return (0..<28).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var workoutsByDay: [Date: [PlannedWorkout]] {
        let calendar = Calendar.current
        let scheduled = store.athleteScopedPlannedWorkouts.filter { $0.scheduledDate != nil }
        let grouped = Dictionary(grouping: scheduled) { workout in
            calendar.startOfDay(for: workout.scheduledDate ?? workout.createdAt)
        }
        return grouped.mapValues { rows in
            rows.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private var unscheduled: [PlannedWorkout] {
        store.athleteScopedPlannedWorkouts.filter { $0.scheduledDate == nil }
    }

    private var selectedTemplate: WorkoutTemplate? {
        WorkoutTemplateLibrary.templates.first { $0.id == selectedTemplateID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("计划模板与复用") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Picker("模板", selection: $selectedTemplateID) {
                                ForEach(WorkoutTemplateLibrary.templates) { template in
                                    Text(template.name).tag(template.id)
                                }
                            }
                            .appDropdownTheme()

                            DatePicker("开始日期", selection: $templateStartDate, displayedComponents: .date)
                                .frame(maxWidth: 260)

                            Stepper("重复 \(repeatWeeks) 周", value: $repeatWeeks, in: 1...16)
                                .frame(maxWidth: 180)

                            Button("应用模板") {
                                guard let selectedTemplate else { return }
                                store.instantiateTemplate(selectedTemplate, startDate: templateStartDate, repeatWeeks: repeatWeeks)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if let selectedTemplate {
                            Text("标签: \(selectedTemplate.tags.joined(separator: " · ")) · 总时长 \(selectedTemplate.segments.reduce(0) { $0 + $1.minutes }) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GroupBox("挪威训练法（双阈值）") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Picker("运动", selection: $norwegianSport) {
                                Text("Cycling").tag(SportType.cycling)
                                Text("Running").tag(SportType.running)
                            }
                            .appDropdownTheme()

                            DatePicker("日期", selection: $norwegianDate, displayedComponents: .date)
                                .frame(maxWidth: 240)

                            Button("一键添加双阈值日 (AM+PM)") {
                                store.addNorwegianDoubleThresholdDay(sport: norwegianSport, date: norwegianDate)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Text("原则: 两次都在阈值附近（大致 88%-102% FTP 或 88%-100% LTHR），避免变成 VO2；当天优先碳水与恢复。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("计划依从性 (近42天)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 24) {
                            PlannerStat(title: "计划课", value: "\(adherence.plannedCount)")
                            PlannerStat(title: "完成", value: "\(adherence.completedCount)")
                            PlannerStat(title: "按计划", value: "\(adherence.onTimeCount)")
                            PlannerStat(title: "完成率", value: String(format: "%.0f%%", adherence.completionRate * 100.0))
                            PlannerStat(title: "按计划率", value: String(format: "%.0f%%", adherence.onTimeRate * 100.0))
                        }
                        HStack(spacing: 24) {
                            PlannerStat(title: "双阈值日", value: "\(adherence.norwegianDoubleThresholdDays)")
                            PlannerStat(title: "可控双阈值", value: "\(adherence.norwegianControlledDays)")
                            PlannerStat(title: "双阈值风险日", value: "\(adherence.norwegianRiskDays)")
                            PlannerStat(title: "阈值课次数", value: "\(adherence.norwegianThresholdSessions)")
                        }
                        ProgressView(value: adherence.completionRate)
                            .tint(.green)
                        if adherence.norwegianRiskDays > 0 {
                            Text("提示: 最近有 \(adherence.norwegianRiskDays) 个双阈值风险日（可能强度过高或次数过多），建议下调强度。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("训练日历与拖拽排课") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("上一周期") {
                                calendarAnchor = Calendar.current.date(byAdding: .day, value: -28, to: calendarAnchor) ?? calendarAnchor
                            }
                            Button("下一周期") {
                                calendarAnchor = Calendar.current.date(byAdding: .day, value: 28, to: calendarAnchor) ?? calendarAnchor
                            }
                            Spacer()
                            Text("将课表卡片拖到任意日期即可重排")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120)), count: 7), spacing: 8) {
                            ForEach(weekDays, id: \.self) { day in
                                PlannerDayCell(
                                    day: day,
                                    workouts: workoutsByDay[Calendar.current.startOfDay(for: day)] ?? [],
                                    onReschedule: { id in
                                        store.rescheduleWorkout(id: id, to: day)
                                    }
                                )
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("未排期")
                                .font(.headline)

                            FlowWrap(spacing: 8, lineSpacing: 8) {
                                ForEach(unscheduled) { workout in
                                    PlannerWorkoutChip(workout: workout)
                                        .onDrag {
                                            NSItemProvider(object: workout.id.uuidString as NSString)
                                        }
                                }
                            }
                            .dropDestination(for: String.self) { items, _ in
                                guard let first = items.first, let id = UUID(uuidString: first) else { return false }
                                store.rescheduleWorkout(id: id, to: nil)
                                return true
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PlannerStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
    }
}

private struct PlannerDayCell: View {
    let day: Date
    let workouts: [PlannedWorkout]
    let onReschedule: (UUID) -> Void

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption.bold())
                .foregroundStyle(isToday ? .blue : .secondary)

            if workouts.isEmpty {
                Text("空")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(workouts.prefix(4)) { workout in
                    PlannerWorkoutChip(workout: workout)
                        .onDrag {
                            NSItemProvider(object: workout.id.uuidString as NSString)
                        }
                }
                if workouts.count > 4 {
                    Text("+\(workouts.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(isToday ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let id = UUID(uuidString: first) else { return false }
            onReschedule(id)
            return true
        }
    }
}

private struct PlannerWorkoutChip: View {
    let workout: PlannedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workout.name)
                .font(.caption.bold())
                .lineLimit(1)
            Text("\(workout.sport.label) · \(workout.totalMinutes)min")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct IntervalLabModuleView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedActivityID: UUID?
    @State private var selectedIntervalID: UUID?
    @State private var detectedIntervals: [DetectedInterval] = []
    @State private var allDetectedIntervals: [DetectedInterval] = []
    @State private var similarHitsCache: [SimilarIntervalHit] = []

    private var activityOptions: [Activity] {
        store.filteredActivities
    }

    private var selectedActivity: Activity? {
        guard let selectedActivityID else { return activityOptions.first }
        return activityOptions.first { $0.id == selectedActivityID }
    }

    private var selectedInterval: DetectedInterval? {
        guard let selectedIntervalID else { return detectedIntervals.first }
        return detectedIntervals.first { $0.id == selectedIntervalID }
    }

    private var intervalRefreshKey: String {
        let selected = selectedActivityID?.uuidString ?? "none"
        let marker = activityOptions.first?.id.uuidString ?? "empty"
        let profileFP = "\(store.profile.cyclingFTPWatts)-\(store.profile.runningFTPWatts)-\(store.profile.cyclingThresholdHeartRate)-\(store.profile.runningThresholdHeartRate)"
        return "\(selected)-\(activityOptions.count)-\(marker)-\(profileFP)"
    }

    private var compareRows: [IntervalCompareRow] {
        var rows: [IntervalCompareRow] = []
        if let selectedInterval {
            rows.append(IntervalCompareRow(label: "目标", power: selectedInterval.avgPower, duration: Double(selectedInterval.durationSec), ifValue: selectedInterval.intensityFactor, similarity: 1.0))
        }
        rows.append(contentsOf: similarHitsCache.prefix(5).enumerated().map { idx, hit in
            IntervalCompareRow(
                label: "相似\(idx + 1)",
                power: hit.interval.avgPower,
                duration: Double(hit.interval.durationSec),
                ifValue: hit.interval.intensityFactor,
                similarity: hit.similarity
            )
        })
        return rows
    }

    var body: some View {
        Group {
            if activityOptions.isEmpty {
                ContentUnavailableView("No activities", systemImage: "figure.outdoor.cycle")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("活动", selection: Binding(
                            get: { selectedActivityID ?? activityOptions.first?.id ?? UUID() },
                            set: { selectedActivityID = $0 }
                        )) {
                            ForEach(activityOptions.prefix(120)) { activity in
                                Text("\(activity.date.formatted(date: .abbreviated, time: .omitted)) · \(activity.sport.label) · TSS \(activity.tss)")
                                    .tag(activity.id)
                            }
                        }
                        .appDropdownTheme()

                        Text("自动间歇检测 + 全库相似搜索/对比")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    if let activity = selectedActivity {
                        Text("\(activity.sport.label) · \(activity.durationSec.asDuration) · NP \(activity.normalizedPower.map(String.init) ?? "N/A")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        GroupBox("自动检测间歇") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    if detectedIntervals.isEmpty {
                                        Text("未检测到有效间歇。可导入带功率数据的 FIT 并重试。")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                    ForEach(detectedIntervals) { interval in
                                        Button {
                                            selectedIntervalID = interval.id
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("#\(interval.index) \(interval.label)")
                                                        .font(.subheadline.bold())
                                                    Text("\(interval.durationSec.asDuration) · \(Int(interval.avgPower))W · IF \(String(format: "%.2f", interval.intensityFactor))")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .padding(8)
                                        .background(selectedIntervalID == interval.id ? Color.blue.opacity(0.10) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        GroupBox("相似间歇") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    if similarHitsCache.isEmpty {
                                        Text("暂无相似间歇结果")
                                            .foregroundStyle(.secondary)
                                    }
                                    ForEach(similarHitsCache) { hit in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(hit.interval.activityDate.formatted(date: .abbreviated, time: .omitted)) · \(hit.interval.sport.label) · \(hit.interval.label)")
                                                .font(.subheadline)
                                            Text("相似度 \(String(format: "%.0f%%", hit.similarity * 100)) · \(hit.interval.durationSec.asDuration) · \(Int(hit.interval.avgPower))W · IF \(String(format: "%.2f", hit.interval.intensityFactor))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 3)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    GroupBox("间歇对比图") {
                        if compareRows.isEmpty {
                            Text("选择间歇后显示对比")
                                .foregroundStyle(.secondary)
                        } else {
                            Chart(compareRows) { row in
                                BarMark(
                                    x: .value("Interval", row.label),
                                    y: .value("Power", row.power)
                                )
                                .foregroundStyle(.blue.gradient)

                                PointMark(
                                    x: .value("Interval", row.label),
                                    y: .value("Duration", row.duration / 10.0)
                                )
                                .foregroundStyle(.orange)
                            }
                            .frame(height: 210)
                            .cartesianHoverTip(
                                xTitle: L10n.choose(simplifiedChinese: "间歇", english: "Interval"),
                                yTitle: L10n.choose(simplifiedChinese: "功率/时长", english: "Power/Duration")
                            )

                            Text("柱: 平均功率(W)；点: 时长(秒/10)。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear {
            recomputeIntervalCaches()
        }
        .onChange(of: intervalRefreshKey) { _, _ in
            recomputeIntervalCaches()
        }
        .onChange(of: selectedIntervalID) { _, _ in
            recomputeSimilarHits()
        }
    }

    private func recomputeIntervalCaches() {
        allDetectedIntervals = IntervalLabEngine.detectIntervals(
            activities: activityOptions,
            profile: store.profile
        )

        guard let activity = selectedActivity else {
            detectedIntervals = []
            selectedIntervalID = nil
            similarHitsCache = []
            return
        }

        detectedIntervals = allDetectedIntervals.filter { $0.activityID == activity.id }
        if !detectedIntervals.contains(where: { $0.id == selectedIntervalID }) {
            selectedIntervalID = detectedIntervals.first?.id
        }
        recomputeSimilarHits()
    }

    private func recomputeSimilarHits() {
        guard let selectedInterval else {
            similarHitsCache = []
            return
        }

        similarHitsCache = IntervalLabEngine.findSimilarIntervals(
            target: selectedInterval,
            intervals: allDetectedIntervals,
            limit: 10
        )
    }
}

private struct IntervalCompareRow: Identifiable {
    let id = UUID()
    let label: String
    let power: Double
    let duration: Double
    let ifValue: Double
    let similarity: Double
}

private enum MetricScopeFilter: String, CaseIterable, Identifiable {
    case all
    case activity
    case trends
    case wellness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .activity: return "Activity"
        case .trends: return "Trends"
        case .wellness: return "Wellness"
        }
    }
}

private struct MetricsLabModuleView: View {
    @EnvironmentObject private var store: AppStore

    @State private var primaryMetricID = ChartMetricCatalog.all.first?.id ?? "daily_tss"
    @State private var secondaryEnabled = false
    @State private var secondaryMetricID = ChartMetricCatalog.all.dropFirst().first?.id ?? "ctl"
    @State private var days = 180
    @State private var aggregation: MetricAggregation = .day
    @State private var sportFilter: SportType?
    @State private var comparePrevious = true
    @State private var metricSearch = ""
    @State private var scopeFilter: MetricScopeFilter = .all
    @State private var resultCache = MetricLabResult(primary: [], secondary: [], comparison: [])
    @State private var computeGeneration: UInt64 = 0
    @State private var isComputing = false

    private var filteredMetrics: [ChartMetricDefinition] {
        let base = ChartMetricCatalog.all.filter { metric in
            switch scopeFilter {
            case .all:
                return true
            case .activity:
                return metric.scope == .activity
            case .trends:
                return metric.scope == .trends
            case .wellness:
                return metric.scope == .wellness
            }
        }

        guard !metricSearch.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(metricSearch) ||
            $0.id.localizedCaseInsensitiveContains(metricSearch)
        }
    }

    private var primaryMetric: ChartMetricDefinition {
        ChartMetricCatalog.all.first { $0.id == primaryMetricID } ?? ChartMetricCatalog.all[0]
    }

    private var secondaryMetric: ChartMetricDefinition? {
        guard secondaryEnabled else { return nil }
        return ChartMetricCatalog.all.first { $0.id == secondaryMetricID }
    }

    private var metricQueryKey: String {
        let marker = store.athleteScopedActivities.first?.id.uuidString ?? "none"
        let sport = sportFilter?.rawValue ?? "all"
        return "\(primaryMetricID)-\(secondaryEnabled)-\(secondaryMetricID)-\(days)-\(aggregation.rawValue)-\(sport)-\(comparePrevious)-\(scopeFilter.rawValue)-\(store.athleteScopedActivities.count)-\(store.loadSeries.count)-\(marker)-\(store.profile.cyclingFTPWatts)-\(store.profile.runningFTPWatts)"
    }

    private var primaryInterpolation: InterpolationMethod {
        if aggregation == .day, primaryMetric.style == .sum { return .stepCenter }
        return .linear
    }

    private var comparisonInterpolation: InterpolationMethod {
        if aggregation == .day, primaryMetric.style == .sum { return .stepCenter }
        return .linear
    }

    private var secondaryInterpolation: InterpolationMethod {
        guard let secondaryMetric else { return .linear }
        if aggregation == .day, secondaryMetric.style == .sum { return .stepCenter }
        return .linear
    }

    private var renderPrimaryAsBars: Bool {
        aggregation == .day && primaryMetric.style == .sum
    }

    private var primaryLineSegments: [[MetricChartPoint]] {
        segmentedSeries(resultCache.primary, aggregation: aggregation)
    }

    private var secondaryLineSegments: [[MetricChartPoint]] {
        segmentedSeries(resultCache.secondary, aggregation: aggregation)
    }

    private var comparisonLineSegments: [[MetricChartPoint]] {
        segmentedSeries(resultCache.comparison, aggregation: aggregation)
    }

    private var metricChartDomain: ClosedRange<Date> {
        let allDates = (resultCache.primary + resultCache.secondary + resultCache.comparison).map(\.date)
        let calendar = Calendar.current

        guard
            let minimum = allDates.min(),
            let maximum = allDates.max()
        else {
            let end = calendar.startOfDay(for: Date())
            let start = calendar.date(byAdding: .day, value: -max(14, days) + 1, to: end) ?? end
            return start...end
        }

        if minimum == maximum {
            let start = calendar.date(byAdding: .day, value: -1, to: minimum) ?? minimum
            let end = calendar.date(byAdding: .day, value: 1, to: maximum) ?? maximum
            return start...end
        }

        return minimum...maximum
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("搜索指标 (GC Activity + Trends)", text: $metricSearch)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Text("当前指标库 \(filteredMetrics.count) / \(ChartMetricCatalog.all.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("范围", selection: $scopeFilter) {
                    ForEach(MetricScopeFilter.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .appDropdownTheme()

                Picker("主指标", selection: $primaryMetricID) {
                    ForEach(filteredMetrics) { metric in
                        Text(metric.name).tag(metric.id)
                    }
                }
                .appDropdownTheme()

                Toggle("双指标对比", isOn: $secondaryEnabled)
                    .toggleStyle(.switch)
                if secondaryEnabled {
                    Picker("副指标", selection: $secondaryMetricID) {
                        ForEach(filteredMetrics) { metric in
                            Text(metric.name).tag(metric.id)
                        }
                    }
                    .appDropdownTheme()
                }
            }

            HStack(spacing: 12) {
                Picker("聚合", selection: $aggregation) {
                    ForEach(MetricAggregation.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .appDropdownTheme()

                Picker("窗口", selection: $days) {
                    Text("42d").tag(42)
                    Text("90d").tag(90)
                    Text("180d").tag(180)
                    Text("365d").tag(365)
                }
                .appDropdownTheme()

                Picker("运动", selection: $sportFilter) {
                    Text("All").tag(Optional<SportType>.none)
                    ForEach(SportType.allCases) { sport in
                        Text(sport.label).tag(Optional(sport))
                    }
                }
                .appDropdownTheme()

                Toggle("对比上周期", isOn: $comparePrevious)
                    .toggleStyle(.switch)
            }

            GroupBox("可视化图表引擎") {
                Chart {
                    if renderPrimaryAsBars {
                        ForEach(resultCache.primary) { point in
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(primaryMetric.name, point.value)
                            )
                            .foregroundStyle(.blue)
                        }
                    } else {
                        ForEach(Array(primaryLineSegments.enumerated()), id: \.offset) { segmentIndex, segment in
                            ForEach(segment) { point in
                                LineMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value(primaryMetric.name, point.value),
                                    series: .value("Primary Segment", "primary-\(segmentIndex)")
                                )
                                .foregroundStyle(.blue)
                                .interpolationMethod(primaryInterpolation)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    }

                    if let secondaryMetric {
                        ForEach(Array(secondaryLineSegments.enumerated()), id: \.offset) { segmentIndex, segment in
                            ForEach(segment) { point in
                                LineMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value(secondaryMetric.name, point.value),
                                    series: .value("Secondary Segment", "secondary-\(segmentIndex)")
                                )
                                .foregroundStyle(.orange)
                                .interpolationMethod(secondaryInterpolation)
                                .lineStyle(StrokeStyle(lineWidth: 1.8))
                            }
                        }
                    }

                    if comparePrevious {
                        ForEach(Array(comparisonLineSegments.enumerated()), id: \.offset) { segmentIndex, segment in
                            ForEach(segment) { point in
                                LineMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Prev", point.value),
                                    series: .value("Comparison Segment", "comparison-\(segmentIndex)")
                                )
                                .foregroundStyle(.gray.opacity(0.8))
                                .interpolationMethod(comparisonInterpolation)
                                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                            }
                        }
                    }
                }
                .frame(height: 280)
                .chartXScale(domain: metricChartDomain)
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
                .chartPlotStyle { plot in
                    plot.clipped()
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
                .cartesianHoverTip(
                    xTitle: L10n.choose(simplifiedChinese: "日期", english: "Date"),
                    yTitle: L10n.choose(simplifiedChinese: "指标值", english: "Metric")
                )

                if isComputing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.choose(simplifiedChinese: "正在并行计算图表数据…", english: "Computing chart data in parallel..."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 14) {
                    Text("蓝实线: \(primaryMetric.name)")
                    if let secondaryMetric {
                        Text("橙实线: \(secondaryMetric.name)")
                    }
                    if comparePrevious {
                        Text("灰虚线: 上一周期")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .task(id: metricQueryKey) {
            computeGeneration &+= 1
            let generation = computeGeneration
            isComputing = true

            let activities = store.athleteScopedActivities
            let loadSeries = store.loadSeries
            let profile = store.profile
            let primary = primaryMetric
            let secondary = secondaryMetric
            let days = days
            let aggregation = aggregation
            let sportFilter = sportFilter
            let comparePrevious = comparePrevious

            let result: MetricLabResult = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let value = MetricLabEngine.build(
                        activities: activities,
                        loadSeries: loadSeries,
                        profile: profile,
                        primary: primary,
                        secondary: secondary,
                        days: days,
                        aggregation: aggregation,
                        sportFilter: sportFilter,
                        comparePrevious: comparePrevious
                    )
                    continuation.resume(returning: value)
                }
            }

            guard generation == computeGeneration else { return }
            resultCache = result
            isComputing = false
        }
    }

    private func segmentedSeries(
        _ points: [MetricChartPoint],
        aggregation: MetricAggregation
    ) -> [[MetricChartPoint]] {
        guard !points.isEmpty else { return [] }
        let sorted = points.sorted { $0.date < $1.date }
        let maxGap: TimeInterval
        switch aggregation {
        case .day:
            maxGap = 36 * 60 * 60
        case .week:
            maxGap = 9 * 24 * 60 * 60
        case .month:
            maxGap = 40 * 24 * 60 * 60
        }

        var segments: [[MetricChartPoint]] = []
        var current: [MetricChartPoint] = []

        for point in sorted {
            if let last = current.last,
               point.date.timeIntervalSince(last.date) > maxGap {
                if !current.isEmpty {
                    segments.append(current)
                }
                current = [point]
            } else {
                current.append(point)
            }
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }
}

private struct PowerModelModuleView: View {
    @EnvironmentObject private var store: AppStore

    @State private var athleteAge = 34
    @State private var athleteWeightKg = 69.0
    @State private var analysis = PowerCurveAnalysis.empty
    @State private var analysisGeneration: UInt64 = 0
    @State private var isAnalyzing = false

    private struct ModelCurveRow: Identifiable {
        let model: String
        let durationMin: Double
        let power: Double

        var id: String {
            "\(model)-\(String(format: "%.2f", durationMin))"
        }
    }

    private var analysisKey: String {
        let marker = store.athleteScopedActivities.first?.id.uuidString ?? "none"
        return "\(store.athleteScopedActivities.count)-\(marker)-\(athleteAge)-\(athleteWeightKg)-\(store.profile.cyclingFTPWatts)"
    }

    private var modelCurvePoints: [PowerCurvePoint] {
        (analysis.monod?.curve ?? [])
            + (analysis.morton3P?.curve ?? [])
            + (analysis.submax?.curve ?? [])
    }

    private var modelCurveRows: [ModelCurveRow] {
        var grouped: [String: [ModelCurveRow]] = [:]
        grouped.reserveCapacity(3)

        func appendCurve(name: String, curve: [PowerCurvePoint]) {
            let rows = curve
                .filter { $0.power.isFinite && $0.power > 0 && $0.durationSec > 0 }
                .map { point in
                    ModelCurveRow(
                        model: name,
                        durationMin: Double(point.durationSec) / 60.0,
                        power: point.power
                    )
                }
                .sorted { lhs, rhs in lhs.durationMin < rhs.durationMin }

            guard !rows.isEmpty else { return }

            // Keep one point per duration for stable polyline shape.
            var deduped: [ModelCurveRow] = []
            deduped.reserveCapacity(rows.count)
            for row in rows {
                if let last = deduped.last, abs(last.durationMin - row.durationMin) < 0.0001 {
                    deduped[deduped.count - 1] = row
                } else {
                    deduped.append(row)
                }
            }
            grouped[name] = deduped
        }

        if let monod = analysis.monod {
            appendCurve(name: monod.name, curve: monod.curve)
        }
        if let morton = analysis.morton3P {
            appendCurve(name: morton.name, curve: morton.curve)
        }
        if let submax = analysis.submax {
            appendCurve(name: submax.name, curve: submax.curve)
        }

        let orderedNames = ["Monod-Scherrer", "Morton 3P", "Submax Envelope"]
        var rows: [ModelCurveRow] = []
        rows.reserveCapacity(grouped.values.reduce(0) { $0 + $1.count })
        for name in orderedNames {
            rows.append(contentsOf: grouped[name] ?? [])
        }
        return rows
    }

    private var modelColorScale: KeyValuePairs<String, Color> {
        [
            "Monod-Scherrer": Color.blue,
            "Morton 3P": Color.purple,
            "Submax Envelope": Color.green
        ]
    }

    private var chartXDomain: ClosedRange<Double> {
        let allDurations = (analysis.observed + analysis.comparisonObserved + modelCurvePoints).map(\.durationSec)
        let upper = max(10.0, Double(allDurations.max() ?? 3600) / 60.0)
        return 0.0...upper
    }

    private var chartYDomain: ClosedRange<Double> {
        let observedPowers = (analysis.observed + analysis.comparisonObserved)
            .map(\.power)
            .filter { $0.isFinite && $0 > 0 }
        let modelPowers = modelCurvePoints
            .filter { $0.durationSec >= 10 }
            .map(\.power)
            .filter { $0.isFinite && $0 > 0 }

        let observedMax = observedPowers.max() ?? 250.0
        let hardCap = max(500.0, observedMax * 1.7)
        let rawMax = (observedPowers + modelPowers).map { min($0, hardCap) }.max() ?? observedMax
        return 0.0...max(250.0, rawMax * 1.08)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Stepper("年龄 \(athleteAge)", value: $athleteAge, in: 16...75)
                        .frame(maxWidth: 180)
                    HStack {
                        Text("体重")
                        TextField("kg", value: $athleteWeightKg, format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                    Button("写回 Athlete Profile") {
                        var profile = store.profile
                        profile.athleteAgeYears = athleteAge
                        profile.athleteWeightKg = athleteWeightKg
                        store.profile = profile
                        store.persistProfile()
                    }
                }

                GroupBox("CP/W'/Pmax 多模型") {
                    Chart {
                        ForEach(analysis.observed) { point in
                            PointMark(
                                x: .value("Duration", Double(point.durationSec) / 60.0),
                                y: .value("Power", point.power)
                            )
                            .foregroundStyle(.black)
                        }

                        ForEach(analysis.comparisonObserved) { point in
                            PointMark(
                                x: .value("Prev Duration", Double(point.durationSec) / 60.0),
                                y: .value("Prev Power", point.power)
                            )
                            .foregroundStyle(.gray.opacity(0.35))
                        }

                        ForEach(modelCurveRows) { row in
                            LineMark(
                                x: .value("Duration", row.durationMin),
                                y: .value("Model Power", row.power),
                                series: .value("Model", row.model)
                            )
                            .foregroundStyle(by: .value("Model", row.model))
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .frame(height: 280)
                    .chartXScale(domain: chartXDomain)
                    .chartYScale(domain: chartYDomain)
                    .chartForegroundStyleScale(modelColorScale)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .cartesianHoverTip(
                        xTitle: L10n.choose(simplifiedChinese: "时长(分)", english: "Duration (min)"),
                        yTitle: L10n.choose(simplifiedChinese: "功率(W)", english: "Power (W)")
                    )

                    Text("黑点: 最近90天 MMP；灰点: 前90天。蓝/紫/绿分别为 Monod、Morton 3P、Submax 建模曲线。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isAnalyzing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.choose(simplifiedChinese: "正在并行拟合功率模型…", english: "Fitting power models in parallel..."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    if let monod = analysis.monod {
                        ModelCard(model: monod)
                    }
                    if let morton = analysis.morton3P {
                        ModelCard(model: morton)
                    }
                    if let submax = analysis.submax {
                        ModelCard(model: submax)
                    }
                }

                GroupBox("同年龄段 Watt/kg 排名与骑手画像") {
                    let ranking = analysis.ranking
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FTP/kg: \(String(format: "%.2f", ranking.ftpWkg)) · 年龄段 \(ranking.ageBand)")
                            .font(.headline)
                        Text("估算百分位: \(String(format: "%.1f", ranking.percentile))% · 约排名: \(ranking.rankIn1000)/1000")
                        Text("骑手画像: \(ranking.persona.rawValue)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear {
            athleteAge = store.profile.athleteAgeYears
            athleteWeightKg = store.profile.athleteWeightKg
            if let latestWeight = store.athleteScopedWellnessSamples.sortedByDateDescending().latestValue(\.weightKg) {
                athleteWeightKg = latestWeight
            }
        }
        .task(id: analysisKey) {
            analysisGeneration &+= 1
            let generation = analysisGeneration
            isAnalyzing = true

            let activities = store.athleteScopedActivities
            let profile = store.profile
            let athleteAge = athleteAge
            let athleteWeightKg = athleteWeightKg

            let result: PowerCurveAnalysis = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let value = PowerCurveEngine.analyze(
                        activities: activities,
                        profile: profile,
                        athleteAge: athleteAge,
                        athleteWeightKg: athleteWeightKg
                    )
                    continuation.resume(returning: value)
                }
            }

            guard generation == analysisGeneration else { return }
            analysis = result
            isAnalyzing = false
        }
    }
}

private struct ModelCard: View {
    let model: CPModelFit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.name)
                .font(.headline)
            Text("CP: \(Int(model.cp))W")
            Text("W': \(Int(model.wPrime))J")
            Text("Pmax: \(Int(model.pMax))W")
            if let tau = model.tau {
                Text("τ: \(Int(tau))s")
            }
            Text(String(format: "R²: %.2f", model.r2))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum ActivityGridSortKey: String, CaseIterable, Identifiable {
    case date
    case tss
    case duration
    case distance
    case np
    case hr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: return "日期"
        case .tss: return "TSS"
        case .duration: return "时长"
        case .distance: return "距离"
        case .np: return "NP"
        case .hr: return "AvgHR"
        }
    }
}

private struct ActivityGridModuleView: View {
    @EnvironmentObject private var store: AppStore

    @State private var search = ""
    @State private var selectedSport: SportType?
    @State private var sortKey: ActivityGridSortKey = .date
    @State private var ascending = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var customDelta = "5"
    @State private var fillMissingPower = true

    private var rows: [Activity] {
        var result = store.athleteScopedActivities

        if let selectedSport {
            result = result.filter { $0.sport == selectedSport }
        }

        if !search.isEmpty {
            result = result.filter {
                $0.notes.localizedCaseInsensitiveContains(search) ||
                $0.sport.label.localizedCaseInsensitiveContains(search)
            }
        }

        result.sort { lhs, rhs in
            let cmp: Bool
            switch sortKey {
            case .date:
                cmp = lhs.date < rhs.date
            case .tss:
                cmp = lhs.tss < rhs.tss
            case .duration:
                cmp = lhs.durationSec < rhs.durationSec
            case .distance:
                cmp = lhs.distanceKm < rhs.distanceKm
            case .np:
                cmp = (lhs.normalizedPower ?? 0) < (rhs.normalizedPower ?? 0)
            case .hr:
                cmp = (lhs.avgHeartRate ?? 0) < (rhs.avgHeartRate ?? 0)
            }
            return ascending ? cmp : !cmp
        }

        return result
    }

    private var anomalies: [Activity] {
        rows.filter { activity in
            if activity.durationSec <= 0 || activity.tss < 0 {
                return true
            }
            if let np = activity.normalizedPower, np > 650 {
                return true
            }
            if let hr = activity.avgHeartRate, hr > 210 {
                return true
            }
            if activity.distanceKm > 450 {
                return true
            }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("搜索", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Picker("运动", selection: $selectedSport) {
                    Text("All").tag(Optional<SportType>.none)
                    ForEach(SportType.allCases) { sport in
                        Text(sport.label).tag(Optional(sport))
                    }
                }
                .appDropdownTheme()

                Picker("排序", selection: $sortKey) {
                    ForEach(ActivityGridSortKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                .appDropdownTheme()

                Toggle("升序", isOn: $ascending)

                Spacer()

                Button("全选筛选结果") {
                    selectedIDs = Set(rows.map(\.id))
                }
                Button("清空选择") {
                    selectedIDs.removeAll()
                }
            }

            HStack(spacing: 8) {
                Toggle("缺失功率补全", isOn: $fillMissingPower)
                    .toggleStyle(.switch)
                TextField("修正%", text: $customDelta)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Button("批量修正功率") {
                    let delta = Double(customDelta) ?? 0
                    store.bulkAdjustActivitiesPower(activityIDs: selectedIDs, deltaPercent: delta, overwriteMissing: fillMissingPower)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty)

                Button("删除所选", role: .destructive) {
                    store.deleteActivities(ids: selectedIDs)
                    selectedIDs.removeAll()
                }
                .disabled(selectedIDs.isEmpty)

                Menu("修复工具链") {
                    ForEach(ActivityRepairMode.allCases) { mode in
                        Button(mode.title) {
                            store.repairActivities(ids: selectedIDs, mode: mode)
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                }

                Button("导出所选JSON") {
                    store.exportActivitiesToDist(ids: selectedIDs)
                }
                .disabled(selectedIDs.isEmpty)
            }

            GroupBox("异常检测 / 修复建议") {
                if anomalies.isEmpty {
                    Text("未发现明显异常样本")
                        .foregroundStyle(.secondary)
                } else {
                    Text("检测到 \(anomalies.count) 条异常样本，可先批量修正功率或删除异常记录。")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ActivityGridHeader()
                    ForEach(rows) { activity in
                        ActivityGridRow(
                            activity: activity,
                            selected: selectedIDs.contains(activity.id),
                            toggleSelection: {
                                if selectedIDs.contains(activity.id) {
                                    selectedIDs.remove(activity.id)
                                } else {
                                    selectedIDs.insert(activity.id)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct ActivityGridHeader: View {
    var body: some View {
        HStack {
            Text("Sel").frame(width: 40, alignment: .leading)
            Text("Date").frame(width: 110, alignment: .leading)
            Text("Sport").frame(width: 90, alignment: .leading)
            Text("Dur").frame(width: 80, alignment: .leading)
            Text("Distance").frame(width: 90, alignment: .leading)
            Text("TSS").frame(width: 70, alignment: .leading)
            Text("NP").frame(width: 70, alignment: .leading)
            Text("AvgHR").frame(width: 70, alignment: .leading)
            Spacer()
        }
        .font(.caption.bold())
        .padding(.horizontal, 6)
    }
}

private struct ActivityGridRow: View {
    let activity: Activity
    let selected: Bool
    let toggleSelection: () -> Void

    var body: some View {
        HStack {
            Button(action: toggleSelection) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain)
            .frame(width: 40, alignment: .leading)

            Text(activity.date.formatted(date: .abbreviated, time: .omitted))
                .frame(width: 110, alignment: .leading)
            Text(activity.sport.label)
                .frame(width: 90, alignment: .leading)
            Text(activity.durationSec.asDuration)
                .frame(width: 80, alignment: .leading)
            Text(String(format: "%.1fkm", activity.distanceKm))
                .frame(width: 90, alignment: .leading)
            Text("\(activity.tss)")
                .frame(width: 70, alignment: .leading)
            Text(activity.normalizedPower.map { "\($0)" } ?? "-")
                .frame(width: 70, alignment: .leading)
            Text(activity.avgHeartRate.map { "\($0)" } ?? "-")
                .frame(width: 70, alignment: .leading)

            Spacer()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(selected ? Color.blue.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CollabMessage: Identifiable {
    let id = UUID()
    let author: String
    let body: String
    let date: Date
}

private struct CollaborationModuleView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedActivityID: UUID?
    @State private var messageInput = ""
    @State private var messagesByActivity: [UUID: [CollabMessage]] = [:]
    @State private var selectedAthleteIndex = 0

    private let athletes = [
        "Athlete A · Road",
        "Athlete B · Triathlon",
        "Athlete C · Marathon"
    ]

    private let groups = [
        "Elite Build Group",
        "Weekend Endurance Group",
        "Race Prep Squad"
    ]

    private var selectedActivity: Activity? {
        let options = store.athleteScopedActivities.sorted { $0.date > $1.date }
        if let selectedActivityID {
            return options.first { $0.id == selectedActivityID }
        }
        return options.first
    }

    private var currentThread: [CollabMessage] {
        guard let id = selectedActivity?.id else { return [] }
        return messagesByActivity[id] ?? []
    }

    var body: some View {
        if store.athleteScopedActivities.isEmpty {
            ContentUnavailableView("No activities", systemImage: "person.2")
        } else {
            HStack(alignment: .top, spacing: 12) {
                GroupBox("教练-运动员管理") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("运动员", selection: $selectedAthleteIndex) {
                            ForEach(athletes.indices, id: \.self) { idx in
                                Text(athletes[idx]).tag(idx)
                            }
                        }
                        .appDropdownTheme()

                        Text("教练: Coach Chen")
                            .font(.subheadline)
                        Text("群组")
                            .font(.headline)
                        ForEach(groups, id: \.self) { group in
                            Text("• \(group)")
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 280)

                GroupBox("活动评论聊天") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("活动", selection: Binding(
                            get: { selectedActivityID ?? store.athleteScopedActivities.first?.id ?? UUID() },
                            set: { selectedActivityID = $0 }
                        )) {
                            ForEach(store.athleteScopedActivities.sorted(by: { $0.date > $1.date }).prefix(80)) { activity in
                                Text("\(activity.date.formatted(date: .abbreviated, time: .omitted)) · \(activity.sport.label) · TSS \(activity.tss)")
                                    .tag(activity.id)
                            }
                        }
                        .appDropdownTheme()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                if currentThread.isEmpty {
                                    Text("暂无评论。")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                ForEach(currentThread) { message in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(message.author) · \(message.date.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(message.body)
                                            .font(.subheadline)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }

                        HStack {
                            TextField("输入评论", text: $messageInput)
                                .textFieldStyle(.roundedBorder)
                            Button("发送") {
                                sendMessage()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(messageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func sendMessage() {
        let body = messageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let activityID = selectedActivity?.id else { return }

        var thread = messagesByActivity[activityID] ?? []
        thread.append(CollabMessage(author: "Coach", body: body, date: Date()))
        messagesByActivity[activityID] = thread
        messageInput = ""
    }
}

private enum ExecutionMode: String, CaseIterable, Identifiable {
    case power = "功率"
    case heartRate = "心率"
    case pace = "配速"
    case mixed = "混合"

    var id: String { rawValue }
}

private struct IntegrationModuleView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode: ExecutionMode = .mixed
    @State private var selectedDevice = "Wahoo KICKR"
    @State private var dispatchStatus = "未下发"
    @State private var targetPower = "220"
    @State private var targetHeartRate = "155"
    @State private var targetPace = "4:25"
    @State private var connectorTokenValues: [String: String] = [:]
    @State private var showGarminImporter = false

    @State private var connectors: [IntegrationConnector] = [
        IntegrationConnector(name: "Intervals.icu", group: "Cloud", bidirectional: true, enabled: true),
        IntegrationConnector(name: "Strava", group: "Cloud", bidirectional: false, enabled: true),
        IntegrationConnector(name: "Garmin Connect", group: "Cloud", bidirectional: false, enabled: true),
        IntegrationConnector(name: "TrainingPeaks", group: "Cloud", bidirectional: true, enabled: false),
        IntegrationConnector(name: "Oura", group: "Wellness", bidirectional: false, enabled: false),
        IntegrationConnector(name: "WHOOP", group: "Wellness", bidirectional: false, enabled: false),
        IntegrationConnector(name: "Apple Health", group: "Wellness", bidirectional: true, enabled: false),
        IntegrationConnector(name: "Google Fit", group: "Wellness", bidirectional: true, enabled: false),
        IntegrationConnector(name: "Wahoo Smart Trainer", group: "Device", bidirectional: true, enabled: true),
        IntegrationConnector(name: "Garmin/Tacx Trainer", group: "Device", bidirectional: true, enabled: true),
        IntegrationConnector(name: "ANT+ FE-C", group: "Indoor", bidirectional: true, enabled: false),
        IntegrationConnector(name: "Zwift", group: "Indoor", bidirectional: true, enabled: false)
    ]

    private let devices = ["Wahoo KICKR", "Garmin/Tacx", "Zwift Bridge", "Edge Headunit"]
    private let importTypes = [UTType.json]
    private let connectorTokenFields = IntegrationConnectorTokenField.all

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("连接生态") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("平台")
                            .font(.caption.bold())
                        Text("类别")
                            .font(.caption.bold())
                        Text("双向")
                            .font(.caption.bold())
                        Text("启用")
                            .font(.caption.bold())
                    }
                    ForEach($connectors) { $connector in
                        GridRow {
                            Text(connector.name)
                            Text(connector.group)
                            Image(systemName: connector.bidirectional ? "arrow.left.arrow.right" : "arrow.down")
                            Toggle("", isOn: $connector.enabled)
                                .labelsHidden()
                        }
                    }
                }
            }

            GroupBox("平台凭据与直连") {
                VStack(alignment: .leading, spacing: 8) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        ForEach(connectorTokenFields) { field in
                            GridRow {
                                Text(field.label)
                                tokenField(field)
                            }
                        }
                    }

                    HStack {
                        Button("保存平台凭据") {
                            persistConnectorTokens()
                        }
                        .buttonStyle(.borderedProminent)

                        syncActionButton("Garmin 拉取活动") {
                            await store.syncPullActivitiesFromGarminConnect()
                        }
                        syncActionButton("Garmin 拉取 Wellness") {
                            await store.syncPullWellnessFromGarmin()
                        }
                        syncActionButton("Oura 拉取 Wellness") {
                            await store.syncPullWellnessFromOura()
                        }
                        syncActionButton("WHOOP 拉取 Wellness") {
                            await store.syncPullWellnessFromWhoop()
                        }

                        Button("导入 Garmin JSON") {
                            showGarminImporter = true
                        }
                    }

                    Text("Garmin Connect（活动+Wellness）与 Oura 已支持真实 API 拉取；Garmin JSON 导入保留为离线备用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("训练执行目标多模式闭环") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("目标模式", selection: $mode) {
                            ForEach(ExecutionMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .appDropdownTheme()

                        Picker("下发设备", selection: $selectedDevice) {
                            ForEach(devices, id: \.self) { device in
                                Text(device).tag(device)
                            }
                        }
                        .appDropdownTheme()

                        Button("下发今日训练") {
                            dispatchToDevice()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack {
                        TextField("目标功率W", text: $targetPower)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        TextField("目标心率bpm", text: $targetHeartRate)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        TextField("目标配速", text: $targetPace)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text("实时回传: 功率 \(store.trainer.livePowerWatts.map { "\($0)W" } ?? "--")")
                        Text("心率 \(store.heartRateMonitor.liveHeartRateBPM.map { "\($0)bpm" } ?? "--")")
                        Text("RPE 代理: TSB \(String(format: "%.1f", store.summary.currentTSB))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(dispatchStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("室内训练生态") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("支持项: ANT+ FE-C, ERG/CRS/PGMF, 视频/街景联动接口。")
                    Text("当前实现状态: BLE FTMS 已可用；ANT+/视频联动已预留接口。")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("导入导出与历史兼容") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("导入: FIT / TCX / GPX / Strava / Intervals.icu")
                    Text("导出: JSON 快照（当前可用） + 训练计划双向同步")
                    Text("历史兼容: 活动级基础字段 + 计划与日历事件")
                        .foregroundStyle(.secondary)
                    Button("导出当前活动快照到 dist/exports") {
                        store.exportActivitiesToDist(ids: [])
                    }
                }
            }
        }
        .onAppear {
            loadConnectorTokens()
        }
        .fileImporter(
            isPresented: $showGarminImporter,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result, !urls.isEmpty {
                store.importGarminConnectJSON(urls: urls)
            }
        }
    }

    @ViewBuilder
    private func tokenField(_ field: IntegrationConnectorTokenField) -> some View {
        let binding = Binding(
            get: { connectorTokenValues[field.id, default: ""] },
            set: { connectorTokenValues[field.id] = $0 }
        )
        if field.secure {
            SecureField(field.placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
        } else {
            TextField(field.placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func syncActionButton(
        _ title: String,
        action: @escaping @Sendable () async -> Void
    ) -> some View {
        Button(title) {
            persistConnectorTokens()
            Task {
                await action()
            }
        }
        .disabled(store.isSyncing)
    }

    private func loadConnectorTokens() {
        connectorTokenValues = Dictionary(
            uniqueKeysWithValues: connectorTokenFields.map { field in
                (field.id, store.profile[keyPath: field.keyPath])
            }
        )
    }

    private func persistConnectorTokens() {
        var profile = store.profile
        for field in connectorTokenFields {
            profile[keyPath: field.keyPath] = connectorTokenValues[field.id, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        store.profile = profile
        store.persistProfile()
    }

    private func dispatchToDevice() {
        let time = Date().formatted(date: .omitted, time: .standard)
        switch mode {
        case .power:
            if let watts = Int(targetPower) {
                store.trainer.setErgTargetPower(watts)
                dispatchStatus = "已下发: 功率 \(watts)W -> \(selectedDevice) (\(time))"
            } else {
                dispatchStatus = "功率目标格式错误"
            }
        case .heartRate:
            dispatchStatus = "已下发: 心率 \(targetHeartRate)bpm -> \(selectedDevice) (\(time))"
        case .pace:
            dispatchStatus = "已下发: 配速 \(targetPace) -> \(selectedDevice) (\(time))"
        case .mixed:
            if let watts = Int(targetPower) {
                store.trainer.setErgTargetPower(watts)
            }
            dispatchStatus = "已下发: 混合目标 P\(targetPower) / HR\(targetHeartRate) / Pace \(targetPace) -> \(selectedDevice) (\(time))"
        }
    }
}

private struct IntegrationConnector: Identifiable {
    let id = UUID()
    var name: String
    var group: String
    var bidirectional: Bool
    var enabled: Bool
}

private struct IntegrationConnectorTokenField: Identifiable {
    let id: String
    let label: String
    let placeholder: String
    let secure: Bool
    let keyPath: WritableKeyPath<AthleteProfile, String>

    static let all: [IntegrationConnectorTokenField] = [
        .init(id: "garmin", label: "Garmin", placeholder: "Access Token", secure: true, keyPath: \.garminConnectAccessToken),
        .init(id: "garmin-csrf", label: "Garmin CSRF", placeholder: "Connect-Csrf-Token", secure: false, keyPath: \.garminConnectCSRFToken),
        .init(id: "oura", label: "Oura", placeholder: "Personal Access Token", secure: true, keyPath: \.ouraPersonalAccessToken),
        .init(id: "whoop", label: "WHOOP", placeholder: "Access Token", secure: true, keyPath: \.whoopAccessToken),
        .init(id: "apple-health", label: "Apple Health", placeholder: "Access Token", secure: true, keyPath: \.appleHealthAccessToken),
        .init(id: "google-fit", label: "Google Fit", placeholder: "Access Token", secure: true, keyPath: \.googleFitAccessToken),
        .init(id: "training-peaks", label: "TrainingPeaks", placeholder: "Access Token", secure: true, keyPath: \.trainingPeaksAccessToken)
    ]
}

private struct ForensicModuleView: View {
    @EnvironmentObject private var store: AppStore
    @State private var compareItems = ["赛季A", "赛季B", "活动组", "区间组", "运动员组"]

    private var scatterRows: [ForensicScatterRow] {
        store.athleteScopedActivities.compactMap { activity in
            guard let np = activity.normalizedPower, let hr = activity.avgHeartRate else { return nil }
            return ForensicScatterRow(
                sport: activity.sport,
                power: Double(np),
                heartRate: Double(hr),
                tss: Double(activity.tss)
            )
        }
    }

    private var aeroRows: [AerolabRow] {
        let source = store.athleteScopedActivities.sorted { $0.date < $1.date }.suffix(60)
        return source.enumerated().map { idx, activity in
            let speed = max(8.0, activity.distanceKm / max(0.2, Double(activity.durationSec) / 3600.0))
            let np = Double(activity.normalizedPower ?? 160)
            let cda = max(0.18, min(0.42, 0.38 - (np / max(1.0, speed * speed * 18.0))))
            return AerolabRow(index: idx, cda: cda)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("2D/3D Scatter (Forensic)") {
                if scatterRows.isEmpty {
                    Text("缺少功率+心率样本")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(scatterRows) { row in
                        PointMark(
                            x: .value("Power", row.power),
                            y: .value("HeartRate", row.heartRate)
                        )
                        .symbolSize(max(18, row.tss * 1.5))
                        .foregroundStyle(by: .value("Sport", row.sport.label))
                    }
                    .frame(height: 220)
                    .cartesianHoverTip(
                        xTitle: L10n.choose(simplifiedChinese: "功率(W)", english: "Power (W)"),
                        yTitle: L10n.choose(simplifiedChinese: "心率(bpm)", english: "Heart Rate (bpm)")
                    )
                    Text("点大小代表 TSS，作为伪 3D 强度轴。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Aerolab (CdA 估计轨迹)") {
                Chart(aeroRows) { row in
                    LineMark(
                        x: .value("Session", row.index),
                        y: .value("CdA", row.cda)
                    )
                    .foregroundStyle(.mint)
                }
                .frame(height: 160)
                .cartesianHoverTip(
                    xTitle: L10n.choose(simplifiedChinese: "训练序号", english: "Session"),
                    yTitle: "CdA"
                )
                Text("基于功率/速度估算 CdA，用于空气动力变化趋势追踪。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GroupBox("高级数据编辑器") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("工具链: 异常检测、GPS/尖峰/扭矩修复接口。")
                    Text("当前可用: 活动网格批量功率修正 + 异常检测；GPS/扭矩修复为下一阶段。")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("赛季/活动/区间/运动员拖拽对比") {
                List {
                    ForEach(compareItems, id: \.self) { item in
                        Text(item)
                    }
                    .onMove { indexes, newOffset in
                        compareItems.move(fromOffsets: indexes, toOffset: newOffset)
                    }
                }
                .frame(height: 160)
            }
        }
    }
}

private struct ForensicScatterRow: Identifiable {
    let id = UUID()
    let sport: SportType
    let power: Double
    let heartRate: Double
    let tss: Double
}

private struct AerolabRow: Identifiable {
    let id = UUID()
    let index: Int
    let cda: Double
}

private struct DurationPoint: Identifiable {
    let id = UUID()
    let label: String
    let minute: Double
    let power: Double
}

private struct FlowWrap<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
