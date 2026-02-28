import Foundation
import SwiftUI
import Charts
import UniformTypeIdentifiers

private enum ActivityCalendarScope: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week:
            return L10n.choose(simplifiedChinese: "周", english: "Week")
        case .month:
            return L10n.choose(simplifiedChinese: "月", english: "Month")
        case .year:
            return L10n.choose(simplifiedChinese: "年", english: "Year")
        }
    }
}

struct ActivityLibraryView: View {
    struct ActivitySummaryCardItem: Identifiable {
        let id: String
        let title: String
        let value: String
        let subtitle: String
        let tint: Color
        let emphasis: Double
    }

    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var showClearAllConfirm = false
    @State private var selectedActivity: Activity?
    @State private var calendarScope: ActivityCalendarScope = .month
    @State private var calendarAnchor = Date()
    @State private var selectedCalendarDay: Date?
    private let importTypes: [UTType] = [
        UTType(filenameExtension: "fit"),
        UTType(filenameExtension: "tcx"),
        UTType(filenameExtension: "gpx")
    ].compactMap { $0 }

    private var allActivitiesInCurrentSportScope: [Activity] {
        if let sport = store.selectedSportFilter {
            return store.athleteScopedActivities.filter { $0.sport == sport }
        }
        return store.athleteScopedActivities
    }

    private var athleteFilteredActivities: [Activity] {
        allActivitiesInCurrentSportScope
    }

    private var isAllAthletesPanelSelected: Bool {
        store.isAllAthletesSelected
    }

    private var canClearSelectedAthleteActivities: Bool {
        !store.isAllAthletesSelected && !store.athleteScopedActivities.isEmpty
    }

    private var clearActivitiesButtonTitle: String {
        if store.isAllAthletesSelected {
            return L10n.choose(
                simplifiedChinese: "先选择运动员再清空",
                english: "Select Athlete to Clear"
            )
        }
        return L10n.choose(
            simplifiedChinese: "清空当前运动员活动",
            english: "Clear Athlete Activities"
        )
    }

    private var searchFilteredActivities: [Activity] {
        let base = athleteFilteredActivities
        guard !searchText.isEmpty else { return base }

        return base.filter {
            $0.notes.localizedCaseInsensitiveContains(searchText) ||
            $0.sport.label.localizedCaseInsensitiveContains(searchText) ||
            athleteDisplayName(for: $0).localizedCaseInsensitiveContains(searchText)
        }
    }

    private func athleteDisplayName(for activity: Activity) -> String {
        if let name = normalizedNonEmpty(activity.athleteName) {
            return name
        }
        if let parsed = parseAthleteNameFromLegacyNotes(activity.notes) {
            return parsed
        }
        return L10n.choose(simplifiedChinese: "默认运动员", english: "Default Athlete")
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseAthleteNameFromLegacyNotes(_ notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separators = [
            "---来自 Fricu",
            "---from Fricu",
            " · Trainer ride",
            " · 训练骑行",
            "• Trainer ride",
            "• 训练骑行"
        ]
        for separator in separators {
            if let range = trimmed.range(of: separator, options: [.caseInsensitive]) {
                let candidate = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }

        return nil
    }

    private var activitiesByDay: [Date: [Activity]] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: searchFilteredActivities) { activity in
            calendar.startOfDay(for: activity.date)
        }
        return grouped.mapValues { rows in
            rows.sorted { $0.date > $1.date }
        }
    }

