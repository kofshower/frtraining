import SwiftUI

/// Bilingual copy token used by nutrition page sections.
struct NutritionPageBilingualCopy {
    /// Simplified Chinese text used when app language is Chinese.
    let simplifiedChinese: String
    /// English text used when app language is English.
    let english: String

    /// Resolve localized text according to the current app language setting.
    /// - Returns: Localized copy chosen by ``L10n``.
    func localized() -> String {
        L10n.choose(simplifiedChinese: simplifiedChinese, english: english)
    }
}

/// Centralized copy definitions for the nutrition page to keep wording consistent.
enum NutritionPageCopy {
    static let tabFatLoss = NutritionPageBilingualCopy(simplifiedChinese: "减脂原理", english: "Fat-loss Logic")
    static let headerSubtitle = NutritionPageBilingualCopy(
        simplifiedChinese: "按运动员记录每日饮食计划、实际摄入、饮水与宏量营养，独立于 Dashboard 使用。",
        english: "Log daily meal plans, actual intake, hydration, and macros in a dedicated page."
    )
    static let coreLogicTitle = NutritionPageBilingualCopy(simplifiedChinese: "减脂页：底层逻辑", english: "Fat-loss: Core Logic")
    static let coreLogicBody = NutritionPageBilingualCopy(
        simplifiedChinese: "核心不是“某一顿吃胖了”，而是细胞内外溶质浓度变化引起的水分转移。高碳+高盐时，短期体重上涨常由水分变化主导；系统会据此区分“水重波动”和“脂肪变化”。",
        english: "The core is not just 'one meal made me fat'. Solute shifts between extracellular and intracellular spaces move water. With high-carb + high-salt intake, short-term weight gains are often water-driven, and the planner separates water fluctuation from fat change."
    )
    static let mechanismTitle = NutritionPageBilingualCopy(simplifiedChinese: "① 原理图（渗透作用）", english: "1) Mechanism Diagram (Osmosis)")
    static let mechanismBody = NutritionPageBilingualCopy(
        simplifiedChinese: "当细胞内“溶质浓度”更高时，水分向细胞内移动；当间质液钠负荷更高时，水分更易滞留在细胞外。系统将该逻辑用于解释体重日波动。",
        english: "When intracellular solute concentration is higher, water shifts into cells. When extracellular sodium load is higher, water is retained outside cells. The system uses this to explain day-to-day weight changes."
    )
    static let engineTitle = NutritionPageBilingualCopy(simplifiedChinese: "② 饮食计划生成引擎", english: "2) Meal-plan Generation Engine")
    static let engineBody = NutritionPageBilingualCopy(
        simplifiedChinese: "输入层：体重趋势、训练负荷、近 3 日碳水/盐/饮水；规则层：先判别水重波动，再计算热量缺口与三大营养素；输出层：生成每餐建议与次日调节策略。",
        english: "Input layer: weight trend, training load, and recent 3-day carbs/salt/water. Rule layer: detect water-weight fluctuation first, then compute deficit and macros. Output layer: meal suggestions plus next-day adjustment strategy."
    )
    static let executionTitle = NutritionPageBilingualCopy(simplifiedChinese: "③ 页面如何指导执行", english: "3) How This Page Guides Execution")
    static let screenshotInsightsTitle = NutritionPageBilingualCopy(simplifiedChinese: "④ 图文核心观点卡", english: "4) Core Insight Card")
    static let screenshotInsightsSummary = NutritionPageBilingualCopy(
        simplifiedChinese: "目标不是盲目少吃，而是让“脂肪动员→进入肌细胞→线粒体氧化→三羧酸循环→电子链产能”这条通路稳定运行。",
        english: "The goal is not blind restriction, but keeping the pathway 'fat mobilization → muscle uptake → mitochondrial oxidation → TCA cycle → electron transport energy production' running efficiently."
    )
}

