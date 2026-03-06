import SwiftUI

struct NutritionPageView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.choose(simplifiedChinese: "饮食", english: "Nutrition"))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                    Text(
                        L10n.choose(
                            simplifiedChinese: "按运动员记录每日饮食计划、实际摄入、饮水与宏量营养，独立于 Dashboard 使用。",
                            english: "Log daily meal plans, actual intake, hydration, and macros in a dedicated page."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                NutritionPlannerCard()
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                FatLossLogicExplainerCard()
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(20)
        }
    }
}

private struct FatLossLogicExplainerCard: View {
    private struct LogicStep: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private var steps: [LogicStep] {
        [
            .init(
                id: 1,
                title: L10n.choose(simplifiedChinese: "脂肪动员（HSL）", english: "Mobilization (HSL)"),
                detail: L10n.choose(
                    simplifiedChinese: "先让脂肪细胞把甘油三酯分解成游离脂肪酸并释放入血，形成“可用燃料池”。",
                    english: "Triglycerides are first broken down into free fatty acids and released into blood as usable fuel."
                )
            ),
            .init(
                id: 2,
                title: L10n.choose(simplifiedChinese: "进入肌细胞并运输", english: "Cell Entry & Transport"),
                detail: L10n.choose(
                    simplifiedChinese: "脂肪酸需要进入目标肌细胞，并通过肉碱穿梭系统进入线粒体。",
                    english: "Fatty acids enter muscle cells and are shuttled into mitochondria via the carnitine system."
                )
            ),
            .init(
                id: 3,
                title: L10n.choose(simplifiedChinese: "β氧化 + 三羧酸循环", english: "β-oxidation + TCA"),
                detail: L10n.choose(
                    simplifiedChinese: "在线粒体内先做β氧化，再进入三羧酸循环与电子传递链，最终产出ATP。",
                    english: "Inside mitochondria, β-oxidation feeds TCA and the electron transport chain to produce ATP."
                )
            ),
            .init(
                id: 4,
                title: L10n.choose(simplifiedChinese: "代谢环境维持", english: "Metabolic Context"),
                detail: L10n.choose(
                    simplifiedChinese: "保证水合、B族维生素、蛋白与训练刺激，减少“脂肪出不来或烧不掉”的瓶颈。",
                    english: "Hydration, B vitamins, protein, and training stimuli help avoid common fat-oxidation bottlenecks."
                )
            )
        ]
    }

    private var planRules: [String] {
        [
            L10n.choose(
                simplifiedChinese: "优先建立温和热量缺口：按训练日/休息日分配热量，避免长期过低导致代谢与训练质量下降。",
                english: "Use a moderate calorie deficit with training-day vs rest-day energy distribution."
            ),
            L10n.choose(
                simplifiedChinese: "蛋白固定优先：每公斤体重约 1.6–2.2g 蛋白，先保留瘦体重。",
                english: "Lock protein first (about 1.6–2.2 g/kg bodyweight) to preserve lean mass."
            ),
            L10n.choose(
                simplifiedChinese: "碳水按训练负荷周期化：关键训练日前后增加碳水，低强度日适当下调。",
                english: "Periodize carbs around training load—higher near key sessions, lower on easy days."
            ),
            L10n.choose(
                simplifiedChinese: "脂肪兜底激素需求：保持基础脂肪摄入，避免极低脂饮食。",
                english: "Keep a minimum fat intake to support endocrine function."
            ),
            L10n.choose(
                simplifiedChinese: "每 7–14 天评估体重、围度、训练表现和恢复，再动态微调摄入。",
                english: "Reassess every 7–14 days using body metrics, training quality, and recovery signals."
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.choose(simplifiedChinese: "减脂底层逻辑与饮食计划生成", english: "Fat-loss Logic & Diet Plan Generation"))
                .font(.title3.weight(.bold))

            Text(
                L10n.choose(
                    simplifiedChinese: "根据“脂肪动员 → 运输入线粒体 → β氧化 → 三羧酸循环”的路径，本页饮食计划按可执行规则自动生成：",
                    english: "Following the path of mobilization → mitochondrial transport → β-oxidation → TCA, this page generates meal plans with practical rules:"
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(step.id). \(step.title)")
                            .font(.headline)
                        Text(step.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Text(L10n.choose(simplifiedChinese: "饮食计划自动生成规则", english: "Auto-generation Rules"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(planRules.indices, id: \.self) { index in
                    Text("• \(planRules[index])")
                        .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
