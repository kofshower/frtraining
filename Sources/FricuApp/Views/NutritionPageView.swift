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
    static let appetiteMechanismTitle = NutritionPageBilingualCopy(simplifiedChinese: "⑤ 血糖-胰岛素-瘦素减脂原理卡", english: "5) Blood Glucose–Insulin–Leptin Card")
    static let appetiteMechanismSummary = NutritionPageBilingualCopy(
        simplifiedChinese: "热量相同下，高/低 GI 的减脂速度接近，但低 GI 让血糖曲线更平缓、饥饿出现更慢，从而更容易控制总摄入。若长期高胰岛素与肥胖并存，常伴随瘦素抵抗，饱腹信号会减弱。",
        english: "At equal calories, high- and low-GI diets can yield similar fat-loss speed, but low GI smooths glycemic swings and delays hunger, improving intake control. With long-term hyperinsulinemia and obesity, leptin resistance can blunt satiety signaling."
    )
    static let insulinGateTitle = NutritionPageBilingualCopy(
        simplifiedChinese: "⑥ 胰岛素-GLUT4 脂肪动员闸门卡",
        english: "6) Insulin-GLUT4 Fat-mobilization Gate Card"
    )
    static let insulinGateSummary = NutritionPageBilingualCopy(
        simplifiedChinese: "高胰岛素阶段更偏向“抑制脂解 + 促进储存”；当胰岛素回落且肌细胞对 GLUT4 信号敏感时，营养分配与训练协同更利于减脂执行。",
        english: "High-insulin phases bias toward reduced lipolysis and increased storage. When insulin falls and muscle GLUT4 signaling remains sensitive, nutrition timing and training can better support fat-loss execution."
    )
    static let tcaFuelCardTitle = NutritionPageBilingualCopy(simplifiedChinese: "⑥ 三羧酸循环供能协同卡", english: "6) TCA Fuel-Synergy Card")
    static let tcaFuelCardSummary = NutritionPageBilingualCopy(
        simplifiedChinese: "截图观点可归纳为：糖、脂肪、蛋白分解后都会汇入乙酰辅酶 A 与三羧酸循环；糖代谢能补充草酰乙酸，帮助循环持续运行。若碳水长期过低，循环通量下降，脂肪氧化效率也会受限。实操上应兼顾热量缺口、碳水窗口、B 族维生素/矿物质与训练刺激。",
        english: "Core screenshot logic: carbohydrate, fat, and protein catabolism all converge at acetyl-CoA and the TCA cycle; carbohydrate metabolism helps replenish oxaloacetate to keep cycle throughput stable. With chronically very low carbohydrate intake, TCA flux can drop and fat-oxidation efficiency may also decline. In practice, combine calorie deficit, carb timing, B-vitamins/minerals, and training stimulus."
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
                    Text(NutritionPageCopy.appetiteMechanismTitle.localized())
                        .font(.headline)

                    DiagramPanelCard {
                        GlycemicLeptinMechanismCard()
                            .frame(maxWidth: .infinity)
                    }

                    Text(NutritionPageCopy.appetiteMechanismSummary.localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(NutritionPageCopy.insulinGateTitle.localized())
                        .font(.headline)

                    DiagramPanelCard {
                        InsulinGlut4MechanismCard()
                            .frame(maxWidth: .infinity)
                    }

                    Text(NutritionPageCopy.insulinGateSummary.localized())
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
                VStack(alignment: .leading, spacing: 10) {
                    Text(NutritionPageCopy.tcaFuelCardTitle.localized())
                        .font(.headline)

                    DiagramPanelCard {
                        TcaFuelSynergyCard()
                            .frame(maxWidth: .infinity)
                    }

                    Text(NutritionPageCopy.tcaFuelCardSummary.localized())
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

/// Diagram card that summarizes screenshot-derived TCA cycle fueling logic.
private struct TcaFuelSynergyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                fuelNode(
                    title: L10n.choose(simplifiedChinese: "糖", english: "Carbs"),
                    detail: L10n.choose(simplifiedChinese: "糖酵解 → 丙酮酸", english: "Glycolysis → pyruvate"),
                    tone: .blue
                )

                fuelNode(
                    title: L10n.choose(simplifiedChinese: "脂肪", english: "Fat"),
                    detail: L10n.choose(simplifiedChinese: "脂解/β 氧化 → 乙酰辅酶 A", english: "Lipolysis/β-oxidation → acetyl-CoA"),
                    tone: .orange
                )

                fuelNode(
                    title: L10n.choose(simplifiedChinese: "蛋白", english: "Protein"),
                    detail: L10n.choose(simplifiedChinese: "生糖/生酮氨基酸补充中间体", english: "Glucogenic/ketogenic amino acids replenish intermediates"),
                    tone: .purple
                )
            }

            HStack {
                Spacer(minLength: 0)
                Image(systemName: "arrow.down")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            fuelNode(
                title: L10n.choose(simplifiedChinese: "循环枢纽：乙酰辅酶 A + 草酰乙酸", english: "Cycle Hub: acetyl-CoA + oxaloacetate"),
                detail: L10n.choose(simplifiedChinese: "草酰乙酸不足时，三羧酸循环通量下降，脂肪氧化‘火力’也会受限。", english: "When oxaloacetate is insufficient, TCA throughput drops and fat oxidation can be constrained."),
                tone: .green
            )

            HStack {
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            fuelNode(
                title: L10n.choose(simplifiedChinese: "输出与实操", english: "Output & Execution"),
                detail: L10n.choose(simplifiedChinese: "电子传递链产出 ATP/CO₂/H₂O；减脂需在热量缺口下，保留训练前后碳水、补充 B 族维生素与铁锌镁、保持水合并强化耐力/间歇训练。", english: "ETC outputs ATP/CO₂/H₂O; fat loss still requires calorie deficit with carb windows around training, B-vitamins + iron/zinc/magnesium support, hydration, and endurance/interval training."),
                tone: .pink
            )
        }
    }

    /// Creates a styled node for the TCA fuel-synergy card.
    /// - Parameters:
    ///   - title: Main text of the node.
    ///   - detail: Support text that explains causal logic.
    ///   - tone: Accent color for readability grouping.
    /// - Returns: A rendered node view.
    private func fuelNode(title: String, detail: String, tone: Color) -> some View {
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

/// Diagram card that summarizes the screenshot-derived hunger and satiety mechanism.
private struct GlycemicLeptinMechanismCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mechanismNode(
                title: L10n.choose(simplifiedChinese: "进食后血糖反应", english: "Post-meal Glycemic Response"),
                detail: L10n.choose(simplifiedChinese: "高 GI：血糖 2 小时内快速冲高并回落；低 GI：约 4 小时平缓波动，饥饿更晚出现。", english: "High GI spikes and drops within ~2 hours; low GI stays steadier for ~4 hours and delays hunger."),
                tone: .blue
            )

            mechanismArrow

            mechanismNode(
                title: L10n.choose(simplifiedChinese: "胰岛素阈值与食欲", english: "Insulin Threshold & Appetite"),
                detail: L10n.choose(simplifiedChinese: "当血糖频繁越过胰岛素刺激阈值，胰岛素分泌上升更明显，后续更容易出现反跳性饥饿。", english: "Frequent crossing of insulin-trigger thresholds drives larger insulin release and can increase rebound hunger."),
                tone: .orange
            )

            mechanismArrow

            mechanismNode(
                title: L10n.choose(simplifiedChinese: "瘦素信号链", english: "Leptin Signaling Chain"),
                detail: L10n.choose(simplifiedChinese: "脂肪细胞分泌瘦素 → 入血 → 作用下丘脑弓状核；若出现瘦素抵抗，则‘已吃够’信号变弱。", english: "Adipocytes release leptin → bloodstream → hypothalamic arcuate nucleus; with leptin resistance, the 'enough food' signal weakens."),
                tone: .purple
            )

            mechanismArrow

            mechanismNode(
                title: L10n.choose(simplifiedChinese: "执行策略", english: "Action Strategy"),
                detail: L10n.choose(simplifiedChinese: "优先天然食物与低 GI 主食、阻力训练/HIIT、规律睡眠与减脂，目标是提升胰岛素与瘦素敏感性。", english: "Prioritize whole foods and lower-GI staples, resistance training/HIIT, regular sleep, and fat reduction to improve insulin/leptin sensitivity."),
                tone: .green
            )
        }
    }

    private var mechanismArrow: some View {
        HStack {
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Creates a styled flow node for the appetite-regulation mechanism card.
    /// - Parameters:
    ///   - title: Main node title.
    ///   - detail: Explanatory body copy.
    ///   - tone: Accent color used for the node border/background.
    /// - Returns: A rendered node view.
    private func mechanismNode(title: String, detail: String, tone: Color) -> some View {
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

/// Diagram card that explains how insulin signaling and GLUT4 affect fat-loss execution.
private struct InsulinGlut4MechanismCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            gateNode(
                title: L10n.choose(simplifiedChinese: "进食后：胰岛素上升", english: "After Meals: Insulin Rises"),
                detail: L10n.choose(simplifiedChinese: "碳水摄入引发胰岛素分泌，短期内更偏向抑制脂肪细胞脂解并促进营养储存。", english: "Carbohydrate intake raises insulin, which temporarily suppresses adipocyte lipolysis and favors nutrient storage."),
                tone: .blue
            )

            gateArrow

            gateNode(
                title: L10n.choose(simplifiedChinese: "肌细胞通道：GLUT4 转位", english: "Muscle Gate: GLUT4 Translocation"),
                detail: L10n.choose(simplifiedChinese: "在胰岛素敏感状态下，GLUT4 更易转位到细胞膜，葡萄糖优先进入肌细胞用于糖原回补与训练恢复。", english: "With good insulin sensitivity, GLUT4 translocates to the membrane so glucose is directed into muscle for glycogen refill and training recovery."),
                tone: .green
            )

            gateArrow

            gateNode(
                title: L10n.choose(simplifiedChinese: "胰岛素长期偏高风险", english: "Risk of Persistently High Insulin"),
                detail: L10n.choose(simplifiedChinese: "若长期高胰岛素并伴随活动不足，脂解受抑、饥饿波动增大，更容易形成‘摄入高于消耗’。", english: "If insulin stays elevated with low activity, lipolysis remains suppressed and hunger swings increase, making intake exceed expenditure."),
                tone: .orange
            )

            gateArrow

            gateNode(
                title: L10n.choose(simplifiedChinese: "执行抓手", english: "Execution Levers"),
                detail: L10n.choose(simplifiedChinese: "把碳水放在训练前后窗口、优先低加工食物、保留阻力训练与有氧，目标是提升胰岛素敏感性并保持脂肪动员。", english: "Place carbs around training windows, prioritize minimally processed foods, and keep resistance plus aerobic work to improve insulin sensitivity while sustaining fat mobilization."),
                tone: .purple
            )
        }
    }

    private var gateArrow: some View {
        HStack {
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func gateNode(title: String, detail: String, tone: Color) -> some View {
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

/// Diagram card that converts screenshot copy into a practical carb-sodium-water decision map.
private struct CarbSodiumWaterMechanismCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mechanismNode(
                title: L10n.choose(simplifiedChinese: "核心定律", english: "Core Rule"),
                detail: L10n.choose(simplifiedChinese: "哪里溶质浓度更高，水分就向哪里移动。", english: "Water shifts toward the compartment with higher solute concentration."),
                tone: .blue
            )

            Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            mechanismNode(
                title: L10n.choose(simplifiedChinese: "高碳（尤其训练后）", english: "High Carb (Especially Post-workout)"),
                detail: L10n.choose(simplifiedChinese: "肌糖原回补（约 1g 糖原结合 3–4g 水）→ 水分更多进入细胞内，外观可能更饱满。", english: "Glycogen refill (about 1g glycogen binds 3–4g water) draws more water into cells and can make muscles look fuller."),
                tone: .green
            )

            mechanismNode(
                title: L10n.choose(simplifiedChinese: "高盐（钠负荷升高）", english: "High Salt (Higher Sodium Load)"),
                detail: L10n.choose(simplifiedChinese: "细胞外液渗透压上升 → 水分更易滞留在细胞外/间质液，体重与浮肿感可能上升。", english: "Extracellular osmotic pressure rises, so water is retained outside cells/interstitial fluid, increasing scale weight and puffiness."),
                tone: .orange
            )

            mechanismNode(
                title: L10n.choose(simplifiedChinese: "结果判读", english: "How to Interpret"),
                detail: L10n.choose(simplifiedChinese: "短期体重↑ 不等于脂肪↑；先看 7–14 天趋势，再结合围度、盐与碳水记录判断。", english: "Short-term weight gain is not equal to fat gain; review 7–14 day trend with circumference plus sodium/carb logs."),
                tone: .purple
            )
        }
    }

    /// Builds a colored node used by the screenshot-summary mechanism card.
    /// - Parameters:
    ///   - title: Node title in the current language.
    ///   - detail: Node explanatory copy in the current language.
    ///   - tone: Accent color for node styling.
    /// - Returns: A rendered card node.
    private func mechanismNode(title: String, detail: String, tone: Color) -> some View {
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

private struct BulletText: View {
    let text: String

    var body: some View {
        Text("• \(text)")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
