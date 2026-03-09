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
        simplifiedChinese: "把计划、执行与复盘放在一页：先判别水重波动，再调整热量缺口与碳水窗口。",
        english: "Keep plan, execution, and review on one page: detect water fluctuation first, then adjust deficit and carb windows."
    )
    static let dailyChecklistTitle = FatLossAssistantBilingualCopy(simplifiedChinese: "今日执行清单", english: "Today's Execution Checklist")
    static let strategyTitle = FatLossAssistantBilingualCopy(simplifiedChinese: "策略卡", english: "Strategy Cards")
    static let reviewTitle = FatLossAssistantBilingualCopy(simplifiedChinese: "复盘规则", english: "Review Rules")
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
        return store.mealPlansForAthlete(named: store.selectedAthleteNameForWrite)
            .filter { $0.date >= cutoff }
            .count
    }

    private var recentWellnessCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return store.wellnessSamplesForAthlete(named: store.selectedAthleteNameForWrite)
            .filter { $0.date >= cutoff }
            .count
    }

    private var profileStepState: FatLossWorkflowState {
        if store.isAllAthletesSelected { return .blocked }
        return profileConfigured ? .done : .ready
    }

    private var planningStepState: FatLossWorkflowState {
        if store.isAllAthletesSelected { return .blocked }
        guard profileConfigured else { return .blocked }
        return todayMealPlan == nil ? .ready : .done
    }

    private var executionStepState: FatLossWorkflowState {
        if store.isAllAthletesSelected { return .blocked }
        guard todayMealPlan != nil else { return .pending }
        if todayExecutionRatio >= 0.85 || hydrationLogged {
            return .done
        }
        return executionLogged ? .running : .ready
    }

    private var reviewStepState: FatLossWorkflowState {
        if store.isAllAthletesSelected { return .blocked }
        guard recentMealPlanCount > 0 else { return .pending }
        return (recentMealPlanCount >= 3 && recentWellnessCount >= 3) ? .done : .ready
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                GroupBox(L10n.choose(simplifiedChinese: "减脂流程", english: "Fat-loss Workflow")) {
                    VStack(alignment: .leading, spacing: 12) {
                        flowCard(
                            step: 1,
                            title: L10n.choose(simplifiedChinese: "建档与目标", english: "Profile and Goal"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "当前运动员：\(store.selectedAthleteTitle) · 年龄 \(store.profile.athleteAgeYears) · 体重 \(String(format: "%.1f", store.profile.athleteWeightKg))kg · BMR \(store.profile.basalMetabolicRateKcal) kcal",
                                english: "Athlete: \(store.selectedAthleteTitle) · Age \(store.profile.athleteAgeYears) · Weight \(String(format: "%.1f", store.profile.athleteWeightKg))kg · BMR \(store.profile.basalMetabolicRateKcal) kcal"
                            ),
                            state: profileStepState
                        )

                        flowCard(
                            step: 2,
                            title: L10n.choose(simplifiedChinese: "生成今日餐单", english: "Plan Today"),
                            subtitle: L10n.choose(
                                simplifiedChinese: todayMealPlan == nil
                                    ? "尚未生成今日餐单，先在下方营养规划中保存目标。"
                                    : "今日计划热量 \(todayMealPlan?.plannedTotals.calories ?? 0) kcal，目标可直接用于执行打卡。",
                                english: todayMealPlan == nil
                                    ? "No plan for today yet. Save targets in Nutrition Planner first."
                                    : "Today's planned calories: \(todayMealPlan?.plannedTotals.calories ?? 0) kcal."
                            ),
                            state: planningStepState
                        )

                        flowCard(
                            step: 3,
                            title: L10n.choose(simplifiedChinese: "执行与打卡", english: "Execute and Log"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "完成度 \(Int(todayExecutionRatio * 100))% · 饮水记录 \(String(format: "%.1f", todayMealPlan?.hydrationActualLiters ?? 0))L。",
                                english: "Completion \(Int(todayExecutionRatio * 100))% · Hydration \(String(format: "%.1f", todayMealPlan?.hydrationActualLiters ?? 0))L."
                            ),
                            state: executionStepState
                        )

                        flowCard(
                            step: 4,
                            title: L10n.choose(simplifiedChinese: "7天复盘与调参", english: "7-day Review and Adjust"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "近 7 天餐单 \(recentMealPlanCount) 天 · 恢复样本 \(recentWellnessCount) 条。",
                                english: "Last 7 days: meal plans \(recentMealPlanCount) · wellness samples \(recentWellnessCount)."
                            ),
                            state: reviewStepState
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(FatLossAssistantCopy.reviewTitle.localized())
                            .font(.headline)
                        FatLossAssistantBulletText(text: L10n.choose(simplifiedChinese: "以 7–14 天趋势作为主要判断，不被单日体重影响。", english: "Use 7–14 day trends as the primary signal, not single-day scale changes."))
                        FatLossAssistantBulletText(text: L10n.choose(simplifiedChinese: "若围度下降且训练状态稳定，即使体重平台也可继续当前策略。", english: "If waist decreases and training quality is stable, keep the current strategy even with weight plateau."))
                        FatLossAssistantBulletText(text: L10n.choose(simplifiedChinese: "连续两周无变化时，再微调碳水时段或总热量。", english: "Only after two static weeks, fine-tune carb timing or total calories."))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                NutritionPlannerCard()
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(20)
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

    @ViewBuilder
    private func flowCard(
        step: Int,
        title: String,
        subtitle: String,
        state: FatLossWorkflowState
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(step)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 18, height: 18)
                    .background(state.color.opacity(0.16), in: Circle())
                    .foregroundStyle(state.color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(flowStateLabel(state), systemImage: state.symbol)
                    .font(.caption)
                    .foregroundStyle(state.color)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
