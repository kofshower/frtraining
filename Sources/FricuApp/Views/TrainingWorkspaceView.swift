import SwiftUI

private enum TrainingWorkspaceTab: String, CaseIterable, Identifiable {
    case overview
    case plans
    case workouts
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return L10n.choose(simplifiedChinese: "总览", english: "Overview")
        case .plans:
            return L10n.choose(simplifiedChinese: "周期计划", english: "Plans")
        case .workouts:
            return L10n.choose(simplifiedChinese: "Workout 工坊", english: "Workouts")
        case .advanced:
            return L10n.choose(simplifiedChinese: "高级分析", english: "Advanced")
        }
    }

    var summary: String {
        switch self {
        case .overview:
            return L10n.choose(
                simplifiedChinese: "先看训练节奏、近期安排和执行状态，再决定是去排周期还是写单节课。",
                english: "Start with training rhythm, upcoming sessions, and adherence before diving deeper."
            )
        case .plans:
            return L10n.choose(
                simplifiedChinese: "围绕训练周期、模板复用和赛事目标来编排长期计划。",
                english: "Build longer plans around blocks, templates, and event targets."
            )
        case .workouts:
            return L10n.choose(
                simplifiedChinese: "快速创建、编辑并加入单次 workout，随时塞进训练日历。",
                english: "Create and schedule individual workouts quickly."
            )
        case .advanced:
            return L10n.choose(
                simplifiedChinese: "间歇实验室、功率建模和活动取证等进阶能力都还在这里。",
                english: "Interval lab, power modeling, and other advanced tools still live here."
            )
        }
    }
}