    private var visibleCalendarDays: Set<Date> {
        let calendar = Calendar.current
        switch calendarScope {
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: calendarAnchor)
                ?? DateInterval(start: calendar.startOfDay(for: calendarAnchor), duration: 7 * 86400)
            return Set((0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: interval.start).map { calendar.startOfDay(for: $0) }
            })
        case .month:
            return Set(monthGridDays(for: calendarAnchor))
        case .year:
            guard let yearStart = calendar.date(from: calendar.dateComponents([.year], from: calendarAnchor)) else {
                return []
            }
            var days: Set<Date> = []
            for monthOffset in 0..<12 {
                guard let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: yearStart) else { continue }
                for day in monthGridDays(for: monthDate) {
                    days.insert(day)
                }
            }
            return days
        }
    }

    private func monthGridDays(for date: Date) -> [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEndInclusive = calendar.date(byAdding: .day, value: -1, to: monthInterval.end)
            .map { calendar.startOfDay(for: $0) } ?? monthStart
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: monthEndInclusive)?.start ?? monthEndInclusive
        let lastGridDay = calendar.date(byAdding: .day, value: 6, to: lastWeekStart)
            .map { calendar.startOfDay(for: $0) } ?? monthEndInclusive

        var rows: [Date] = []
        var cursor = firstWeekStart
        while cursor <= lastGridDay {
            rows.append(calendar.startOfDay(for: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return rows
    }

    private var summaryRows: [Activity] {
        let base = searchFilteredActivities
        let calendar = Calendar.current
        if let selectedCalendarDay {
            return base.filter { calendar.isDate($0.date, inSameDayAs: selectedCalendarDay) }
        }
        let days = visibleCalendarDays
        guard !days.isEmpty else { return base }
        return base.filter { days.contains(calendar.startOfDay(for: $0.date)) }
    }

    private var activities: [Activity] {
        guard let selectedCalendarDay else {
            return searchFilteredActivities
        }
        let calendar = Calendar.current
        return searchFilteredActivities.filter {
            calendar.isDate($0.date, inSameDayAs: selectedCalendarDay)
        }
    }

    private func clampLevel(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private var activitySummaryCards: [ActivitySummaryCardItem] {
        let rows = summaryRows
        let totalHours = rows.reduce(0.0) { $0 + Double($1.durationSec) / 3600.0 }
        let totalDistance = rows.reduce(0.0) { $0 + $1.distanceKm }
        let totalTSS = rows.reduce(0) { $0 + $1.tss }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let weeklyRows = rows.filter { calendar.startOfDay(for: $0.date) >= weekStart }
        let weeklyTSS = weeklyRows.reduce(0) { $0 + $1.tss }

        let latestDateText = rows.first?.date.formatted(date: .abbreviated, time: .omitted)
            ?? L10n.choose(simplifiedChinese: "无", english: "None")

        return [
            ActivitySummaryCardItem(
                id: "count",
                title: L10n.choose(simplifiedChinese: "活动数量", english: "Activities"),
                value: "\(rows.count)",
                subtitle: L10n.choose(simplifiedChinese: "当前日历范围", english: "Current calendar range"),
                tint: .blue,
                emphasis: clampLevel(Double(rows.count) / 240.0)
            ),
            ActivitySummaryCardItem(
                id: "weekly_tss",
                title: L10n.choose(simplifiedChinese: "近 7 天 TSS", english: "7-Day TSS"),
                value: "\(weeklyTSS)",
                subtitle: L10n.choose(simplifiedChinese: "短期训练压力", english: "Short-term training stress"),
                tint: .orange,
                emphasis: clampLevel(Double(weeklyTSS) / 700.0)
            ),
            ActivitySummaryCardItem(
                id: "hours",
                title: L10n.choose(simplifiedChinese: "总时长", english: "Total Hours"),
                value: String(format: "%.1f h", totalHours),
                subtitle: L10n.choose(simplifiedChinese: "导入活动累计", english: "Accumulated imported sessions"),
                tint: .teal,
                emphasis: clampLevel(totalHours / 160.0)
            ),
            ActivitySummaryCardItem(
                id: "distance",
                title: L10n.choose(simplifiedChinese: "总里程", english: "Total Distance"),
                value: String(format: "%.0f km", totalDistance),
                subtitle: L10n.choose(simplifiedChinese: "导入活动累计", english: "Accumulated imported sessions"),
                tint: .green,
                emphasis: clampLevel(totalDistance / 3500.0)
            ),
            ActivitySummaryCardItem(
                id: "tss",
                title: "TSS",
                value: "\(totalTSS)",
                subtitle: L10n.choose(simplifiedChinese: "总训练负荷", english: "Total training load"),
                tint: .purple,
                emphasis: clampLevel(Double(totalTSS) / 16000.0)
            ),
            ActivitySummaryCardItem(
                id: "latest",
                title: L10n.choose(simplifiedChinese: "最近活动", english: "Latest Activity"),
                value: latestDateText,
                subtitle: L10n.choose(simplifiedChinese: "最近一次训练日期", english: "Most recent session date"),
                tint: .indigo,
                emphasis: rows.isEmpty ? 0.0 : 0.55
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.choose(simplifiedChinese: "活动库", english: "Activity Library"))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                    Text(
                        L10n.choose(
                            simplifiedChinese: "更大的标题、分组统计卡和重点指标色条，帮助快速筛选与回顾。",
                            english: "Large heading, grouped summary cards, and metric bars for faster filtering and review."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 220)),
                        GridItem(.flexible(minimum: 220)),
                        GridItem(.flexible(minimum: 220))
                    ],
                    spacing: 10
                ) {
                    ForEach(activitySummaryCards) { item in
                        ActivitySummaryCard(item: item)
                    }
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                TextField("Search notes or sport", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                HStack {
                    Button("Import FIT/TCX/GPX") {
                        showImporter = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button(clearActivitiesButtonTitle, role: .destructive) {
                        showClearAllConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canClearSelectedAthleteActivities)

                    Text("Real parser enabled: FIT, TCX, GPX.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                if store.isAllAthletesSelected {
                    Text(
                        L10n.choose(
                            simplifiedChinese: "已禁用全库清空。请先在顶部下拉框选择某个运动员，再清空该运动员活动。",
                            english: "Global clear is disabled. Select an athlete from the top dropdown first, then clear only that athlete's activities."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                ActivityCalendarPanel(
                    activitiesByDay: activitiesByDay,
                    scope: $calendarScope,
                    anchor: $calendarAnchor,
                    selectedDay: $selectedCalendarDay
                )

                if let selectedCalendarDay {
                    HStack(spacing: 8) {
                        Text("\(L10n.choose(simplifiedChinese: "已按日期筛选", english: "Filtered by day")): \(selectedCalendarDay.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L10n.choose(simplifiedChinese: "清除筛选", english: "Clear Filter")) {
                            self.selectedCalendarDay = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if activities.isEmpty {
                    ContentUnavailableView("No matching activities", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    let lastActivityID = activities.last?.id
                    LazyVStack(spacing: 0) {
                        ForEach(activities) { activity in
                            Button {
                                selectedActivity = activity
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(activity.sport.label)
                                            .font(.headline)
                                        if isAllAthletesPanelSelected {
                                            Text(athleteDisplayName(for: activity))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                        }
                                        Spacer()
                                        Text(activity.date, style: .date)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }

                                    HStack(spacing: 16) {
                                        Text(activity.durationSec.asDuration)
                                        Text(String(format: "%.1f km", activity.distanceKm))
                                        Text("TSS \(activity.tss)")
                                        if let np = activity.normalizedPower {
                                            Text("NP \(np)W")
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                    if !activity.notes.isEmpty {
                                        Text(activity.notes)
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            if activity.id != lastActivityID {
                                Divider()
                            }
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .onChange(of: store.athletePanels.map(\.id)) { _, _ in
            guard let selectedCalendarDay else { return }
            let selected = Calendar.current.startOfDay(for: selectedCalendarDay)
            if activitiesByDay[selected] == nil {
                self.selectedCalendarDay = nil
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result, !urls.isEmpty {
                store.importActivityFiles(urls: urls)
            }
        }
        .alert(
            L10n.choose(simplifiedChinese: "清空活动？", english: "Clear activities?"),
            isPresented: $showClearAllConfirm
        ) {
            Button(L10n.choose(simplifiedChinese: "取消", english: "Cancel"), role: .cancel) {}
            Button(
                L10n.choose(
                    simplifiedChinese: "清空该运动员活动",
                    english: "Clear Athlete Activities"
                ),
                role: .destructive
            ) {
                selectedActivity = nil
                searchText = ""
                store.clearAllActivities()
            }
        } message: {
            if store.isAllAthletesSelected {
                Text(
                    L10n.choose(
                        simplifiedChinese: "这将从本地存储永久移除全部活动。",
                        english: "This will permanently remove all activities from local storage."
                    )
                )
            } else {
                Text(
                    L10n.choose(
                        simplifiedChinese: "这将从本地存储永久移除 \(store.selectedAthleteTitle) 的全部活动。",
                        english: "This will permanently remove activities for \(store.selectedAthleteTitle) from local storage."
                    )
                )
            }
        }
        .sheet(item: $selectedActivity) { activity in
            ActivityDetailSheet(
                activity: activity,
                profile: store.profile,
                loadSeries: store.loadSeries
            )
            .frame(minWidth: 820, minHeight: 620)
        }
    }
}

private struct ActivitySummaryCard: View {
    let item: ActivityLibraryView.ActivitySummaryCardItem

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
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(item.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(item.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(item.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ActivityPlatformPushButton: View {
    let title: String
    let isPrimary: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPrimary ? Color.white : Color.green)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isDisabled ? 0.55 : 1.0)
        .disabled(isDisabled)
    }

    private var backgroundColor: Color {
        isPrimary ? Color.green : Color.green.opacity(0.12)
    }
}

private struct ActivityCalendarPanel: View {
    let activitiesByDay: [Date: [Activity]]
    @Binding var scope: ActivityCalendarScope
    @Binding var anchor: Date
    @Binding var selectedDay: Date?

    private let calendar = Calendar.current

    private struct DisplayDay: Identifiable {
        let date: Date
        let inPrimaryRange: Bool
        var id: Date { date }
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let start = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[start...] + symbols[..<start])
    }

    private var periodTitle: String {
        switch scope {
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) ?? DateInterval(start: calendar.startOfDay(for: anchor), duration: 7 * 86400)
            let start = interval.start.formatted(date: .abbreviated, time: .omitted)
            let end = calendar.date(byAdding: .day, value: 6, to: interval.start)?.formatted(date: .abbreviated, time: .omitted) ?? start
            return "\(start) - \(end)"
        case .month:
            return anchor.formatted(.dateTime.year().month(.wide))
        case .year:
            return anchor.formatted(.dateTime.year())
        }
    }

    private var monthAnchorDatesInYear: [Date] {
        guard let yearStart = calendar.date(from: calendar.dateComponents([.year], from: anchor)) else { return [] }
        return (0..<12).compactMap { monthOffset in
            calendar.date(byAdding: .month, value: monthOffset, to: yearStart)
        }
    }

    private var visibleDays: [DisplayDay] {
        switch scope {
        case .week:
            return weekDays(for: anchor)
        case .month:
            return monthDays(for: anchor)
        case .year:
            return []
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        moveAnchor(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    Text(periodTitle)
                        .font(.headline)

                    Button {
                        moveAnchor(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Picker(L10n.choose(simplifiedChinese: "视图", english: "View"), selection: $scope) {
                        ForEach(ActivityCalendarScope.allCases) { viewScope in
                            Text(viewScope.title).tag(viewScope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                }

                if scope == .year {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(monthAnchorDatesInYear, id: \.self) { monthDate in
                            MonthMiniGridCard(
                                monthDate: monthDate,
                                selectedDay: selectedDay,
                                activitiesByDay: activitiesByDay,
                                onSelect: { day in
                                    toggleSelection(for: day)
                                }
                            )
                        }
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 36), spacing: 4), count: 7), spacing: 4) {
                        ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                            Text(symbol.uppercased())
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(visibleDays) { day in
                            ActivityCalendarDayCell(
                                day: day.date,
                                inPrimaryRange: day.inPrimaryRange,
                                selectedDay: selectedDay,
                                activityCount: activitiesByDay[day.date]?.count ?? 0,
                                sports: sportsForDay(day.date),
                                onTap: {
                                    toggleSelection(for: day.date)
                                }
                            )
                        }
                    }
                }

                ActivityCalendarLegendRow()
            }
        } label: {
            Text(L10n.choose(simplifiedChinese: "活动日历", english: "Activity Calendar"))
        }
        .onChange(of: scope) { _, _ in
            if let selectedDay {
                let day = calendar.startOfDay(for: selectedDay)
                if activitiesByDay[day] == nil {
                    self.selectedDay = nil
                }
            }
        }
    }

    private func weekDays(for date: Date) -> [DisplayDay] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86400)
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            return DisplayDay(date: calendar.startOfDay(for: day), inPrimaryRange: true)
        }
    }

    private func monthDays(for date: Date) -> [DisplayDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEndInclusive = calendar.date(byAdding: .day, value: -1, to: monthInterval.end).map { calendar.startOfDay(for: $0) } ?? monthStart
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: monthEndInclusive)?.start ?? monthEndInclusive
        let lastGridDay = calendar.date(byAdding: .day, value: 6, to: lastWeekStart).map { calendar.startOfDay(for: $0) } ?? monthEndInclusive

        var rows: [DisplayDay] = []
        var cursor = firstWeekStart
        while cursor <= lastGridDay {
            let day = calendar.startOfDay(for: cursor)
            let inMonth = day >= monthStart && day <= monthEndInclusive
            rows.append(DisplayDay(date: day, inPrimaryRange: inMonth))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return rows
    }

    private func moveAnchor(by direction: Int) {
        let value = direction == 0 ? 0 : (direction > 0 ? 1 : -1)
        switch scope {
        case .week:
            anchor = calendar.date(byAdding: .day, value: 7 * value, to: anchor) ?? anchor
        case .month:
            anchor = calendar.date(byAdding: .month, value: value, to: anchor) ?? anchor
        case .year:
            anchor = calendar.date(byAdding: .year, value: value, to: anchor) ?? anchor
        }
    }

    private func sportsForDay(_ day: Date) -> [SportType] {
        let rows = activitiesByDay[calendar.startOfDay(for: day)] ?? []
        guard !rows.isEmpty else { return [] }
        let counts = Dictionary(grouping: rows, by: \.sport).mapValues(\.count)
        return counts.keys.sorted { lhs, rhs in
            let lc = counts[lhs] ?? 0
            let rc = counts[rhs] ?? 0
            if lc != rc { return lc > rc }
            return lhs.rawValue < rhs.rawValue
        }
    }

    private func toggleSelection(for day: Date) {
        let target = calendar.startOfDay(for: day)
        if let selectedDay, calendar.isDate(selectedDay, inSameDayAs: target) {
            self.selectedDay = nil
        } else {
            self.selectedDay = target
        }
    }
}

private struct MonthMiniGridCard: View {
    let monthDate: Date
    let selectedDay: Date?
    let activitiesByDay: [Date: [Activity]]
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current

    private struct MiniDay: Identifiable {
        let date: Date
        let inMonth: Bool
        var id: Date { date }
    }

    private var monthTitle: String {
        monthDate.formatted(.dateTime.month(.abbreviated))
    }

    private var days: [MiniDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate) else { return [] }
        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEndInclusive = calendar.date(byAdding: .day, value: -1, to: monthInterval.end).map { calendar.startOfDay(for: $0) } ?? monthStart
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: monthEndInclusive)?.start ?? monthEndInclusive
        let lastGridDay = calendar.date(byAdding: .day, value: 6, to: lastWeekStart).map { calendar.startOfDay(for: $0) } ?? monthEndInclusive

        var rows: [MiniDay] = []
        var cursor = firstWeekStart
        while cursor <= lastGridDay {
            let day = calendar.startOfDay(for: cursor)
            rows.append(MiniDay(date: day, inMonth: day >= monthStart && day <= monthEndInclusive))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(monthTitle)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 10), spacing: 2), count: 7), spacing: 2) {
                ForEach(days) { day in
                    let rows = activitiesByDay[day.date] ?? []
                    let hasActivity = !rows.isEmpty
                    let sports = orderedSports(rows)
                    let primaryColor = sports.first.map(ActivitySportPalette.color(for:)) ?? .clear
                    let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false

                    Button {
                        onSelect(day.date)
                    } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(hasActivity ? primaryColor.opacity(day.inMonth ? 0.95 : 0.35) : Color.secondary.opacity(day.inMonth ? 0.12 : 0.05))
                            .frame(height: 8)
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color.accentColor, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(day.date.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func orderedSports(_ rows: [Activity]) -> [SportType] {
        let counts = Dictionary(grouping: rows, by: \.sport).mapValues(\.count)
        return counts.keys.sorted { lhs, rhs in
            let lc = counts[lhs] ?? 0
            let rc = counts[rhs] ?? 0
            if lc != rc { return lc > rc }
            return lhs.rawValue < rhs.rawValue
        }
    }
}

private struct ActivityCalendarDayCell: View {
    let day: Date
    let inPrimaryRange: Bool
    let selectedDay: Date?
    let activityCount: Int
    let sports: [SportType]
    let onTap: () -> Void

    private let calendar = Calendar.current

    private var isToday: Bool {
        calendar.isDateInToday(day)
    }

    private var isSelected: Bool {
        selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
    }

    private var dayText: String {
        let value = calendar.component(.day, from: day)
        return "\(value)"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(dayText)
                        .font(.caption.bold())
                        .foregroundStyle(isToday ? .blue : (inPrimaryRange ? .primary : .secondary))
                    Spacer(minLength: 0)
                    if activityCount > 0 {
                        Text("\(activityCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if sports.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    HStack(spacing: 3) {
                        ForEach(Array(sports.prefix(4)), id: \.rawValue) { sport in
                            Circle()
                                .fill(ActivitySportPalette.color(for: sport))
                                .frame(width: 6, height: 6)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }
        if !inPrimaryRange {
            return Color.secondary.opacity(0.05)
        }
        if isToday {
            return Color.blue.opacity(0.10)
        }
        return Color.secondary.opacity(0.08)
    }
}

private struct ActivityCalendarLegendRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(SportType.allCases, id: \.rawValue) { sport in
                HStack(spacing: 4) {
                    Circle()
                        .fill(ActivitySportPalette.color(for: sport))
                        .frame(width: 7, height: 7)
                    Text(sport.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ActivitySportPalette {
    static func color(for sport: SportType) -> Color {
        switch sport {
        case .cycling:
            return .blue
        case .running:
            return .orange
        case .swimming:
            return .teal
        case .strength:
            return .purple
        }
    }
}

private struct ActivityDetailSheet: View {
    @Environment(\.appChartDisplayMode) private var chartDisplayMode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let activity: Activity
    let profile: AthleteProfile
    let loadSeries: [DailyLoadPoint]
    @State private var preloadedSensorSamples: [ActivitySensorSample] = []
    @State private var hasLoadedSensorSamples = false
    @State private var derived = ActivityDetailDerived.empty
    @State private var derivedComputationGeneration: UInt64 = 0
    @State private var isComputingDerived = false
    @State private var showDeleteActivityConfirm = false

    private var activityFTP: Int {
        profile.ftpWatts(for: activity.sport)
    }

    private var activityThresholdHR: Int {
        profile.thresholdHeartRate(for: activity.sport, on: activity.date)
    }

    private var activityLTHRRange: HeartRateThresholdRange? {
        profile.heartRateThresholdRange(for: activity.sport, on: activity.date)
    }

    private var avgSpeedKPH: Double? {
        guard activity.durationSec > 0, activity.distanceKm > 0 else { return nil }
        return activity.distanceKm / (Double(activity.durationSec) / 3600.0)
    }

    private var runningPaceMinPerKm: Double? {
        guard activity.sport == .running, activity.distanceKm > 0 else { return nil }
        return (Double(activity.durationSec) / 60.0) / activity.distanceKm
    }

    private var swimPaceMinPer100m: Double? {
        guard activity.sport == .swimming, activity.distanceKm > 0 else { return nil }
        let total100m = activity.distanceKm * 10.0
        guard total100m > 0 else { return nil }
        return (Double(activity.durationSec) / 60.0) / total100m
    }

    private var intensityFactor: Double? {
        guard let np = activity.normalizedPower, activityFTP > 0 else { return nil }
        return Double(np) / Double(activityFTP)
    }

    private var tssPerHour: Double {
        let hours = max(1.0 / 60.0, Double(activity.durationSec) / 3600.0)
        return Double(activity.tss) / hours
    }

    private var estimatedWorkKJ: Double? {
        guard let np = activity.normalizedPower else { return nil }
        return Double(np * activity.durationSec) / 1000.0
    }

    private var peakPowerSourceText: String {
        if activity.intervals.contains(where: { $0.actualPower != nil || $0.targetPower != nil }) {
            return "区间功率"
        }
        if activity.normalizedPower != nil {
            return "活动概要NP估算"
        }
        return "无功率数据"
    }

    private var peakPowerTimelineWatts: [Double] {
        guard activity.durationSec > 0 else { return [] }

        let fallbackPower = activity.normalizedPower.map(Double.init)
        if !activity.intervals.isEmpty {
            var rows: [Double] = []
            rows.reserveCapacity(activity.durationSec)
            var assigned = 0

            for effort in activity.intervals {
                let duration = max(0, effort.durationSec)
                guard duration > 0 else { continue }
                guard let power = effort.actualPower.map(Double.init) ?? effort.targetPower.map(Double.init) ?? fallbackPower else {
                    return []
                }
                rows.append(contentsOf: repeatElement(power, count: duration))
                assigned += duration
            }

            if assigned < activity.durationSec {
                guard let fallbackPower else { return [] }
                rows.append(contentsOf: repeatElement(fallbackPower, count: activity.durationSec - assigned))
            }

            if !rows.isEmpty {
                return rows
            }
        }

        guard let fallbackPower else { return [] }
        return Array(repeating: fallbackPower, count: activity.durationSec)
    }

    private func peakPower(minutes: Int, timeline: [Double]) -> Double? {
        let windowSec = minutes * 60
        guard windowSec > 0, timeline.count >= windowSec else { return nil }

        var rolling = timeline[0..<windowSec].reduce(0.0, +)
        var best = rolling
        if timeline.count > windowSec {
            for idx in windowSec..<timeline.count {
                rolling += timeline[idx] - timeline[idx - windowSec]
                best = max(best, rolling)
            }
        }
        return best / Double(windowSec)
    }

    private func peakPower(seconds: Int, timeline: [Double]) -> Double? {
        guard seconds > 0, timeline.count >= seconds else { return nil }

        var rolling = timeline[0..<seconds].reduce(0.0, +)
        var best = rolling
        if timeline.count > seconds {
            for idx in seconds..<timeline.count {
                rolling += timeline[idx] - timeline[idx - seconds]
                best = max(best, rolling)
            }
        }
        return best / Double(seconds)
    }

    private var dayLoadPoint: DailyLoadPoint? {
        let calendar = Calendar.current
        return loadSeries.first { calendar.isDate($0.date, inSameDayAs: activity.date) }
    }

    private var activitySensorSamples: [ActivitySensorSample] {
        preloadedSensorSamples
    }

    private var traceTargetPoints: Int {
#if os(iOS)
        return 360
#else
        return 600
#endif
    }

    private var powerTracePoints: [ActivityTracePoint] {
        derived.powerTracePoints
    }

    private var heartRateTracePoints: [ActivityTracePoint] {
        derived.heartRateTracePoints
    }

    private func computePowerTracePoints(from sensorSamples: [ActivitySensorSample]) -> [ActivityTracePoint] {
        if !sensorSamples.isEmpty {
            let streamPoints = sensorSamples.enumerated().compactMap { idx, sample -> ActivityTracePoint? in
                guard let power = sample.power, power > 0 else { return nil }
                return ActivityTracePoint(id: idx, minute: sample.timeSec / 60.0, value: power)
            }
            if streamPoints.count >= 2 {
                return downsampleTrace(streamPoints, targetPoints: traceTargetPoints)
            }
        }

        let totalMin = max(1.0, Double(activity.durationSec) / 60.0)

        var points: [ActivityTracePoint] = []
        var nextID = 0
        func appendPoint(minute: Double, value: Double) {
            points.append(ActivityTracePoint(id: nextID, minute: minute, value: value))
            nextID += 1
        }

        if !activity.intervals.isEmpty {
            var cursor = 0.0
            for effort in activity.intervals {
                let durationMin = max(1.0 / 60.0, Double(effort.durationSec) / 60.0)
                let power = effort.actualPower ?? effort.targetPower ?? activity.normalizedPower
                if let power {
                    appendPoint(minute: cursor, value: Double(power))
                    appendPoint(minute: min(totalMin, cursor + durationMin), value: Double(power))
                }
                cursor += durationMin
            }
        }

        if points.count >= 2 {
            return downsampleTrace(points, targetPoints: traceTargetPoints)
        }

        guard let np = activity.normalizedPower else { return [] }
        appendPoint(minute: 0.0, value: Double(np))
        appendPoint(minute: totalMin, value: Double(np))
        return downsampleTrace(points, targetPoints: traceTargetPoints)
    }

    private func computeHeartRateTracePoints(from sensorSamples: [ActivitySensorSample]) -> [ActivityTracePoint] {
        if !sensorSamples.isEmpty {
            let streamPoints = sensorSamples.enumerated().compactMap { idx, sample -> ActivityTracePoint? in
                guard let hr = sample.heartRate, hr > 0 else { return nil }
                return ActivityTracePoint(id: idx, minute: sample.timeSec / 60.0, value: hr)
            }
            if streamPoints.count >= 2 {
                return downsampleTrace(streamPoints, targetPoints: traceTargetPoints)
            }
        }

        let totalMin = max(1.0, Double(activity.durationSec) / 60.0)

        var points: [ActivityTracePoint] = []
        var nextID = 0
        func appendPoint(minute: Double, value: Double) {
            points.append(ActivityTracePoint(id: nextID, minute: minute, value: value))
            nextID += 1
        }

        if !activity.intervals.isEmpty, let avgHR = activity.avgHeartRate {
            var cursor = 0.0
            for effort in activity.intervals {
                let durationMin = max(1.0 / 60.0, Double(effort.durationSec) / 60.0)
                let power = effort.actualPower ?? effort.targetPower ?? activity.normalizedPower
                let hrValue: Double
                if let power, let np = activity.normalizedPower, np > 0 {
                    let deltaPower = Double(power - np)
                    hrValue = clamp(Double(avgHR) + deltaPower * 0.08, min: 70, max: 210)
                } else {
                    hrValue = Double(avgHR)
                }
                appendPoint(minute: cursor, value: hrValue)
                appendPoint(minute: min(totalMin, cursor + durationMin), value: hrValue)
                cursor += durationMin
            }
        }

        if points.count >= 2 {
            return downsampleTrace(points, targetPoints: traceTargetPoints)
        }

        guard let avgHR = activity.avgHeartRate else { return [] }
        appendPoint(minute: 0.0, value: Double(avgHR))
        appendPoint(minute: totalMin, value: Double(avgHR))
        return downsampleTrace(points, targetPoints: traceTargetPoints)
    }

    private func downsampleTrace(_ points: [ActivityTracePoint], targetPoints: Int) -> [ActivityTracePoint] {
        guard points.count > targetPoints, targetPoints >= 2 else { return points }
        let stride = max(1, Int(ceil(Double(points.count) / Double(targetPoints))))
        var sampled = points.enumerated().compactMap { idx, point in
            idx % stride == 0 ? point : nil
        }
        if let last = points.last, sampled.last?.id != last.id {
            sampled.append(last)
        }
        return sampled
    }

    private var powerTraceSourceText: String {
        if !activitySensorSamples.isEmpty {
            return "来源: 原始传感器流 (FIT/TCX/GPX)"
        }
        if activity.intervals.contains(where: { $0.actualPower != nil || $0.targetPower != nil }) {
            return "来源: 区间功率"
        }
        if activity.normalizedPower != nil {
            return "来源: 活动概要估算"
        }
        return "来源: 无功率数据"
    }

    private var heartRateSourceText: String {
        if !activitySensorSamples.isEmpty {
            return "来源: 原始传感器流 (FIT/TCX/GPX)"
        }
        if !activity.intervals.isEmpty, activity.avgHeartRate != nil {
            return "来源: 区间强度估算心率"
        }
        if activity.avgHeartRate != nil {
            return "来源: 活动概要估算"
        }
        return "来源: 无心率数据"
    }

    private var powerAverageValue: Double? {
        derived.powerAverageValue
    }

    private var heartRateAverageValue: Double? {
        derived.heartRateAverageValue
    }

    private var powerDistributionBins: [ActivityDistributionBin] {
        distributionBins(from: powerTracePoints, binCount: 12, unit: "W")
    }

    private var heartRateDistributionBins: [ActivityDistributionBin] {
        distributionBins(from: heartRateTracePoints, binCount: 12, unit: "bpm")
    }

    private func distributionBins(from points: [ActivityTracePoint], binCount: Int, unit: String) -> [ActivityDistributionBin] {
        let values = points.map(\.value).filter { $0.isFinite && $0 > 0 }
        guard values.count >= 2 else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let span = max(1.0, maxValue - minValue)
        let safeBinCount = max(4, binCount)
        let binWidth = span / Double(safeBinCount)

        var counts = Array(repeating: 0, count: safeBinCount)
        for value in values {
            let rawIndex = Int((value - minValue) / binWidth)
            let index = min(max(rawIndex, 0), safeBinCount - 1)
            counts[index] += 1
        }

        let total = max(1, counts.reduce(0, +))
        return counts.enumerated().map { idx, count in
            let lower = minValue + Double(idx) * binWidth
            let upper = idx == safeBinCount - 1 ? maxValue : lower + binWidth
            return ActivityDistributionBin(
                id: idx,
                rangeLabel: "\(Int(lower.rounded()))-\(Int(upper.rounded())) \(unit)",
                valueMidpoint: (lower + upper) * 0.5,
                sampleCount: count,
                fraction: Double(count) / Double(total)
            )
        }
    }

    private var durationHours: Double {
        max(1.0 / 3600.0, Double(activity.durationSec) / 3600.0)
    }

    private var durationMinutes: Double {
        Double(activity.durationSec) / 60.0
    }

    private var decouplingTracePoints: [ActivityTracePoint] {
        derived.decouplingTracePoints
    }

    private var decouplingSummary: ActivityDecouplingSummary? {
        derived.decouplingSummary
    }

    private var balanceSummary: ActivityBalanceSummary? {
        derived.balanceSummary
    }

    private var hrPwScatterPoints: [ActivityHrPwScatterPoint] {
        derived.hrPwScatterPoints
    }

    private var hrPwRenderableScatterPoints: [ActivityHrPwScatterPoint] {
        derived.hrPwRenderableScatterPoints
    }

    private var hrPwDelaySec: Int {
        derived.hrPwDelaySec
    }

    private var hrPwAveragePower: Double {
        derived.hrPwAveragePower
    }

    private var hrPwAverageHR: Double {
        derived.hrPwAverageHR
    }

    private var hrPwRegression: ActivityHrPwRegression? {
        derived.hrPwRegression
    }

    private var hrPwPowerAtThreshold: Double? {
        derived.hrPwPowerAtThreshold
    }

    private var hrPwRegressionVisiblePoints: [ActivityTracePoint] {
        derived.hrPwRegressionVisiblePoints
    }

    private var hrPwXDomain: ClosedRange<Double> {
        0...500
    }

    private var hrPwYDomain: ClosedRange<Double> {
        derived.hrPwYDomain
    }

    private var hrPwZoneBands: [ActivityPowerZoneBand] {
        let ratios: [Double] = [0.0, 0.55, 0.75, 0.90, 1.05, 1.20, 1.50]
        let labels = ["Z1", "Z2", "Z3", "Z4", "Z5", "Z6", "Z7"]
        let domainUpper = hrPwXDomain.upperBound
        let ftp = max(Double(activityFTP), 1)

        var rows: [ActivityPowerZoneBand] = []
        for idx in labels.indices {
            let lower = ftp * ratios[idx]
            let upper = idx < ratios.count - 1 ? ftp * ratios[idx + 1] : domainUpper
            if upper <= lower { continue }
            rows.append(
                ActivityPowerZoneBand(
                    id: idx,
                    label: labels[idx],
                    lowerPower: max(0, lower),
                    upperPower: min(domainUpper, upper),
                    color: hrPwZoneColor(for: idx)
                )
            )
        }

        if let lastUpper = rows.last?.upperPower, lastUpper < domainUpper {
            rows.append(
                ActivityPowerZoneBand(
                    id: 99,
                    label: "Z7+",
                    lowerPower: lastUpper,
                    upperPower: domainUpper,
                    color: hrPwZoneColor(for: 6)
                )
            )
        }
        return rows
    }

    private func rollingMean(_ values: [Double], window: Int) -> [Double] {
        guard !values.isEmpty else { return [] }
        let w = max(1, window)
        var out = Array(repeating: 0.0, count: values.count)
        var sum = 0.0

        for idx in values.indices {
            sum += values[idx]
            if idx >= w {
                sum -= values[idx - w]
            }
            let n = min(idx + 1, w)
            out[idx] = sum / Double(n)
        }
        return out
    }

    private func hrPwZoneColor(for index: Int) -> Color {
        switch index {
        case 0: return Color(red: 0.86, green: 0.56, blue: 0.90)
        case 1: return Color(red: 0.64, green: 0.56, blue: 0.90)
        case 2: return Color(red: 0.47, green: 0.74, blue: 0.93)
        case 3: return Color(red: 0.43, green: 0.89, blue: 0.78)
        case 4: return Color(red: 0.58, green: 0.88, blue: 0.53)
        case 5: return Color(red: 0.92, green: 0.83, blue: 0.49)
        default: return Color(red: 0.94, green: 0.59, blue: 0.62)
        }
    }

    private func hrPwTimeColor(for segment: Int) -> Color {
        let hue = (Double((60 + segment * (360 / 36)) % 360)) / 360.0
        return Color(hue: hue, saturation: 0.95, brightness: 0.95)
    }

    private func sampleStepSeconds(for minutes: [Double]) -> Double {
        guard minutes.count >= 2 else { return 1.0 }
        let sorted = minutes.sorted()

        var positiveDeltasSec: [Double] = []
        positiveDeltasSec.reserveCapacity(max(1, sorted.count - 1))
        for idx in 1..<sorted.count {
            let delta = (sorted[idx] - sorted[idx - 1]) * 60.0
            if delta.isFinite, delta > 0 {
                positiveDeltasSec.append(delta)
            }
        }

        if !positiveDeltasSec.isEmpty {
            positiveDeltasSec.sort()
            return positiveDeltasSec[positiveDeltasSec.count / 2]
        }

        let spanSec = max(1.0, (sorted.last! - sorted.first!) * 60.0)
        return spanSec / Double(max(1, sorted.count - 1))
    }

    private func gcSmoothAndClip(
        samples: [ActivityPowerHeartSample],
        smoothSec: Double,
        minHr: Double,
        minPower: Double,
        maxPower: Double
    ) -> [ActivityPowerHeartSample] {
        guard samples.count >= 2 else { return [] }
        let sorted = samples.sorted { $0.minute < $1.minute }
        let stepSec = max(1.0, sampleStepSeconds(for: sorted.map(\.minute)))
        let window = max(1, Int(round(smoothSec / stepSec)))
        let smoothPower = rollingMean(sorted.map(\.power), window: window)
        let smoothHr = rollingMean(sorted.map(\.hr), window: window)

        return sorted.indices.compactMap { idx in
            let power = smoothPower[idx]
            let hr = smoothHr[idx]
            guard hr >= minHr, power >= minPower, power < maxPower else { return nil }
            return ActivityPowerHeartSample(minute: sorted[idx].minute, power: power, hr: hr)
        }
    }

    private func gcDecimate(samples: [ActivityPowerHeartSample], targetStepSec: Double) -> [ActivityPowerHeartSample] {
        guard samples.count >= 2 else { return samples }
        let sorted = samples.sorted { $0.minute < $1.minute }
        let stepSec = max(1.0, sampleStepSeconds(for: sorted.map(\.minute)))
        let strideCount = max(1, Int(round(targetStepSec / stepSec)))
        var rows = sorted.enumerated().compactMap { idx, sample in
            idx % strideCount == 0 ? sample : nil
        }
        if let last = sorted.last, rows.last?.minute != last.minute {
            rows.append(last)
        }
        return rows
    }

    private func delayedSeriesForRegression(
        samples: [ActivityPowerHeartSample],
        delaySec: Int
    ) -> (powers: [Double], hearts: [Double])? {
        guard samples.count >= 3 else { return nil }
        let sorted = samples.sorted { $0.minute < $1.minute }
        let stepSec = max(1.0, sampleStepSeconds(for: sorted.map(\.minute)))
        let delaySamples = max(0, Int(round(Double(delaySec) / stepSec)))
        guard delaySamples < sorted.count - 2 else { return nil }

        let powers = sorted.dropLast(delaySamples).map(\.power)
        let hearts = sorted.dropFirst(delaySamples).map(\.hr)
        guard powers.count == hearts.count, powers.count >= 3 else { return nil }
        return (powers, hearts)
    }

    private func gcBestDelay(samples: [ActivityPowerHeartSample], minDelaySec: Int, maxDelaySec: Int) -> Int {
        let sorted = samples.sorted { $0.minute < $1.minute }
        guard sorted.count >= 60 else { return 0 }
        var bestDelay = 0
        var bestCorrelation = 0.0
        for delay in minDelaySec...maxDelaySec {
            guard let delayed = delayedSeriesForRegression(samples: sorted, delaySec: delay) else { continue }
            let r = correlation(delayed.powers, delayed.hearts)
            if r > bestCorrelation {
                bestCorrelation = r
                bestDelay = delay
            }
        }
        return bestDelay
    }

    private func correlation(_ xs: [Double], _ ys: [Double]) -> Double {
        guard xs.count == ys.count, xs.count >= 3 else { return 0 }
        let xMean = xs.reduce(0, +) / Double(xs.count)
        let yMean = ys.reduce(0, +) / Double(ys.count)
        var cov = 0.0
        var varX = 0.0
        var varY = 0.0
        for idx in xs.indices {
            let dx = xs[idx] - xMean
            let dy = ys[idx] - yMean
            cov += dx * dy
            varX += dx * dx
            varY += dy * dy
        }
        guard varX > 1e-9, varY > 1e-9 else { return 0 }
        return cov / sqrt(varX * varY)
    }

    private func pairedPowerHeartRateSamples(
        maxSamples: Int,
        sensorSamples: [ActivitySensorSample],
        powerPoints: [ActivityTracePoint],
        heartRatePoints: [ActivityTracePoint]
    ) -> [ActivityPowerHeartSample] {
        if !sensorSamples.isEmpty {
            let direct = sensorSamples.compactMap { sample -> ActivityPowerHeartSample? in
                guard
                    let power = sample.power,
                    let hr = sample.heartRate,
                    power > 0,
                    hr > 0
                else {
                    return nil
                }
                return ActivityPowerHeartSample(minute: sample.timeSec / 60.0, power: power, hr: hr)
            }
            if direct.count >= 2 {
                if direct.count <= maxSamples {
                    return direct
                }
                let step = max(1, direct.count / max(maxSamples, 1))
                return direct.enumerated().compactMap { idx, sample in
                    idx % step == 0 ? sample : nil
                }
            }
        }

        guard
            let maxMinute = min(powerPoints.last?.minute ?? .nan, heartRatePoints.last?.minute ?? .nan) as Double?,
            maxMinute.isFinite,
            maxMinute > 0,
            maxSamples > 2
        else { return [] }

        var rows: [ActivityPowerHeartSample] = []
        for idx in 0..<maxSamples {
            let ratio = Double(idx) / Double(maxSamples - 1)
            let minute = maxMinute * ratio
            guard
                let power = interpolatedValue(at: minute, points: powerPoints),
                let hr = interpolatedValue(at: minute, points: heartRatePoints),
                power > 0,
                hr > 0
            else { continue }
            rows.append(ActivityPowerHeartSample(minute: minute, power: power, hr: hr))
        }
        return rows
    }

    private func interpolatedValue(at minute: Double, points: [ActivityTracePoint]) -> Double? {
        guard points.count >= 2 else { return nil }
        if minute <= points[0].minute { return points[0].value }
        if minute >= points[points.count - 1].minute { return points[points.count - 1].value }

        for idx in 1..<points.count {
            let left = points[idx - 1]
            let right = points[idx]
            if minute <= right.minute {
                let span = max(1e-6, right.minute - left.minute)
                let ratio = (minute - left.minute) / span
                return left.value + (right.value - left.value) * ratio
            }
        }
        return nil
    }

    private var tssMethodText: String {
        if activity.normalizedPower != nil, activityFTP > 0 {
            return "计算: TSS = h × (NP / FTP)^2 × 100"
        }
        if activity.avgHeartRate != nil, activityThresholdHR > 0 {
            return "计算: TSS = h × (AvgHR / LTHR)^2 × 100 (心率估算)"
        }
        return "计算: TSS = h × 45 (兜底估算)"
    }

    private var tssInputsText: String {
        if let np = activity.normalizedPower, activityFTP > 0 {
            let ifValue = Double(np) / Double(activityFTP)
            return String(
                format: "参数: h=%.2f, NP=%dW, FTP=%dW, IF=%.2f",
                durationHours, np, activityFTP, ifValue
            )
        }
        if let hr = activity.avgHeartRate, activityThresholdHR > 0 {
            let hrRatio = Double(hr) / Double(activityThresholdHR)
            let sourceText: String
            if let range = activityLTHRRange {
                sourceText = "参数: 活动日=\(activity.date.formatted(date: .abbreviated, time: .omitted)), 命中LTHR区间=\(range.startDate.formatted(date: .abbreviated, time: .omitted))~\(range.endDate?.formatted(date: .abbreviated, time: .omitted) ?? "∞")"
            } else {
                sourceText = "参数: 活动日=\(activity.date.formatted(date: .abbreviated, time: .omitted)), 使用当前运动默认LTHR"
            }
            return String(
                format: "参数: h=%.2f, AvgHR=%dbpm, LTHR=%dbpm, HR/LTHR=%.2f\n%@",
                durationHours, hr, activityThresholdHR, hrRatio
                , sourceText
            )
        }
        return String(format: "参数: h=%.2f, fallback=45 TSS/h", durationHours)
    }

    private var metrics: [ActivityMetricCardModel] {
        derived.metrics
    }

    private func buildMetrics(
        decouplingSummary: ActivityDecouplingSummary?,
        balanceSummary: ActivityBalanceSummary?
    ) -> [ActivityMetricCardModel] {
        let peakPowerWindowsMin = [60, 30, 20, 10, 5, 1]
        let peakPowerWindowsSec = [30, 20, 15, 10, 1]
        let peakPowerTimeline = peakPowerTimelineWatts
        let peakPowerValues: [Int: Double?] = Dictionary(
            uniqueKeysWithValues: peakPowerWindowsMin.map { minutes in
                (minutes, peakPower(minutes: minutes, timeline: peakPowerTimeline))
            }
        )
        let peakPowerValuesSec: [Int: Double?] = Dictionary(
            uniqueKeysWithValues: peakPowerWindowsSec.map { seconds in
                (seconds, peakPower(seconds: seconds, timeline: peakPowerTimeline))
            }
        )

        var rows: [ActivityMetricCardModel] = [
            .init(
                title: "Duration",
                value: activity.durationSec.asDuration,
                hint: "训练时长",
                method: "计算: Duration = moving_time",
                inputs: "参数: moving_time=\(activity.durationSec)s"
            ),
            .init(
                title: "Distance",
                value: String(format: "%.1f km", activity.distanceKm),
                hint: "总里程",
                method: "计算: Distance(km) = Distance(m) / 1000",
                inputs: String(format: "参数: Distance=%.1fkm (%.0fm)", activity.distanceKm, activity.distanceKm * 1000.0)
            ),
            .init(
                title: "TSS",
                value: "\(activity.tss)",
                hint: "训练负荷",
                method: tssMethodText,
                inputs: tssInputsText
            ),
            .init(
                title: "TSS/h",
                value: String(format: "%.0f", tssPerHour),
                hint: "负荷密度",
                method: "计算: TSS/h = TSS / h",
                inputs: String(format: "参数: TSS=%d, h=%.2f", activity.tss, durationHours)
            )
        ]

        for minutes in peakPowerWindowsMin {
            let windowSec = minutes * 60
            let peak = peakPowerValues[minutes] ?? nil
            let valueText = peak.map { String(format: "%.0f W", $0) } ?? "N/A"
            let inputsText: String
            if peak != nil {
                inputsText = String(
                    format: "参数: 窗口=%dmin(%ds), 样本时长=%ds, 来源=%@",
                    minutes, windowSec, peakPowerTimeline.count, peakPowerSourceText
                )
            } else {
                inputsText = String(
                    format: "参数: 窗口=%dmin(%ds), 样本时长=%ds, 来源=%@ (活动时长不足或无功率数据)",
                    minutes, windowSec, peakPowerTimeline.count, peakPowerSourceText
                )
            }
            rows.append(
                .init(
                    title: "\(minutes) min Peak Power",
                    value: valueText,
                    hint: "滚动窗口峰值平均功率",
                    method: "计算: PeakPower_t = max(rolling_mean_power(t 秒窗口))",
                    inputs: inputsText
                )
            )
        }

        for seconds in peakPowerWindowsSec {
            let peak = peakPowerValuesSec[seconds] ?? nil
            let valueText = peak.map { String(format: "%.0f W", $0) } ?? "N/A"
            let inputsText: String
            if peak != nil {
                inputsText = String(
                    format: "参数: 窗口=%ds, 样本时长=%ds, 来源=%@",
                    seconds, peakPowerTimeline.count, peakPowerSourceText
                )
            } else {
                inputsText = String(
                    format: "参数: 窗口=%ds, 样本时长=%ds, 来源=%@ (活动时长不足或无功率数据)",
                    seconds, peakPowerTimeline.count, peakPowerSourceText
                )
            }
            rows.append(
                .init(
                    title: seconds == 1 ? "Peak 1 second Power" : "\(seconds) sec Peak Power",
                    value: valueText,
                    hint: "短时冲刺峰值平均功率",
                    method: "计算: PeakPower_t = max(rolling_mean_power(t 秒窗口))",
                    inputs: inputsText
                )
            )
        }

        if let avgSpeedKPH {
            rows.append(
                .init(
                    title: "Avg Speed",
                    value: String(format: "%.1f km/h", avgSpeedKPH),
                    hint: "平均速度",
                    method: "计算: AvgSpeed = Distance(km) / h",
                    inputs: String(format: "参数: Distance=%.1fkm, h=%.2f", activity.distanceKm, durationHours)
                )
            )
        }

        if let runningPaceMinPerKm {
            rows.append(
                .init(
                    title: "Pace",
                    value: runningPaceMinPerKm.mmss,
                    hint: "平均配速 /km",
                    method: "计算: Pace(min/km) = Duration(min) / Distance(km)",
                    inputs: String(format: "参数: Duration=%.1fmin, Distance=%.1fkm", durationMinutes, activity.distanceKm)
                )
            )
        }

        if let swimPaceMinPer100m {
            rows.append(
                .init(
                    title: "Swim Pace",
                    value: swimPaceMinPer100m.mmss,
                    hint: "平均配速 /100m",
                    method: "计算: SwimPace(min/100m) = Duration(min) / Distance(100m)",
                    inputs: String(
                        format: "参数: Duration=%.1fmin, Distance=%.1f×100m",
                        durationMinutes, activity.distanceKm * 10.0
                    )
                )
            )
        }

        if let np = activity.normalizedPower {
            rows.append(
                .init(
                    title: "NP",
                    value: "\(np) W",
                    hint: "标准化功率",
                    method: "计算: NP = (mean(P^4))^(1/4)（若有功率序列）",
                    inputs: "参数: NP=\(np)W"
                )
            )
        }

        if let intensityFactor {
            rows.append(
                .init(
                    title: "IF",
                    value: String(format: "%.2f", intensityFactor),
                    hint: "相对 FTP 强度",
                    method: "计算: IF = NP / FTP",
                    inputs: String(
                        format: "参数: NP=%dW, FTP=%dW",
                        activity.normalizedPower ?? 0, activityFTP
                    )
                )
            )
        }

        if let hr = activity.avgHeartRate {
            rows.append(
                .init(
                    title: "Avg HR",
                    value: "\(hr) bpm",
                    hint: "平均心率",
                    method: "计算: AvgHR = mean(HR samples)",
                    inputs: "参数: AvgHR=\(hr)bpm"
                )
            )
            if activityThresholdHR > 0 {
                let ratio = Double(hr) / Double(activityThresholdHR)
                rows.append(
                    .init(
                        title: "HR/LTHR",
                        value: String(format: "%.0f%%", ratio * 100),
                        hint: "心率压力",
                        method: "计算: HR/LTHR = AvgHR / LTHR(date-matched)",
                        inputs: "参数: AvgHR=\(hr)bpm, LTHR=\(activityThresholdHR)bpm, Date=\(activity.date.formatted(date: .abbreviated, time: .omitted))"
                    )
                )
            }
        }

        if let estimatedWorkKJ {
            rows.append(
                .init(
                    title: "Est. Work",
                    value: String(format: "%.0f kJ", estimatedWorkKJ),
                    hint: "估算机械做功",
                    method: "计算: Work(kJ) = NP × Duration(s) / 1000",
                    inputs: String(
                        format: "参数: NP=%dW, Duration=%ds",
                        activity.normalizedPower ?? 0, activity.durationSec
                    )
                )
            )
        }

        if let decoupling = decouplingSummary {
            rows.append(
                .init(
                    title: "Decoupling",
                    value: String(format: "%.1f%%", decoupling.ratePct),
                    hint: "心率-功率解耦率",
                    method: "计算: Decoupling% = (EF_first - EF_second) / EF_first × 100，EF=Power/HR",
                    inputs: String(
                        format: "参数: EF_first=%.3f, EF_second=%.3f, 样本点=%d, 时长=%.0fmin",
                        decoupling.efFirst, decoupling.efSecond, decoupling.sampleCount, durationMinutes
                    )
                )
            )
        }

        if activity.sport == .cycling {
            if let balanceSummary {
                rows.append(
                    .init(
                        title: "L/R Balance (Avg)",
                        value: String(format: "L%.1f%% / R%.1f%%", balanceSummary.averageLeftPercent, balanceSummary.averageRightPercent),
                        hint: "全程左右脚平均功率占比",
                        method: "计算: Avg(L/R) = 全部有效采样均值",
                        inputs: String(format: "参数: 样本点=%d, 偏移=|L-50|=%.1f%%", balanceSummary.sampleCount, balanceSummary.averageDeviationFromCenter)
                    )
                )
                rows.append(
                    .init(
                        title: "L/R Balance (Finish)",
                        value: String(format: "L%.1f%% / R%.1f%%", balanceSummary.endLeftPercent, balanceSummary.endRightPercent),
                        hint: "骑行结束阶段左右脚占比",
                        method: "计算: Finish(L/R) = 最后一个有效平衡采样",
                        inputs: String(format: "参数: End 偏移=|L-50|=%.1f%%", balanceSummary.endDeviationFromCenter)
                    )
                )
                rows.append(
                    .init(
                        title: "L/R Verdict",
                        value: balanceSummary.verdict.label,
                        hint: "左右平衡判定",
                        method: "计算: max(|AvgL-50|, |EndL-50|) 分档",
                        inputs: String(
                            format: "参数: Avg 偏移=%.1f%%, End 偏移=%.1f%%, 阈值(平衡<=%.1f, 轻偏<=%.1f)",
                            balanceSummary.averageDeviationFromCenter,
                            balanceSummary.endDeviationFromCenter,
                            ActivityBalanceAnalyzer.balancedDeviationThreshold,
                            ActivityBalanceAnalyzer.mildDeviationThreshold
                        )
                    )
                )
            } else {
                rows.append(
                    .init(
                        title: "L/R Balance",
                        value: "N/A",
                        hint: "无左右脚平衡数据",
                        method: "计算: 需要 FIT/设备原始 L/R 采样",
                        inputs: "参数: 当前活动未发现 balanceLeft/balanceRight 字段"
                    )
                )
            }
        }

        return rows
    }


    private var stories: [ActivityStory] {
        derived.stories
    }

    private func buildStories(
        decouplingSummary: ActivityDecouplingSummary?,
        balanceSummary: ActivityBalanceSummary?
    ) -> [ActivityStory] {
        var rows: [ActivityStory] = []

        if let intensityFactor {
            if intensityFactor >= 0.95 {
                rows.append(.init(title: "强度故事", body: String(format: "IF %.2f，接近或超过阈值课强度。建议后续 24-48h 关注恢复与睡眠。", intensityFactor), tone: .warning))
            } else if intensityFactor >= 0.80 {
                rows.append(.init(title: "强度故事", body: String(format: "IF %.2f，属于中高强度耐力刺激，适合提高有氧与阈值能力。", intensityFactor), tone: .positive))
            } else {
                rows.append(.init(title: "强度故事", body: String(format: "IF %.2f，偏低强度，适合打底与恢复窗口。", intensityFactor), tone: .neutral))
            }
        }

        if tssPerHour >= 90 {
            rows.append(.init(title: "负荷密度故事", body: String(format: "TSS/h %.0f，单位时间负荷较高。若连续出现，建议在下一天安排低压训练。", tssPerHour), tone: .warning))
        } else if tssPerHour >= 60 {
            rows.append(.init(title: "负荷密度故事", body: String(format: "TSS/h %.0f，属于有效训练密度。可继续在周内安排1-2次同级别课表。", tssPerHour), tone: .positive))
        } else {
            rows.append(.init(title: "负荷密度故事", body: String(format: "TSS/h %.0f，训练刺激温和。适合恢复日或基础容量日。", tssPerHour), tone: .neutral))
        }

        if let hr = activity.avgHeartRate, activityThresholdHR > 0 {
            let ratio = Double(hr) / Double(activityThresholdHR)
            if ratio >= 0.92 {
                rows.append(.init(title: "心肺压力故事", body: String(format: "平均心率 %d bpm（约 LTHR 的 %.0f%%），心血管压力较高。建议近期关注 HRV 和主观疲劳。", hr, ratio * 100), tone: .warning))
            } else if ratio >= 0.82 {
                rows.append(.init(title: "心肺压力故事", body: String(format: "平均心率 %d bpm（约 LTHR 的 %.0f%%），刺激有效且可控。", hr, ratio * 100), tone: .positive))
            } else {
                rows.append(.init(title: "心肺压力故事", body: String(format: "平均心率 %d bpm（约 LTHR 的 %.0f%%），处于低压区间，偏恢复或耐力打底。", hr, ratio * 100), tone: .neutral))
            }
        }

        if let dayLoadPoint {
            if dayLoadPoint.tsb < -20 {
                rows.append(.init(title: "恢复建议", body: String(format: "当天 TSB %.1f，疲劳高位。下一课建议降强度或转恢复骑。", dayLoadPoint.tsb), tone: .warning))
            } else if dayLoadPoint.tsb > 10 {
                rows.append(.init(title: "恢复建议", body: String(format: "当天 TSB %.1f，身体较新鲜。可计划下一次质量课。", dayLoadPoint.tsb), tone: .positive))
            } else {
                rows.append(.init(title: "恢复建议", body: String(format: "当天 TSB %.1f，处于可训练区间。保持当前节奏即可。", dayLoadPoint.tsb), tone: .neutral))
            }
        }

        if let decoupling = decouplingSummary {
            if decoupling.ratePct >= 5 {
                rows.append(.init(title: "解耦率故事", body: String(format: "解耦率 %.1f%%，后半程心率漂移明显。建议补给更早、降低前半段冲动配速。", decoupling.ratePct), tone: .warning))
            } else if decoupling.ratePct >= 2 {
                rows.append(.init(title: "解耦率故事", body: String(format: "解耦率 %.1f%%，有轻微漂移。可通过稳定输出和有氧容量训练进一步优化。", decoupling.ratePct), tone: .neutral))
            } else {
                rows.append(.init(title: "解耦率故事", body: String(format: "解耦率 %.1f%%，前后半程耦合稳定，耐力控制较好。", decoupling.ratePct), tone: .positive))
            }
        }

        if activity.sport == .cycling, let balanceSummary {
            let body = String(
                format: "全程均值 L%.1f/R%.1f，结束 L%.1f/R%.1f，判定：%@。",
                balanceSummary.averageLeftPercent,
                balanceSummary.averageRightPercent,
                balanceSummary.endLeftPercent,
                balanceSummary.endRightPercent,
                balanceSummary.verdict.label
            )
            switch balanceSummary.verdict {
            case .balanced:
                rows.append(.init(title: "左右脚平衡故事", body: body, tone: .positive))
            case .mildImbalance:
                rows.append(.init(title: "左右脚平衡故事", body: body + " 建议继续观察疲劳阶段是否持续向一侧偏移。", tone: .neutral))
            case .imbalanced:
                rows.append(.init(title: "左右脚平衡故事", body: body + " 建议检查锁片/坐垫设定与单腿肌力差。", tone: .warning))
            }
        }

        if rows.isEmpty {
            rows.append(.init(title: "数据提示", body: "这次活动的数据字段较少。导入包含功率/心率的 FIT 文件后可生成更完整故事。", tone: .neutral))
        }
        return rows
    }

    private var cachedGPTInsight: ActivityMetricInsight? {
        store.activityMetricInsight(for: activity.id)
    }

    private var isRefreshingGPTInsight: Bool {
        store.isRefreshingActivityMetricInsight(for: activity.id)
    }

    private func preloadSensorSamplesIfNeeded() async {
        guard !hasLoadedSensorSamples else { return }
        let snapshot = activity
        let samples: [ActivitySensorSample] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ActivitySourceDataDecoder.samples(for: snapshot))
            }
        }
        preloadedSensorSamples = samples
        hasLoadedSensorSamples = true
    }

    private func buildDerived(sensorSamples: [ActivitySensorSample]) -> ActivityDetailDerived {
        let powerPoints = computePowerTracePoints(from: sensorSamples)
        let heartRatePoints = computeHeartRateTracePoints(from: sensorSamples)

        let powerAverage: Double?
        if !powerPoints.isEmpty {
            powerAverage = powerPoints.map(\.value).reduce(0, +) / Double(powerPoints.count)
        } else {
            powerAverage = activity.normalizedPower.map(Double.init)
        }

        let heartRateAverage: Double?
        if !heartRatePoints.isEmpty {
            heartRateAverage = heartRatePoints.map(\.value).reduce(0, +) / Double(heartRatePoints.count)
        } else {
            heartRateAverage = activity.avgHeartRate.map(Double.init)
        }

        let decouplingSamples = pairedPowerHeartRateSamples(
            maxSamples: 30,
            sensorSamples: sensorSamples,
            powerPoints: powerPoints,
            heartRatePoints: heartRatePoints
        )
        let decouplingTrace = decouplingSamples.enumerated().map { index, sample in
            ActivityTracePoint(id: index, minute: sample.minute, value: sample.power / sample.hr)
        }
        let decoupling = computeDecouplingSummary(from: decouplingSamples)
        let balance = ActivityBalanceAnalyzer.summary(from: sensorSamples)

        let hrPw = computeHrPwDerived(
            sensorSamples: sensorSamples,
            powerPoints: powerPoints,
            heartRatePoints: heartRatePoints
        )

        let metricRows = buildMetrics(decouplingSummary: decoupling, balanceSummary: balance)
        let storyRows = buildStories(decouplingSummary: decoupling, balanceSummary: balance)

        return ActivityDetailDerived(
            powerTracePoints: powerPoints,
            heartRateTracePoints: heartRatePoints,
            powerAverageValue: powerAverage,
            heartRateAverageValue: heartRateAverage,
            decouplingTracePoints: decouplingTrace,
            decouplingSummary: decoupling,
            balanceSummary: balance,
            hrPwScatterPoints: hrPw.scatter,
            hrPwRenderableScatterPoints: hrPw.renderable,
            hrPwDelaySec: hrPw.delaySec,
            hrPwAveragePower: hrPw.averagePower,
            hrPwAverageHR: hrPw.averageHR,
            hrPwRegression: hrPw.regression,
            hrPwRegressionVisiblePoints: hrPw.regressionPoints,
            hrPwPowerAtThreshold: hrPw.powerAtThreshold,
            hrPwYDomain: hrPw.yDomain,
            metrics: metricRows,
            stories: storyRows
        )
    }

    private func recomputeDerivedCaches() {
        derivedComputationGeneration &+= 1
        let generation = derivedComputationGeneration
        let snapshot = preloadedSensorSamples
        isComputingDerived = true

        DispatchQueue.global(qos: .userInitiated).async {
            let computed = self.buildDerived(sensorSamples: snapshot)
            DispatchQueue.main.async {
                guard generation == self.derivedComputationGeneration else { return }
                self.derived = computed
                self.isComputingDerived = false
            }
        }
    }

    private func computeDecouplingSummary(from paired: [ActivityPowerHeartSample]) -> ActivityDecouplingSummary? {
        guard activity.durationSec >= 20 * 60 else { return nil }
        guard paired.count >= 8 else { return nil }

        let firstHalf = Array(paired.prefix(paired.count / 2))
        let secondHalf = Array(paired.suffix(paired.count - paired.count / 2))
        guard firstHalf.count >= 3, secondHalf.count >= 3 else { return nil }

        let efFirst = firstHalf.map { $0.power / $0.hr }.reduce(0, +) / Double(firstHalf.count)
        let efSecond = secondHalf.map { $0.power / $0.hr }.reduce(0, +) / Double(secondHalf.count)
        guard efFirst > 0 else { return nil }

        let decouplingPct = (efFirst - efSecond) / efFirst * 100.0
        return ActivityDecouplingSummary(
            ratePct: decouplingPct,
            efFirst: efFirst,
            efSecond: efSecond,
            sampleCount: paired.count,
            splitMinute: secondHalf.first?.minute
        )
    }

    private func computeHrPwDerived(
        sensorSamples: [ActivitySensorSample],
        powerPoints: [ActivityTracePoint],
        heartRatePoints: [ActivityTracePoint]
    ) -> (
        scatter: [ActivityHrPwScatterPoint],
        renderable: [ActivityHrPwScatterPoint],
        delaySec: Int,
        averagePower: Double,
        averageHR: Double,
        regression: ActivityHrPwRegression?,
        regressionPoints: [ActivityTracePoint],
        powerAtThreshold: Double?,
        yDomain: ClosedRange<Double>
    ) {
        let rawSamples = pairedPowerHeartRateSamples(
            maxSamples: max(240, min(activity.durationSec, 12_000)),
            sensorSamples: sensorSamples,
            powerPoints: powerPoints,
            heartRatePoints: heartRatePoints
        )
        let smoothedSamples = gcSmoothAndClip(
            samples: rawSamples,
            smoothSec: 240,
            minHr: 50,
            minPower: 50,
            maxPower: 500
        )
        let decimated = gcDecimate(samples: smoothedSamples, targetStepSec: 10)
        let denominator = max(1.0, Double(max(0, decimated.count - 1)))
        let scatter = decimated.enumerated().map { index, sample in
            let segment = min(35, Int((Double(index) / denominator) * 35.0))
            return ActivityHrPwScatterPoint(
                id: index,
                minute: sample.minute,
                power: sample.power,
                hr: sample.hr,
                segment: segment
            )
        }

        let quantized = scatter.map { point in
            "\(Int((point.power * 2).rounded()))|\(Int((point.hr * 2).rounded()))"
        }
        let distinctPairCount = Set(quantized).count
        let powerRange = (scatter.map(\.power).max() ?? 0) - (scatter.map(\.power).min() ?? 0)
        let hrRange = (scatter.map(\.hr).max() ?? 0) - (scatter.map(\.hr).min() ?? 0)
        let renderable = (scatter.count >= 8 && (distinctPairCount >= 3 || powerRange >= 8 || hrRange >= 4))
            ? scatter
            : []

        let delay = gcBestDelay(samples: smoothedSamples, minDelaySec: 10, maxDelaySec: 60)
        let averagePower = smoothedSamples.isEmpty ? 0 : smoothedSamples.map(\.power).reduce(0, +) / Double(smoothedSamples.count)
        let averageHR = smoothedSamples.isEmpty ? 0 : smoothedSamples.map(\.hr).reduce(0, +) / Double(smoothedSamples.count)

        let regression: ActivityHrPwRegression?
        if let delayed = delayedSeriesForRegression(samples: smoothedSamples, delaySec: delay), delayed.powers.count >= 3 {
            let xs = delayed.powers
            let ys = delayed.hearts
            let xMean = xs.reduce(0, +) / Double(xs.count)
            let yMean = ys.reduce(0, +) / Double(ys.count)

            var covXY = 0.0
            var varX = 0.0
            var varY = 0.0
            for idx in xs.indices {
                let dx = xs[idx] - xMean
                let dy = ys[idx] - yMean
                covXY += dx * dy
                varX += dx * dx
                varY += dy * dy
            }
            if varX > 1e-6, varY > 1e-6 {
                regression = ActivityHrPwRegression(
                    slope: covXY / varX,
                    intercept: yMean - (covXY / varX) * xMean,
                    correlation: covXY / sqrt(varX * varY)
                )
            } else {
                regression = nil
            }
        } else {
            regression = nil
        }

        let regressionPoints: [ActivityTracePoint]
        if let regression {
            regressionPoints = [
                ActivityTracePoint(id: 9_001, minute: hrPwXDomain.lowerBound, value: regression.predicted(at: hrPwXDomain.lowerBound)),
                ActivityTracePoint(id: 9_002, minute: hrPwXDomain.upperBound, value: regression.predicted(at: hrPwXDomain.upperBound))
            ]
        } else {
            regressionPoints = []
        }

        let powerAtThreshold: Double?
        if let regression, abs(regression.slope) > 1e-6 {
            let value = (150.0 - regression.intercept) / regression.slope
            powerAtThreshold = (value.isFinite && value > 0) ? value : nil
        } else {
            powerAtThreshold = nil
        }

        let maxHR = smoothedSamples.map(\.hr).max() ?? max(120.0, Double(activityThresholdHR))
        let yUpper = ceil(max(70.0, maxHR * 1.2) / 5.0) * 5.0
        let yDomain = 50.0...yUpper

        return (scatter, renderable, delay, averagePower, averageHR, regression, regressionPoints, powerAtThreshold, yDomain)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activity.sport.label)
                            .font(.largeTitle.bold())
                        Text(activity.date.formatted(date: .complete, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteActivityConfirm = true
                    } label: {
                        Label(
                            L10n.choose(simplifiedChinese: "删除活动", english: "Delete Activity"),
                            systemImage: "trash"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                if !activity.notes.isEmpty {
                    Text(activity.notes)
                        .font(.headline)
                }

                if isComputingDerived {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.choose(simplifiedChinese: "正在并行计算活动指标…", english: "Computing activity metrics in parallel..."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox(L10n.choose(simplifiedChinese: "推送到平台", english: "Push to Platforms")) {
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ActivityPlatformPushButton(
                                title: L10n.choose(simplifiedChinese: "推送 Intervals", english: "Push Intervals"),
                                isPrimary: true,
                                isDisabled: store.isSyncing
                            ) {
                                Task { await store.syncPushActivityToIntervals(activityID: activity.id) }
                            }

                            ActivityPlatformPushButton(
                                title: L10n.choose(simplifiedChinese: "推送 Strava", english: "Push Strava"),
                                isPrimary: false,
                                isDisabled: store.isSyncing
                            ) {
                                Task { await store.syncPushActivityToStrava(activityID: activity.id) }
                            }

                            ActivityPlatformPushButton(
                                title: L10n.choose(simplifiedChinese: "推送 Garmin", english: "Push Garmin"),
                                isPrimary: false,
                                isDisabled: store.isSyncing
                            ) {
                                Task { await store.syncPushActivityToGarminConnect(activityID: activity.id) }
                            }

                            ActivityPlatformPushButton(
                                title: L10n.choose(simplifiedChinese: "一键推送全部", english: "Push All"),
                                isPrimary: false,
                                isDisabled: store.isSyncing
                            ) {
                                Task { await store.syncPushActivityToConnectedPlatforms(activityID: activity.id) }
                            }
                        }

                        if store.isSyncing {
                            ProgressView(L10n.choose(simplifiedChinese: "正在推送...", english: "Pushing..."))
                        }
                        if let status = store.syncStatus, !status.isEmpty {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let error = store.lastError, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("关键指标")
                    .font(.title3.bold())

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 170)),
                        GridItem(.flexible(minimum: 170)),
                        GridItem(.flexible(minimum: 170)),
                        GridItem(.flexible(minimum: 170))
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(metrics) { metric in
                        ActivityMetricCard(metric: metric)
                    }
                }

                Text("活动小图")
                    .font(.title3.bold())

                HStack(alignment: .top, spacing: 12) {
                    ActivityMiniSeriesCard(
                        title: "Power",
                        unitLabel: "W",
                        color: .orange,
                        points: powerTracePoints,
                        average: powerAverageValue,
                        sourceText: powerTraceSourceText
                    )
                    .frame(maxWidth: .infinity)

                    ActivityMiniSeriesCard(
                        title: "Heart Rate",
                        unitLabel: "bpm",
                        color: .red,
                        points: heartRateTracePoints,
                        average: heartRateAverageValue,
                        sourceText: heartRateSourceText
                    )
                    .frame(maxWidth: .infinity)
                }

                Text("分布图")
                    .font(.title3.bold())

                HStack(alignment: .top, spacing: 12) {
                    ActivityDistributionCard(
                        title: "Power Distribution",
                        unitLabel: "W",
                        color: .orange,
                        bins: powerDistributionBins
                    )
                    .frame(maxWidth: .infinity)

                    ActivityDistributionCard(
                        title: "Heart Rate Distribution",
                        unitLabel: "bpm",
                        color: .red,
                        bins: heartRateDistributionBins
                    )
                    .frame(maxWidth: .infinity)
                }

                GroupBox("HrPw (Heart Rate × Power)") {
                    VStack(alignment: .leading, spacing: 10) {
                        if hrPwRenderableScatterPoints.count < 8 {
                            Text(
                                hrPwScatterPoints.count >= 8
                                    ? "HrPw 样本离散度不足（当前多为概要均值/常量），请导入包含原始功率+心率曲线的 FIT 文件。"
                                    : "HrPw 图需要足够的功率+心率样本（建议导入含传感器曲线的 FIT 文件）。"
                            )
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if chartDisplayMode == .pie {
                            Chart(hrPwRenderableScatterPoints.suffix(60)) { point in
                                SectorMark(
                                    angle: .value("HeartRate", max(0, point.hr)),
                                    innerRadius: .ratio(0.56),
                                    angularInset: 1
                                )
                                .foregroundStyle(hrPwTimeColor(for: point.segment))
                            }
                        } else {
                            Chart {
                                ForEach(hrPwZoneBands) { band in
                                    RectangleMark(
                                        xStart: .value("PowerStart", band.lowerPower),
                                        xEnd: .value("PowerEnd", band.upperPower),
                                        yStart: .value("HRMin", hrPwYDomain.lowerBound),
                                        yEnd: .value("HRMax", hrPwYDomain.upperBound)
                                    )
                                    .foregroundStyle(band.color.opacity(0.18))
                                    .annotation(position: .overlay, alignment: .center) {
                                        Text(band.label)
                                            .font(.caption2.bold())
                                            .foregroundStyle(band.color.opacity(0.95))
                                    }
                                }

                                RuleMark(y: .value("AvgHR", hrPwAverageHR))
                                    .foregroundStyle(.secondary.opacity(0.45))
                                    .lineStyle(.init(lineWidth: 1, dash: [3, 3]))

                                RuleMark(x: .value("AvgPower", hrPwAveragePower))
                                    .foregroundStyle(.secondary.opacity(0.45))
                                    .lineStyle(.init(lineWidth: 1, dash: [3, 3]))

                                ForEach(hrPwRenderableScatterPoints) { point in
                                    switch chartDisplayMode {
                                    case .line:
                                        PointMark(
                                            x: .value("Power", point.power),
                                            y: .value("HeartRate", point.hr)
                                        )
                                        .symbolSize(18)
                                        .foregroundStyle(hrPwTimeColor(for: point.segment))
                                    case .bar:
                                        BarMark(
                                            x: .value("Power", point.power),
                                            y: .value("HeartRate", point.hr)
                                        )
                                        .foregroundStyle(hrPwTimeColor(for: point.segment).opacity(0.8))
                                    case .pie:
                                        BarMark(
                                            x: .value("Power", point.power),
                                            y: .value("HeartRate", point.hr)
                                        )
                                        .foregroundStyle(hrPwTimeColor(for: point.segment).opacity(0.8))
                                    case .flame:
                                        BarMark(
                                            x: .value("Power", point.power),
                                            y: .value("HeartRate", point.hr)
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

                                if chartDisplayMode == .line, !hrPwRegressionVisiblePoints.isEmpty {
                                    ForEach(hrPwRegressionVisiblePoints) { point in
                                        LineMark(
                                            x: .value("Power", point.minute),
                                            y: .value("Regression", point.value)
                                        )
                                        .interpolationMethod(.linear)
                                        .foregroundStyle(.blue.opacity(0.9))
                                        .lineStyle(.init(lineWidth: 2))
                                    }
                                }
                            }
                            .chartXScale(domain: hrPwXDomain)
                            .chartYScale(domain: hrPwYDomain)
                            .chartPlotStyle { plot in
                                plot.clipped()
                            }
                            .chartXAxisLabel("Power (Watts)")
                            .chartYAxisLabel("Heart Rate (BPM)")
                            .frame(height: 290)
                            .cartesianHoverTip(
                                xTitle: L10n.choose(simplifiedChinese: "功率(W)", english: "Power (W)"),
                                yTitle: L10n.choose(simplifiedChinese: "心率(bpm)", english: "Heart Rate (bpm)")
                            )

                            if let regression = hrPwRegression {
                                Text(
                                    String(
                                        format: "%.3f*x+%.1f : R %.3f (%d)",
                                        regression.slope,
                                        regression.intercept,
                                        regression.correlation,
                                        hrPwDelaySec
                                    )
                                )
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            }
                            if let powerAtTHR = hrPwPowerAtThreshold {
                                Text(
                                    String(
                                        format: "Power@150: %.0fW",
                                        powerAtTHR
                                    )
                                )
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            }

                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Decoupling (EF)") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let decoupling = decouplingSummary, !decouplingTracePoints.isEmpty {
                            HStack {
                                Text(String(format: "解耦率 %.1f%%", decoupling.ratePct))
                                    .font(.caption.bold())
                                Spacer()
                                Text(String(format: "EF前半 %.3f → 后半 %.3f", decoupling.efFirst, decoupling.efSecond))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Chart(decouplingTracePoints) { point in
                                switch chartDisplayMode {
                                case .line:
                                    LineMark(
                                        x: .value("Minute", point.minute),
                                        y: .value("EF", point.value)
                                    )
                                    .interpolationMethod(.linear)
                                    .foregroundStyle(.mint)
                                    .lineStyle(.init(lineWidth: 2))

                                    RuleMark(y: .value("EF First", decoupling.efFirst))
                                        .foregroundStyle(.mint.opacity(0.3))
                                        .lineStyle(.init(lineWidth: 1, dash: [4, 3]))

                                    RuleMark(y: .value("EF Second", decoupling.efSecond))
                                        .foregroundStyle(.blue.opacity(0.35))
                                        .lineStyle(.init(lineWidth: 1, dash: [4, 3]))

                                    if let splitMinute = decoupling.splitMinute {
                                        RuleMark(x: .value("Split", splitMinute))
                                            .foregroundStyle(.orange.opacity(0.75))
                                            .lineStyle(.init(lineWidth: 1.2, dash: [2, 2]))
                                    }
                                case .bar:
                                    BarMark(
                                        x: .value("Minute", point.minute),
                                        y: .value("EF", point.value)
                                    )
                                    .foregroundStyle(.mint.opacity(0.85))
                                case .pie:
                                    SectorMark(
                                        angle: .value("EF", max(0, point.value)),
                                        innerRadius: .ratio(0.56),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(.mint.opacity(0.8))
                                case .flame:
                                    BarMark(
                                        x: .value("Minute", point.minute),
                                        y: .value("EF", max(0, point.value))
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
                            .frame(height: 130)
                            .cartesianHoverTip(
                                xTitle: L10n.choose(simplifiedChinese: "时间(分)", english: "Time (min)"),
                                yTitle: "EF"
                            )

                            HStack(spacing: 12) {
                                ActivityLegendSwatch(
                                    color: .mint,
                                    style: .solid,
                                    label: L10n.choose(simplifiedChinese: "实线：EF 时间曲线", english: "Solid: EF time trace")
                                )
                                ActivityLegendSwatch(
                                    color: .mint.opacity(0.65),
                                    style: .dashed,
                                    label: L10n.choose(simplifiedChinese: "虚线：前半均值", english: "Dashed: first-half mean")
                                )
                                ActivityLegendSwatch(
                                    color: .blue.opacity(0.75),
                                    style: .dashed,
                                    label: L10n.choose(simplifiedChinese: "虚线：后半均值", english: "Dashed: second-half mean")
                                )
                                ActivityLegendSwatch(
                                    color: .orange.opacity(0.8),
                                    style: .dashed,
                                    label: L10n.choose(simplifiedChinese: "竖虚线：前后半分割点", english: "Vertical dashed: split point")
                                )
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("计算: 解耦率 = (EF前半 - EF后半) / EF前半 × 100，EF = 功率 / 心率")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("参数: 样本点 \(decoupling.sampleCount), 前后半程均值由同时间点功率/心率配对得到")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("解耦率需要 >=20min 且含功率+心率数据。")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("指标故事")
                    .font(.title3.bold())

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stories) { story in
                        ActivityStoryCard(story: story)
                    }
                }

                GroupBox("GPT Activity 解读（缓存）") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let insight = cachedGPTInsight {
                            Text(insight.summary)
                                .font(.subheadline)
                            if !insight.keyFindings.isEmpty {
                                Divider()
                                Text("关键发现")
                                    .font(.subheadline.bold())
                                ForEach(insight.keyFindings, id: \.self) { line in
                                    Text("• \(line)")
                                        .font(.caption)
                                }
                            }
                            if !insight.actions.isEmpty {
                                Divider()
                                Text("建议动作")
                                    .font(.subheadline.bold())
                                ForEach(insight.actions, id: \.self) { line in
                                    Text("• \(line)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("生成时间: \(insight.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if isRefreshingGPTInsight {
                            ProgressView("正在生成 GPT 解读...")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("尚未生成 GPT 解读。")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Spacer()
                            Button(isRefreshingGPTInsight ? "刷新中..." : "刷新 GPT 解读") {
                                Task { await store.refreshActivityMetricInsight(for: activity, force: true) }
                            }
                            .disabled(isRefreshingGPTInsight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !activity.intervals.isEmpty {
                    Text("区间明细")
                        .font(.title3.bold())

                    VStack(spacing: 6) {
                        ForEach(activity.intervals) { effort in
                            HStack {
                                Text(effort.name)
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(effort.durationSec.asDuration)
                                    .foregroundStyle(.secondary)
                                if let target = effort.targetPower {
                                    Text("Target \(target)W")
                                        .foregroundStyle(.secondary)
                                }
                                if let actual = effort.actualPower {
                                    Text("Actual \(actual)W")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
        .task(id: activity.id) {
            hasLoadedSensorSamples = false
            preloadedSensorSamples = []
            derivedComputationGeneration &+= 1
            isComputingDerived = false
            derived = .empty
            await preloadSensorSamplesIfNeeded()
            recomputeDerivedCaches()
            await store.ensureActivityMetricInsightCached(for: activity)
        }
        .confirmationDialog(
            L10n.choose(simplifiedChinese: "删除这个活动？", english: "Delete this activity?"),
            isPresented: $showDeleteActivityConfirm,
            titleVisibility: .visible
        ) {
            Button(
                L10n.choose(simplifiedChinese: "删除活动", english: "Delete Activity"),
                role: .destructive
            ) {
                store.deleteActivities(ids: [activity.id])
                dismiss()
            }
            Button(L10n.choose(simplifiedChinese: "取消", english: "Cancel"), role: .cancel) {}
        } message: {
            Text(
                L10n.choose(
                    simplifiedChinese: "将从本地存储永久删除该活动，并清理相关缓存解读。此操作不可撤销。",
                    english: "This permanently removes the activity from local storage and clears related cached insights. This action cannot be undone."
                )
            )
        }
    }
}

private struct ActivityDetailDerived {
    let powerTracePoints: [ActivityTracePoint]
    let heartRateTracePoints: [ActivityTracePoint]
    let powerAverageValue: Double?
    let heartRateAverageValue: Double?
    let decouplingTracePoints: [ActivityTracePoint]
    let decouplingSummary: ActivityDecouplingSummary?
    let balanceSummary: ActivityBalanceSummary?
    let hrPwScatterPoints: [ActivityHrPwScatterPoint]
    let hrPwRenderableScatterPoints: [ActivityHrPwScatterPoint]
    let hrPwDelaySec: Int
    let hrPwAveragePower: Double
    let hrPwAverageHR: Double
    let hrPwRegression: ActivityHrPwRegression?
    let hrPwRegressionVisiblePoints: [ActivityTracePoint]
    let hrPwPowerAtThreshold: Double?
    let hrPwYDomain: ClosedRange<Double>
    let metrics: [ActivityMetricCardModel]
    let stories: [ActivityStory]

    static let empty = ActivityDetailDerived(
        powerTracePoints: [],
        heartRateTracePoints: [],
        powerAverageValue: nil,
        heartRateAverageValue: nil,
        decouplingTracePoints: [],
        decouplingSummary: nil,
        balanceSummary: nil,
        hrPwScatterPoints: [],
        hrPwRenderableScatterPoints: [],
        hrPwDelaySec: 0,
        hrPwAveragePower: 0,
        hrPwAverageHR: 0,
        hrPwRegression: nil,
        hrPwRegressionVisiblePoints: [],
        hrPwPowerAtThreshold: nil,
        hrPwYDomain: 50...150,
        metrics: [],
        stories: []
    )
}

private struct ActivityMetricCardModel: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let hint: String
    let method: String
    let inputs: String
}

private struct ActivityMetricCard: View {
    let metric: ActivityMetricCardModel

    private var tint: Color {
        let key = metric.title.lowercased()
        if key.contains("tsb") { return .mint }
        if key.contains("atl") { return .orange }
        if key.contains("ctl") { return .blue }
        if key.contains("tss") { return .blue }
        if key.contains("hr") || key.contains("heart") { return .red }
        if key.contains("power") || key.contains("ftp") { return .orange }
        if key.contains("sleep") { return .indigo }
        if key.contains("hrv") { return .cyan }
        if key.contains("decoupling") || key.contains("解耦") { return .teal }
        return .gray
    }

    private var emphasis: Double {
        guard let number = firstNumericValue(from: metric.value) else { return 0.45 }
        let key = metric.title.lowercased()
        if key.contains("tsb") { return min(max(abs(number) / 30.0, 0.0), 1.0) }
        if key.contains("atl") || key.contains("ctl") { return min(max(number / 120.0, 0.0), 1.0) }
        if key.contains("tss") { return min(max(number / 250.0, 0.0), 1.0) }
        if key.contains("hr") || key.contains("heart") { return min(max(number / 190.0, 0.0), 1.0) }
        if key.contains("power") || key.contains("ftp") { return min(max(number / 400.0, 0.0), 1.0) }
        if key.contains("sleep") { return min(max(number / 8.0, 0.0), 1.0) }
        if key.contains("hrv") { return min(max(number / 120.0, 0.0), 1.0) }
        if key.contains("decoupling") || key.contains("解耦") { return min(max(abs(number) / 12.0, 0.0), 1.0) }
        return min(max(number / 100.0, 0.0), 1.0)
    }

    private func firstNumericValue(from text: String) -> Double? {
        let pattern = "-?\\d+(?:\\.\\d+)?"
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: text,
                options: [],
                range: NSRange(location: 0, length: text.utf16.count)
            ),
            let range = Range(match.range, in: text)
        else {
            return nil
        }
        return Double(text[range])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(.title3.bold().monospacedDigit())
            Text(metric.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(metric.method)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(metric.inputs)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ActivityStory: Identifiable {
    enum Tone {
        case positive
        case neutral
        case warning
    }

    let id = UUID()
    let title: String
    let body: String
    let tone: Tone
}

private struct ActivityStoryCard: View {
    let story: ActivityStory

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

private struct ActivityLegendSwatch: View {
    enum Style {
        case solid
        case dashed
    }

    let color: Color
    let style: Style
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if style == .solid {
                    Capsule()
                        .fill(color)
                } else {
                    DashedLegendLine()
                        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .frame(width: 20, height: 6)

            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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

private struct ActivityTracePoint: Identifiable {
    let id: Int
    let minute: Double
    let value: Double
}

private struct ActivityPowerHeartSample {
    let minute: Double
    let power: Double
    let hr: Double
}

private struct ActivityDecouplingSummary {
    let ratePct: Double
    let efFirst: Double
    let efSecond: Double
    let sampleCount: Int
    let splitMinute: Double?
}

private struct ActivityHrPwScatterPoint: Identifiable {
    let id: Int
    let minute: Double
    let power: Double
    let hr: Double
    let segment: Int
}

private struct ActivityPowerZoneBand: Identifiable {
    let id: Int
    let label: String
    let lowerPower: Double
    let upperPower: Double
    let color: Color
}

private struct ActivityDistributionBin: Identifiable {
    let id: Int
    let rangeLabel: String
    let valueMidpoint: Double
    let sampleCount: Int
    let fraction: Double
}

private struct ActivityHrPwRegression {
    let slope: Double
    let intercept: Double
    let correlation: Double

    func predicted(at power: Double) -> Double {
        slope * power + intercept
    }
}

private struct ActivityDistributionCard: View {
    let title: String
    let unitLabel: String
    let color: Color
    let bins: [ActivityDistributionBin]

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                if bins.isEmpty {
                    Text("No \(title.lowercased()) data")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Chart(bins) { bin in
                        BarMark(
                            x: .value("Range", bin.rangeLabel),
                            y: .value("Samples", bin.sampleCount)
                        )
                        .foregroundStyle(color.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4))
                    }
                    .frame(height: 120)

                    HStack {
                        Text("Peak: \(Int((bins.max(by: { $0.sampleCount < $1.sampleCount })?.valueMidpoint ?? 0).rounded())) \(unitLabel)")
                        Spacer()
                        Text("Bins: \(bins.count)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ActivityMiniSeriesCard: View {
    @Environment(\.appChartDisplayMode) private var chartDisplayMode
    let title: String
    let unitLabel: String
    let color: Color
    let points: [ActivityTracePoint]
    let average: Double?
    let sourceText: String

    private var smoothedPoints: [ActivityTracePoint] {
        guard points.count >= 2 else { return points }
        let sorted = points.sorted { $0.minute < $1.minute }
        let spanSec = max(1.0, (sorted.last?.minute ?? 0 - (sorted.first?.minute ?? 0)) * 60.0)
        let stepSec = spanSec / Double(max(sorted.count - 1, 1))
        let window = max(1, Int(round(30.0 / stepSec))) // GC SmallPlot default ~30s smoothing

        var out = sorted
        var rolling = 0.0
        for idx in sorted.indices {
            rolling += sorted[idx].value
            if idx >= window {
                rolling -= sorted[idx - window].value
            }
            let n = min(idx + 1, window)
            out[idx] = ActivityTracePoint(id: sorted[idx].id, minute: sorted[idx].minute, value: rolling / Double(n))
        }
        return out
    }

    private var yDomain: ClosedRange<Double> {
        let rows = smoothedPoints
        guard !rows.isEmpty else { return 0...1 }
        let minV = rows.map(\.value).min() ?? 0
        let maxV = rows.map(\.value).max() ?? 1
        let span = max(1.0, maxV - minV)
        let pad = max(1.0, span * 0.14)
        let lower = max(0.0, minV - pad)
        let upper = max(lower + 2.0, maxV + pad)
        return lower...upper
    }

    private var latestText: String {
        guard let latest = smoothedPoints.last?.value else { return "--" }
        return "\(Int(latest.rounded())) \(unitLabel)"
    }

    private var averageText: String {
        if let average {
            return "\(Int(average.rounded())) \(unitLabel)"
        }
        guard !smoothedPoints.isEmpty else { return "--" }
        let value = smoothedPoints.map(\.value).reduce(0, +) / Double(smoothedPoints.count)
        return "\(Int(value.rounded())) \(unitLabel)"
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Latest \(latestText)", systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("Avg \(averageText)", systemImage: "minus.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if smoothedPoints.isEmpty {
                    Text("No \(title.lowercased()) data")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Chart(smoothedPoints) { point in
                        switch chartDisplayMode {
                        case .line:
                            LineMark(
                                x: .value("Minute", point.minute),
                                y: .value("Value", point.value)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(color)
                            .lineStyle(.init(lineWidth: 2))
                        case .bar:
                            BarMark(
                                x: .value("Minute", point.minute),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(color.opacity(0.85))
                        case .pie:
                            SectorMark(
                                angle: .value("Value", max(0, point.value)),
                                innerRadius: .ratio(0.56),
                                angularInset: 1
                            )
                            .foregroundStyle(color.opacity(0.8))
                        case .flame:
                            BarMark(
                                x: .value("Minute", point.minute),
                                y: .value("Value", max(0, point.value))
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
                    .chartYScale(domain: yDomain)
                    .chartPlotStyle { plot in
                        plot.clipped()
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 96)
                    .cartesianHoverTip(
                        xTitle: L10n.choose(simplifiedChinese: "时间(分)", english: "Time (min)"),
                        yTitle: unitLabel
                    )
                }

                Text(sourceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension Double {
    var mmss: String {
        guard self.isFinite, self > 0 else { return "--" }
        let totalSeconds = Int((self * 60).rounded())
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
    Swift.max(lower, Swift.min(upper, value))
}