struct NutritionPageView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: NutritionTab = .planner

    private enum NutritionTab: String, CaseIterable, Identifiable {
        case planner
        case fatLossMechanism

        var id: String { rawValue }

        var title: String {
            switch self {
            case .planner:
                return L10n.choose(simplifiedChinese: "饮食计划", english: "Meal Planner")
            case .fatLossMechanism:
                return NutritionPageCopy.tabFatLoss.localized()
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.choose(simplifiedChinese: "饮食", english: "Nutrition"))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                    Text(
                        NutritionPageCopy.headerSubtitle.localized()
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Picker("NutritionTab", selection: $selectedTab) {
                    ForEach(NutritionTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if selectedTab == .planner {
                    NutritionPlannerCard()
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    FatLossMechanismPageView()
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(20)
        }
    }
}

private struct FatLossMechanismPageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NutritionPageCopy.coreLogicTitle.localized())
                        .font(.headline)
                    Text(
                        NutritionPageCopy.coreLogicBody.localized()
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(NutritionPageCopy.mechanismTitle.localized())
                        .font(.headline)

                    DiagramPanelCard {
                        OsmosisMechanismCard()
                            .frame(minHeight: 210)
                    }

                    Text(
                        NutritionPageCopy.mechanismBody.localized()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(NutritionPageCopy.engineTitle.localized())
                        .font(.headline)

                    DiagramPanelCard {
                        PlanGenerationFlowCard()
                            .frame(maxWidth: .infinity)
                    }

                    Text(
                        NutritionPageCopy.engineBody.localized()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(NutritionPageCopy.screenshotInsightsTitle.localized())
                        .font(.headline)

                    DiagramPanelCard {
                        FatLossPathwayCard()
                            .frame(maxWidth: .infinity)
                    }

                    Text(NutritionPageCopy.screenshotInsightsSummary.localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NutritionPageCopy.executionTitle.localized())
                        .font(.headline)

                    BulletText(text: L10n.choose(simplifiedChinese: "若体重上涨但围度稳定，优先提示“水分/电解质回调”，不是立刻大幅降热量。", english: "If weight rises but circumference is stable, prioritize water/electrolyte adjustment instead of aggressive calorie cuts."))
                    BulletText(text: L10n.choose(simplifiedChinese: "关键训练日前后保留碳水窗口，避免“训练能力下降→消耗下降”。", english: "Keep carb windows around key sessions to avoid reduced training output and reduced expenditure."))
                    BulletText(text: L10n.choose(simplifiedChinese: "连续 7–14 天再评估脂肪趋势，避免被单日体重噪音误导。", english: "Assess fat trend over 7–14 days to avoid being misled by single-day weight noise."))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiagramPanelCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background.tertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct OsmosisMechanismCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                osmosisStateCard(
                    title: L10n.choose(simplifiedChinese: "细胞外", english: "Extracellular"),
                    concentration: L10n.choose(simplifiedChinese: "溶质浓度 40%", english: "Solute 40%"),
                    markerText: "○  ○\n○"
                )

                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                    Image(systemName: "arrow.right")
                    Spacer(minLength: 0)
                }
                .font(.headline)
                .foregroundStyle(.primary)

                osmosisStateCard(
                    title: L10n.choose(simplifiedChinese: "细胞内", english: "Intracellular"),
                    concentration: L10n.choose(simplifiedChinese: "溶质浓度 60%", english: "Solute 60%"),
                    markerText: "○  ○\n○  ○\n○"
                )
            }

            Text(L10n.choose(simplifiedChinese: "水分由细胞外流向细胞内", english: "Water moves from extracellular to intracellular"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func osmosisStateCard(title: String, concentration: String, markerText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(concentration)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(markerText)
                .font(.title3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PlanGenerationFlowCard: View {
    var body: some View {
        VStack(spacing: 8) {
            FlowNode(
                title: L10n.choose(simplifiedChinese: "输入", english: "Inputs"),
                detail: L10n.choose(simplifiedChinese: "体重趋势 + 训练负荷 + 碳水/盐/饮水记录", english: "Weight trend + training load + carbs/salt/hydration logs"),
                tone: .blue
            )
            Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)
            FlowNode(
                title: L10n.choose(simplifiedChinese: "判别层", english: "Decision Layer"),
                detail: L10n.choose(simplifiedChinese: "区分水重波动 / 脂肪趋势", english: "Separate water fluctuation from fat trend"),
                tone: .orange
            )
            Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)
            FlowNode(
                title: L10n.choose(simplifiedChinese: "输出", english: "Outputs"),
                detail: L10n.choose(simplifiedChinese: "当日热量、三大营养素、每餐分配与次日调节", english: "Calories, macros, per-meal split, and next-day adjustments"),
                tone: .green
            )
        }
    }
}

private struct FatLossPathwayCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            pathwayNode(
                title: L10n.choose(simplifiedChinese: "脂肪动员", english: "Fat Mobilization"),
                detail: L10n.choose(simplifiedChinese: "脂肪细胞在 HSL 活性支持下，将甘油三酯分解为甘油 + 游离脂肪酸并入血", english: "With adequate HSL activity, adipose triglycerides split into glycerol + free fatty acids and enter bloodstream"),
                tone: .pink
            )

            pathwayArrow

            pathwayNode(
                title: L10n.choose(simplifiedChinese: "运输与进入肌细胞", english: "Transport & Muscle Uptake"),
                detail: L10n.choose(simplifiedChinese: "游离脂肪酸通过血液到达目标肌细胞，胰岛素敏感性影响进入效率", english: "Free fatty acids are delivered to target muscle cells, and insulin sensitivity affects uptake efficiency"),
                tone: .purple
            )

            pathwayArrow

            pathwayNode(
                title: L10n.choose(simplifiedChinese: "线粒体燃烧", english: "Mitochondrial Oxidation"),
                detail: L10n.choose(simplifiedChinese: "脂肪酸在肉碱转运系统帮助下进入线粒体，随后进行 β 氧化", english: "Fatty acids enter mitochondria via the carnitine shuttle, then undergo β-oxidation"),
                tone: .orange
            )

            pathwayArrow

            pathwayNode(
                title: L10n.choose(simplifiedChinese: "能量释放", english: "Energy Release"),
                detail: L10n.choose(simplifiedChinese: "乙酰辅酶 A 进入三羧酸循环与电子传递链，生成 ATP，并产生 CO₂ 与 H₂O", english: "Acetyl-CoA enters TCA cycle and electron transport chain to generate ATP with CO₂ and H₂O"),
                tone: .green
            )

            Divider()

            Text(L10n.choose(simplifiedChinese: "执行抓手：① 提升 HSL 活性 ② 维持胰岛素敏感性 ③ 做心肺/HIIT 增线粒体容量与氧化速率 ④ 补水 + B 族维生素支持代谢循环", english: "Execution handles: 1) improve HSL activity 2) maintain insulin sensitivity 3) use cardio/HIIT to improve mitochondrial capacity and oxidation rate 4) hydration + B vitamins to support metabolic cycle"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pathwayArrow: some View {
        HStack {
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func pathwayNode(title: String, detail: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tone.opacity(0.4), lineWidth: 1)
        )
    }
}

private struct FlowNode: View {
    let title: String
    let detail: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tone.opacity(0.4), lineWidth: 1)
        )
    }
}

private struct BulletText: View {
    let text: String

    var body: some View {
        Text("• \(text)")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