struct TrainingWorkspaceView: View {
    @State private var selectedTab: TrainingWorkspaceTab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.choose(simplifiedChinese: "训练规划", english: "Training"))
                    .font(.largeTitle.bold())

                Text(verbatim: selectedTab.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker(L10n.choose(simplifiedChinese: "训练工作区", english: "Training Workspace"), selection: $selectedTab) {
                    ForEach(TrainingWorkspaceTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 6)

            Group {
                switch selectedTab {
                case .overview:
                    TrainingOverviewView(selectedTab: $selectedTab)
                case .plans:
                    ProSuiteView(
                        showsTitle: false,
                        availableModules: [.planner],
                        initialModule: .planner
                    )
                case .workouts:
                    WorkoutBuilderView(showsTitle: false)
                case .advanced:
                    ProSuiteView(
                        showsTitle: false,
                        availableModules: ProSuiteModule.advancedCases,
                        initialModule: .intervals
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TrainingOverviewSnapshot {
    let adherence: PlanAdherenceReport
    let scheduledWorkouts: [PlannedWorkout]
    let unscheduledWorkouts: [PlannedWorkout]
    let upcomingScheduledWorkouts: [PlannedWorkout]
    let totalPlannedMinutes: Int
    let thisWeekScheduledCount: Int
    let nextTwoWeeksMinutes: Int
    let nextWorkout: PlannedWorkout?
    let recentLibraryWorkouts: [PlannedWorkout]
    let totalActivities: Int
    let templateCount: Int

    init(
        workouts: [PlannedWorkout],
        activities: [Activity],
        profile: AthleteProfile,
        now: Date = Date(),
        calendar: Calendar = .current,
        templateCount: Int = WorkoutTemplateLibrary.templates.count
    ) {
        adherence = PlanAdherenceEngine.evaluate(
            workouts: workouts,
            activities: activities,
            profile: profile
        )

        scheduledWorkouts = workouts
            .filter { $0.scheduledDate != nil }
            .sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }

        unscheduledWorkouts = workouts
            .filter { $0.scheduledDate == nil }
            .sorted { $0.createdAt > $1.createdAt }

        let today = calendar.startOfDay(for: now)
        upcomingScheduledWorkouts = scheduledWorkouts.filter { workout in
            guard let scheduledDate = workout.scheduledDate else { return false }
            return calendar.startOfDay(for: scheduledDate) >= today
        }

        totalPlannedMinutes = workouts.reduce(0) { $0 + $1.totalMinutes }

        if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
            thisWeekScheduledCount = scheduledWorkouts.filter { workout in
                guard let scheduledDate = workout.scheduledDate else { return false }
                return interval.contains(scheduledDate)
            }.count
        } else {
            thisWeekScheduledCount = 0
        }

        if let cutoff = calendar.date(byAdding: .day, value: 14, to: today) {
            nextTwoWeeksMinutes = upcomingScheduledWorkouts
                .filter { workout in
                    guard let scheduledDate = workout.scheduledDate else { return false }
                    return scheduledDate < cutoff
                }
                .reduce(0) { $0 + $1.totalMinutes }
        } else {
            nextTwoWeeksMinutes = 0
        }

        nextWorkout = upcomingScheduledWorkouts.first
        recentLibraryWorkouts = workouts
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .map { $0 }
        totalActivities = activities.count
        self.templateCount = templateCount
    }
}

private struct TrainingOverviewView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedTab: TrainingWorkspaceTab

    private var snapshot: TrainingOverviewSnapshot {
        TrainingOverviewSnapshot(
            workouts: store.athleteScopedPlannedWorkouts,
            activities: store.athleteScopedActivities,
            profile: store.profile
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(
                            L10n.choose(
                                simplifiedChinese: "把长期周期、排课和单次 workout 放到同一个训练流程里。",
                                english: "Keep long blocks, scheduling, and single workouts in one flow."
                            )
                        )
                        .font(.headline)

                        Text(
                            L10n.choose(
                                simplifiedChinese: "先从总览判断当前训练节奏，再去周期计划里排块，或者去 Workout 工坊快速补一节课。",
                                english: "Read the room here first, then jump into plans or build a workout."
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button(L10n.choose(simplifiedChinese: "打开周期计划", english: "Open Plans")) {
                                selectedTab = .plans
                            }
                            .buttonStyle(.borderedProminent)

                            Button(L10n.choose(simplifiedChinese: "进入 Workout 工坊", english: "Open Workouts")) {
                                selectedTab = .workouts
                            }
                            .buttonStyle(.bordered)

                            Button(L10n.choose(simplifiedChinese: "查看高级分析", english: "Open Advanced")) {
                                selectedTab = .advanced
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    TrainingOverviewStatCard(
                        title: L10n.choose(simplifiedChinese: "计划课总数", english: "Planned Sessions"),
                        value: "\(store.athleteScopedPlannedWorkouts.count)",
                        detail: L10n.choose(simplifiedChinese: "总计划时长 \(snapshot.totalPlannedMinutes) 分钟", english: "Total \(snapshot.totalPlannedMinutes) min"),
                        tint: .blue
                    )
                    TrainingOverviewStatCard(
                        title: L10n.choose(simplifiedChinese: "本周已排课", english: "Scheduled This Week"),
                        value: "\(snapshot.thisWeekScheduledCount)",
                        detail: L10n.choose(simplifiedChinese: "未来 14 天 \(snapshot.nextTwoWeeksMinutes) 分钟", english: "Next 14 days \(snapshot.nextTwoWeeksMinutes) min"),
                        tint: .green
                    )
                    TrainingOverviewStatCard(
                        title: L10n.choose(simplifiedChinese: "42 天完成率", english: "42-Day Completion"),
                        value: "\(Int((snapshot.adherence.completionRate * 100).rounded()))%",
                        detail: L10n.choose(simplifiedChinese: "按计划率 \(Int((snapshot.adherence.onTimeRate * 100).rounded()))%", english: "On-time \(Int((snapshot.adherence.onTimeRate * 100).rounded()))%"),
                        tint: .orange
                    )
                    TrainingOverviewStatCard(
                        title: L10n.choose(simplifiedChinese: "待排期 Workout", english: "Unscheduled Workouts"),
                        value: "\(snapshot.unscheduledWorkouts.count)",
                        detail: L10n.choose(simplifiedChinese: "模板库 \(snapshot.templateCount) 个", english: "\(snapshot.templateCount) templates"),
                        tint: .purple
                    )
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], spacing: 12) {
                    TrainingPathCard(
                        title: L10n.choose(simplifiedChinese: "周期计划", english: "Block Planning"),
                        summary: L10n.choose(
                            simplifiedChinese: "适合按 4-16 周周期安排基础期、赛事专项和减量周。",
                            english: "Use this for 4-16 week blocks, race specificity, and tapering."
                        ),
                        highlights: [
                            L10n.choose(simplifiedChinese: "模板复用与批量铺课", english: "Template rollout and block reuse"),
                            L10n.choose(simplifiedChinese: "双阈值日和依从性跟踪", english: "Double-threshold days and adherence"),
                            L10n.choose(simplifiedChinese: "拖拽日历排课", english: "Drag-and-drop calendar scheduling")
                        ],
                        buttonTitle: L10n.choose(simplifiedChinese: "进入周期计划", english: "Open Plans"),
                        tint: .blue
                    ) {
                        selectedTab = .plans
                    }

                    TrainingPathCard(
                        title: L10n.choose(simplifiedChinese: "Workout 工坊", english: "Workout Workshop"),
                        summary: L10n.choose(
                            simplifiedChinese: "适合快速补一节阈值课、恢复骑或某个特定目标 workout。",
                            english: "Use this to add a threshold set, recovery ride, or any single workout fast."
                        ),
                        highlights: [
                            L10n.choose(simplifiedChinese: "分段编辑和即时排期", english: "Segment editing and instant scheduling"),
                            L10n.choose(simplifiedChinese: "按运动类型管理 workout 库", english: "Workout library by sport"),
                            L10n.choose(simplifiedChinese: "随时插入现有周期", english: "Insert into existing blocks anytime")
                        ],
                        buttonTitle: L10n.choose(simplifiedChinese: "进入 Workout 工坊", english: "Open Workouts"),
                        tint: .green
                    ) {
                        selectedTab = .workouts
                    }
                }

                GroupBox(L10n.choose(simplifiedChinese: "近期计划预览", english: "Upcoming Sessions")) {
                    if snapshot.upcomingScheduledWorkouts.isEmpty {
                        ContentUnavailableView(
                            L10n.choose(simplifiedChinese: "还没有排到日历里的训练", english: "No scheduled workouts yet"),
                            systemImage: "calendar.badge.exclamationmark"
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            if let nextWorkout = snapshot.nextWorkout {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.choose(simplifiedChinese: "最近的一节", english: "Next Up"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    UpcomingWorkoutRow(workout: nextWorkout, emphasis: true)
                                }

                                Divider()
                            }

                            ForEach(snapshot.upcomingScheduledWorkouts.prefix(6)) { workout in
                                UpcomingWorkoutRow(workout: workout, emphasis: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox(L10n.choose(simplifiedChinese: "训练资产与执行面", english: "Training Assets")) {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 12) {
                            TrainingAssetMetric(
                                title: L10n.choose(simplifiedChinese: "模板库", english: "Templates"),
                                value: "\(snapshot.templateCount)"
                            )
                            TrainingAssetMetric(
                                title: L10n.choose(simplifiedChinese: "双阈值日", english: "Double Threshold Days"),
                                value: "\(snapshot.adherence.norwegianDoubleThresholdDays)"
                            )
                            TrainingAssetMetric(
                                title: L10n.choose(simplifiedChinese: "风险日", english: "Risk Days"),
                                value: "\(snapshot.adherence.norwegianRiskDays)"
                            )
                            TrainingAssetMetric(
                                title: L10n.choose(simplifiedChinese: "已完成活动", english: "Completed Activities"),
                                value: "\(snapshot.totalActivities)"
                            )
                        }

                        if snapshot.recentLibraryWorkouts.isEmpty {
                            Text(L10n.choose(simplifiedChinese: "还没有保存过 workout。先去 Workout 工坊创建几节常用课吧。", english: "No saved workouts yet. Create a few staple sessions in the workshop."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.choose(simplifiedChinese: "最近加入训练库", english: "Recent Workout Library"))
                                    .font(.headline)

                                ForEach(snapshot.recentLibraryWorkouts) { workout in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(workout.name)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer(minLength: 8)
                                        Text("\(workout.sport.label) · \(workout.totalMinutes) min")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }
}

private struct TrainingOverviewStatCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold())
                .foregroundStyle(tint)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct TrainingPathCard: View {
    let title: String
    let summary: String
    let highlights: [String]
    let buttonTitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(highlights, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}

private struct UpcomingWorkoutRow: View {
    let workout: PlannedWorkout
    let emphasis: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.name)
                    .font(emphasis ? .headline : .subheadline.weight(.semibold))
                Text("\(workout.sport.label) · \(workout.totalMinutes) min · \(workout.segments.count) segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            if let scheduledDate = workout.scheduledDate {
                Text(
                    scheduledDate.formatted(
                        .dateTime
                            .month(.abbreviated)
                            .day()
                    )
                )
                .font(emphasis ? .subheadline.weight(.bold) : .caption.weight(.semibold))
                .foregroundStyle(emphasis ? Color.blue : .secondary)
            }
        }
        .padding(.vertical, emphasis ? 2 : 0)
    }
}

private struct TrainingAssetMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
    }
}
