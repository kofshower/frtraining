import SwiftUI

/// Shared bilingual copy token for the Fat-loss Assistant page.
struct FatLossAssistantBilingualCopy {
    /// Simplified Chinese text.
    let simplifiedChinese: String
    /// English text.
    let english: String

    /// Resolves copy for current app language.
    /// - Returns: Localized text chosen by ``L10n``.
    func localized() -> String {
        L10n.choose(simplifiedChinese: simplifiedChinese, english: english)
    }
}

/// Centralized copy catalog for the Fat-loss Assistant page.
enum FatLossAssistantCopy {
    static let pageTitle = FatLossAssistantBilingualCopy(simplifiedChinese: "减脂助手", english: "Fat-loss Assistant")
    static let subtitle = FatLossAssistantBilingualCopy(
        simplifiedChinese: "把计划、执行与复盘重构为决策树：每个节点对应一个执行卡片，按顺序推进。",
        english: "Reorganized into a decision tree: each node maps to one execution card and advances in order."
    )
    static let dailyChecklistTitle = FatLossAssistantBilingualCopy(simplifiedChinese: "今日执行清单", english: "Today's Execution Checklist")
    static let strategyTitle = FatLossAssistantBilingualCopy(simplifiedChinese: "策略卡", english: "Strategy Cards")
    static let reviewTitle = FatLossAssistantBilingualCopy(simplifiedChinese: "复盘规则", english: "Review Rules")
}

enum FatLossDecisionNode: String, CaseIterable, Identifiable {
    case profileGoal
    case planToday
    case executeLog
    case weeklyReview

    var id: String { rawValue }

    var stepNumber: Int {
        switch self {
        case .profileGoal: return 1
        case .planToday: return 2
        case .executeLog: return 3
        case .weeklyReview: return 4
        }
    }

    var title: String {
        switch self {
        case .profileGoal:
            return L10n.choose(simplifiedChinese: "建档与目标", english: "Profile and Goal")
        case .planToday:
            return L10n.choose(simplifiedChinese: "生成今日策略", english: "Plan Today")
        case .executeLog:
            return L10n.choose(simplifiedChinese: "执行与打卡", english: "Execute and Log")
        case .weeklyReview:
            return L10n.choose(simplifiedChinese: "7天复盘与调参", english: "7-day Review and Adjust")
        }
    }

    var detailCardTitle: String {
        switch self {
        case .profileGoal:
            return L10n.choose(simplifiedChinese: "节点 1 · 建档与目标", english: "Node 1 · Profile and Goal")
        case .planToday:
            return L10n.choose(simplifiedChinese: "节点 2 · 生成今日策略", english: "Node 2 · Plan Today")
        case .executeLog:
            return L10n.choose(simplifiedChinese: "节点 3 · 执行与打卡", english: "Node 3 · Execute and Log")
        case .weeklyReview:
            return L10n.choose(simplifiedChinese: "节点 4 · 7天复盘与调参", english: "Node 4 · 7-day Review and Adjust")
        }
    }

    var icon: String {
        switch self {
        case .profileGoal:
            return "person.text.rectangle"
        case .planToday:
            return "list.bullet.clipboard"
        case .executeLog:
            return "checkmark.seal"
        case .weeklyReview:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

private enum FatLossWorkflowState {
    case pending
    case running
    case blocked
    case ready
    case done

    var symbol: String {
        switch self {
        case .pending:
            return "circle"
        case .running:
            return "clock.arrow.circlepath"
        case .blocked:
            return "xmark.octagon.fill"
        case .ready:
            return "bolt.circle.fill"
        case .done:
            return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .running:
            return .blue
        case .blocked:
            return .orange
        case .ready:
            return .teal
        case .done:
            return .green
        }
    }
}

/// A dedicated page that summarizes the fat-loss workflow with actionable guidance.
struct FatLossAssistantPageView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedNode: FatLossDecisionNode = .profileGoal

    private var todayMealPlan: DailyMealPlan? {
        store.dailyMealPlanForSelectedAthlete(on: Date())
    }

    private var profileConfigured: Bool {
        let profile = store.profile
        return profile.athleteAgeYears > 0 && profile.athleteWeightKg > 0 && profile.basalMetabolicRateKcal > 0
    }

    private var todayExecutionRatio: Double {
        todayMealPlan?.completionRatio ?? 0
    }

    private var hydrationLogged: Bool {
        (todayMealPlan?.hydrationActualLiters ?? 0) > 0
    }

    private var executionLogged: Bool {
        todayExecutionRatio > 0.01 || hydrationLogged
    }

    private var recentMealPlanCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return store.mealPlansForAthlete(named: store.selectedAthleteNameForFilter)
            .filter { $0.date >= cutoff }
            .count
    }

    private var recentWellnessCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return store.wellnessSamplesForAthlete(named: store.selectedAthleteNameForFilter)
            .filter { $0.date >= cutoff }
            .count
    }

