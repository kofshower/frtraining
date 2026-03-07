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

/// A dedicated page that summarizes the fat-loss workflow with actionable guidance.
struct FatLossAssistantPageView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

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