    private var profileStepState: FatLossWorkflowState {
        profileConfigured ? .done : .ready
    }

    private var planningStepState: FatLossWorkflowState {
        guard profileConfigured else { return .blocked }
        return todayMealPlan == nil ? .ready : .done
    }

    private var executionStepState: FatLossWorkflowState {
        guard todayMealPlan != nil else { return .pending }
        if todayExecutionRatio >= 0.85 || hydrationLogged {
            return .done
        }
        return executionLogged ? .running : .ready
    }

    private var reviewStepState: FatLossWorkflowState {
        guard recentMealPlanCount > 0 else { return .pending }
        return (recentMealPlanCount >= 3 && recentWellnessCount >= 3) ? .done : .ready
    }

    private var recommendedNode: FatLossDecisionNode {
        if profileStepState != .done { return .profileGoal }
        if planningStepState != .done { return .planToday }
        if executionStepState != .done { return .executeLog }
        return .weeklyReview
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                GroupBox(L10n.choose(simplifiedChinese: "减脂决策树", english: "Fat-loss Decision Tree")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            L10n.choose(
                                simplifiedChinese: "从上到下执行，点击任一节点可打开对应卡片。当前建议节点：\(recommendedNode.title)。",
                                english: "Execute top-to-bottom. Tap any node to open its mapped card. Suggested node: \(recommendedNode.title)."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach(FatLossDecisionNode.allCases) { node in
                            decisionNodeButton(node)
                            if node != FatLossDecisionNode.allCases.last {
                                flowArrow
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                selectedNodeCard
            }
            .padding(20)
        }
    }

    private func stepState(for node: FatLossDecisionNode) -> FatLossWorkflowState {
        switch node {
        case .profileGoal:
            return profileStepState
        case .planToday:
            return planningStepState
        case .executeLog:
            return executionStepState
        case .weeklyReview:
            return reviewStepState
        }
    }

    private func stepSummary(for node: FatLossDecisionNode) -> String {
        switch node {
        case .profileGoal:
            return L10n.choose(
                simplifiedChinese: "当前运动员：\(store.selectedAthleteTitle) · 年龄 \(store.profile.athleteAgeYears) · 体重 \(String(format: "%.1f", store.profile.athleteWeightKg))kg · BMR \(store.profile.basalMetabolicRateKcal) kcal",
                english: "Athlete: \(store.selectedAthleteTitle) · Age \(store.profile.athleteAgeYears) · Weight \(String(format: "%.1f", store.profile.athleteWeightKg))kg · BMR \(store.profile.basalMetabolicRateKcal) kcal"
            )
        case .planToday:
            return L10n.choose(
                simplifiedChinese: todayMealPlan == nil
                    ? "今日尚未确认执行策略，先按基础资料校准热量缺口与训练窗口营养。"
                    : "今日计划热量 \(todayMealPlan?.plannedTotals.calories ?? 0) kcal。",
                english: todayMealPlan == nil
                    ? "No daily strategy confirmed yet. Calibrate calorie deficit and training-window fueling first."
                    : "Today's planned calories: \(todayMealPlan?.plannedTotals.calories ?? 0) kcal."
            )
        case .executeLog:
            return L10n.choose(
                simplifiedChinese: "完成度 \(Int(todayExecutionRatio * 100))% · 饮水 \(String(format: "%.1f", todayMealPlan?.hydrationActualLiters ?? 0))L。",
                english: "Completion \(Int(todayExecutionRatio * 100))% · Hydration \(String(format: "%.1f", todayMealPlan?.hydrationActualLiters ?? 0))L."
            )
        case .weeklyReview:
            return L10n.choose(
                simplifiedChinese: "近 7 天餐单 \(recentMealPlanCount) 天 · 恢复样本 \(recentWellnessCount) 条。",
                english: "Last 7 days: meal plans \(recentMealPlanCount) · wellness samples \(recentWellnessCount)."
            )
        }
    }

    @ViewBuilder
    private var selectedNodeCard: some View {
        switch selectedNode {
        case .profileGoal:
            decisionContentCard(
                title: selectedNode.detailCardTitle,
                icon: selectedNode.icon,
                state: profileStepState
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(stepSummary(for: .profileGoal))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    checklistItem(
                        title: L10n.choose(simplifiedChinese: "先校准基础资料", english: "Calibrate baseline profile"),
                        detail: L10n.choose(simplifiedChinese: "年龄、体重、BMR 会直接影响缺口与餐单分配。", english: "Age, weight, and BMR directly influence deficit and meal planning.")
                    )
                    checklistItem(
                        title: L10n.choose(simplifiedChinese: "目标缺口建议", english: "Deficit recommendation"),
                        detail: L10n.choose(simplifiedChinese: "默认建议 300–500 kcal/日，不建议激进减脂。", english: "Default recommendation is 300–500 kcal/day; avoid aggressive cuts.")
                    )
                    checklistItem(
                        title: L10n.choose(simplifiedChinese: "复测节奏", english: "Re-check cadence"),
                        detail: L10n.choose(simplifiedChinese: "每周固定 2–3 次晨起同条件记录。", english: "Log morning measurements 2–3 times weekly under same conditions.")
                    )
                }
            }

        case .planToday:
            decisionContentCard(
                title: selectedNode.detailCardTitle,
                icon: selectedNode.icon,
                state: planningStepState
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(stepSummary(for: .planToday))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !profileConfigured {
                        Text(
                            L10n.choose(
                                simplifiedChinese: "请先完成节点 1（建档与目标），否则减脂策略会偏差。",
                                english: "Complete node 1 (Profile and Goal) first, otherwise the fat-loss strategy will drift."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    checklistItem(
                        title: L10n.choose(simplifiedChinese: "先定今日缺口", english: "Set today's deficit"),
                        detail: L10n.choose(simplifiedChinese: "基础日建议 300-500 kcal 缺口；高强度训练日不要继续扩大缺口。", english: "Target a 300-500 kcal deficit on normal days; do not deepen the deficit on hard training days.")
                    )
                    checklistItem(
                        title: L10n.choose(simplifiedChinese: "碳水围绕训练分配", english: "Place carbs around training"),
                        detail: L10n.choose(simplifiedChinese: "把主要碳水放在训练前后，其他时段优先蛋白、蔬菜和高饱腹食物。", english: "Place the main carbohydrate intake before and after training; prioritize protein, vegetables, and satiety foods otherwise.")
                    )
                    checklistItem(
                        title: L10n.choose(simplifiedChinese: "只保留一套执行策略", english: "Keep one execution strategy"),
                        detail: L10n.choose(simplifiedChinese: "减脂助手已整合饮食流程，不再依赖单独饮食页或扫码搜索。", english: "The fat-loss assistant now owns the nutrition workflow and no longer depends on a separate nutrition page or barcode search.")
                    )
                }
            }

        case .executeLog:
            decisionContentCard(
                title: selectedNode.detailCardTitle,
                icon: selectedNode.icon,
                state: executionStepState
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(stepSummary(for: .executeLog))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(FatLossAssistantCopy.dailyChecklistTitle.localized())
                        .font(.headline)

                    checklistItem(
                        title: L10n.choose(simplifiedChinese: "晨起体重 + 围度", english: "Morning weight + waist"),
                        detail: L10n.choose(simplifiedChinese: "同一时间记录，避免餐后与训练后噪音。", english: "Log at the same time to avoid post-meal/training noise.")
                    )
                    checklistItem(
                        title: L10n.choose(simplifiedChinese: "饮水 / 盐 / 碳水", english: "Water / sodium / carbs"),
                        detail: L10n.choose(simplifiedChinese: "连续记录 3 天，用于识别水重波动。", english: "Track for 3 consecutive days to identify water shifts.")
                    )
                    checklistItem(
                        title: L10n.choose(simplifiedChinese: "训练窗口营养", english: "Training-window nutrition"),
                        detail: L10n.choose(simplifiedChinese: "训练前后优先补碳水与蛋白，保持表现与恢复。", english: "Prioritize carbs + protein around training to protect performance and recovery.")
                    )
                }
            }

        case .weeklyReview:
            decisionContentCard(
                title: selectedNode.detailCardTitle,
                icon: selectedNode.icon,
                state: reviewStepState
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(stepSummary(for: .weeklyReview))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(FatLossAssistantCopy.strategyTitle.localized())
                        .font(.headline)

                    HStack(spacing: 10) {
                        strategyCard(
                            icon: "drop.fill",
                            title: L10n.choose(simplifiedChinese: "水重优先", english: "Water First"),
                            detail: L10n.choose(simplifiedChinese: "体重短期上升时先检查盐与碳水，不急于加大热量缺口。", english: "When weight spikes, inspect sodium/carbs before increasing deficit.")
                        )
                        strategyCard(
                            icon: "flame.fill",
                            title: L10n.choose(simplifiedChinese: "缺口稳定", english: "Steady Deficit"),
                            detail: L10n.choose(simplifiedChinese: "建议维持 300–500 kcal 日缺口，避免代谢适应过快。", english: "Keep a 300–500 kcal daily deficit to avoid aggressive metabolic adaptation.")
                        )
                    }

                    Text(FatLossAssistantCopy.reviewTitle.localized())
                        .font(.headline)
                    FatLossAssistantBulletText(text: L10n.choose(simplifiedChinese: "以 7–14 天趋势作为主要判断，不被单日体重影响。", english: "Use 7–14 day trends as primary signal, not single-day scale changes."))
                    FatLossAssistantBulletText(text: L10n.choose(simplifiedChinese: "若围度下降且训练状态稳定，即使体重平台也可继续当前策略。", english: "If waist decreases and training quality is stable, keep the strategy even on scale plateaus."))
                    FatLossAssistantBulletText(text: L10n.choose(simplifiedChinese: "连续两周无变化时，再微调碳水时段或总热量。", english: "Only after two static weeks, fine-tune carb timing or total calories."))
                }
            }
        }
    }

    private func decisionNodeButton(_ node: FatLossDecisionNode) -> some View {
        let state = stepState(for: node)
        let selected = selectedNode == node

        return Button {
            selectedNode = node
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("\(node.stepNumber)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 18, height: 18)
                        .background((selected ? Color.white.opacity(0.22) : state.color.opacity(0.16)), in: Circle())
                        .foregroundStyle(selected ? Color.white : state.color)

                    Image(systemName: node.icon)
                        .frame(width: 20)
                        .foregroundStyle(selected ? Color.white : HealthThemePalette.accent)

                    Text(node.title)
                        .font(.headline)
                        .foregroundStyle(selected ? Color.white : .primary)

                    Spacer()

                    Label(flowStateLabel(state), systemImage: state.symbol)
                        .font(.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : state.color)
                }

                Text(stepSummary(for: node))
                    .font(.caption)
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : .secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.teal : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private var flowArrow: some View {
        HStack {
            Spacer()
            Image(systemName: "arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func decisionContentCard<Content: View>(
        title: String,
        icon: String,
        state: FatLossWorkflowState,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(HealthThemePalette.accent)
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Label(flowStateLabel(state), systemImage: state.symbol)
                        .font(.caption)
                        .foregroundStyle(state.color)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Creates one checklist row with title and supportive detail.
    /// - Parameters:
    ///   - title: Main checklist action.
    ///   - detail: Supporting execution note.
    /// - Returns: Styled checklist view.
    private func checklistItem(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Builds a compact strategy card used in the strategy section.
    /// - Parameters:
    ///   - icon: SF Symbol icon.
    ///   - title: Strategy title.
    ///   - detail: Strategy explanation.
    /// - Returns: Strategy card view.
    private func strategyCard(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(HealthThemePalette.accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FatLossAssistantCopy.pageTitle.localized())
                .font(.system(size: 40, weight: .heavy, design: .rounded))
            Text(FatLossAssistantCopy.subtitle.localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func flowStateLabel(_ state: FatLossWorkflowState) -> String {
        switch state {
        case .pending:
            return L10n.choose(simplifiedChinese: "待执行", english: "Pending")
        case .running:
            return L10n.choose(simplifiedChinese: "执行中", english: "Running")
        case .blocked:
            return L10n.choose(simplifiedChinese: "已阻止", english: "Blocked")
        case .ready:
            return L10n.choose(simplifiedChinese: "可执行", english: "Ready")
        case .done:
            return L10n.choose(simplifiedChinese: "已完成", english: "Done")
        }
    }
}

/// Renders a single bullet row using body copy style.
private struct FatLossAssistantBulletText: View {
    /// Display text rendered next to the leading bullet symbol.
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
