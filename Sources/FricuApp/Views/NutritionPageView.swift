import SwiftUI

struct NutritionPageView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: NutritionTab = .planner

    private enum NutritionTab: String, CaseIterable, Identifiable {
        case planner
        case fatLossLogic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .planner:
                return L10n.choose(simplifiedChinese: "饮食计划", english: "Meal Planner")
            case .fatLossLogic:
                return L10n.choose(simplifiedChinese: "减脂逻辑", english: "Fat-loss Logic")
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
                        L10n.choose(
                            simplifiedChinese: "按运动员记录每日饮食计划、实际摄入、饮水与宏量营养，独立于 Dashboard 使用。",
                            english: "Log daily meal plans, actual intake, hydration, and macros in a dedicated page."
                        )
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
                    FatLossPageView()
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                }

                FatLossLogicExplainerCard()
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(20)
        }
    }
}

private struct FatLossPageView: View {
    private struct DailyMeal: Identifiable {
        let id: Int
        let meal: String
        let strategy: String
    }

    private var physiologyFlow: [String] {
        [
            L10n.choose(
                simplifiedChinese: "细胞缺乏可用能量 → 触发饥饿感。",
                english: "Cells lack usable energy → hunger signal rises."
            ),
            L10n.choose(
                simplifiedChinese: "进食后血糖上升，达到阈值时胰岛素分泌明显增加。",
                english: "After eating, blood glucose rises and insulin increases when threshold is reached."
            ),
            L10n.choose(
                simplifiedChinese: "脂肪细胞分泌瘦素，瘦素进入血液并作用于下丘脑受体。",
                english: "Fat cells release leptin, which reaches hypothalamic receptors through blood."
            ),
            L10n.choose(
                simplifiedChinese: "受体结合成功时出现“吃饱”信号；若瘦素抵抗则饱腹信号减弱。",
                english: "When receptor binding works, satiety appears; leptin resistance weakens that signal."
            )
        ]
    }

    private var planGenerationRules: [String] {
        [
            L10n.choose(
                simplifiedChinese: "先按体重、训练负荷与目标建立温和热量缺口，避免极低热量引发反弹性饥饿。",
                english: "Start with a moderate calorie deficit from bodyweight, training load, and goal."
            ),
            L10n.choose(
                simplifiedChinese: "优先低加工、低 GI 主食，降低“快速升糖→快速回落”带来的食欲波动。",
                english: "Prefer minimally processed, lower-GI staples to reduce appetite swings."
            ),
            L10n.choose(
                simplifiedChinese: "在关键训练前后安排主要碳水，非关键时段用蛋白+蔬菜+适量脂肪稳住饱腹。",
                english: "Place most carbs around key sessions; use protein+veg+fat at other times."
            ),
            L10n.choose(
                simplifiedChinese: "每餐保留足够蛋白和纤维，提升饱腹与恢复质量。",
                english: "Keep enough protein and fiber per meal for satiety and recovery."
            ),
            L10n.choose(
                simplifiedChinese: "每 7–14 天依据体重趋势、训练表现和主观饥饿度微调摄入。",
                english: "Adjust intake every 7–14 days using weight trend, training quality, and hunger."
            )
        ]
    }

    private var generatedDayPlan: [DailyMeal] {
        [
            .init(
                id: 1,
                meal: L10n.choose(simplifiedChinese: "早餐", english: "Breakfast"),
                strategy: L10n.choose(
                    simplifiedChinese: "高蛋白 + 高纤维（如鸡蛋/酸奶 + 燕麦 + 水果），降低上午血糖波动。",
                    english: "High protein + high fiber (e.g., eggs/yogurt + oats + fruit) to reduce morning glucose swings."
                )
            ),
            .init(
                id: 2,
                meal: L10n.choose(simplifiedChinese: "训练前后", english: "Pre/Post Training"),
                strategy: L10n.choose(
                    simplifiedChinese: "把主要碳水放在训练窗口，优先补糖原并减少其他时段饥饿反扑。",
                    english: "Place most carbs in the training window to replenish glycogen and reduce rebound hunger later."
                )
            ),
            .init(
                id: 3,
                meal: L10n.choose(simplifiedChinese: "午/晚餐", english: "Lunch/Dinner"),
                strategy: L10n.choose(
                    simplifiedChinese: "采用“蛋白 + 蔬菜 + 适量主食 + 适量脂肪”结构，稳定胰岛素并保留饱腹。",
                    english: "Use the structure: protein + vegetables + moderate carbs + moderate fats for insulin stability and satiety."
                )
            ),
            .init(
                id: 4,
                meal: L10n.choose(simplifiedChinese: "加餐策略", english: "Snack Strategy"),
                strategy: L10n.choose(
                    simplifiedChinese: "优先低热量高体积食物（蔬果、无糖酸奶、清汤）应对食欲峰值。",
                    english: "Prefer low-calorie high-volume foods (fruit/veg, unsweetened yogurt, broth) for appetite peaks."
                )
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.choose(simplifiedChinese: "减肥页面：底层逻辑说明", english: "Fat-loss Page: Core Logic"))
                .font(.title3.weight(.bold))

            Text(
                L10n.choose(
                    simplifiedChinese: "基于你提供的示意图，这里把“血糖—胰岛素—瘦素—饱腹信号”转成可执行的饮食计划规则。",
                    english: "Based on your diagram, this page converts glucose–insulin–leptin–satiety logic into practical diet rules."
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "① 生理流程", english: "1) Physiology Flow"))
                        .font(.headline)
                    ForEach(physiologyFlow.indices, id: \.self) { idx in
                        Text("• \(physiologyFlow[idx])")
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "② 单卡片原理图（血糖-INS-GLUT4-瘦素）", english: "2) Single-card Diagram (Glucose-INS-GLUT4-Leptin)"))
                        .font(.headline)
                    FatLossMechanismDiagramView()
                        .frame(height: 250)

                    Text(
                        L10n.choose(
                            simplifiedChinese: "图示表达：碳水→血糖上升→胰岛素→GLUT4开门→葡萄糖入肌细胞；脂肪细胞分泌瘦素回路决定饱腹信号强弱。",
                            english: "The diagram shows carbs → blood glucose rise → insulin → GLUT4 gate opening → muscle glucose uptake; leptin loop from fat cells affects satiety strength."
                        )
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "③ 饮食计划如何生成", english: "3) How Meal Plans Are Generated"))
                        .font(.headline)
                    ForEach(planGenerationRules.indices, id: \.self) { idx in
                        Text("• \(planGenerationRules[idx])")
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "④ 自动生成的一日示例", english: "4) Auto-generated Day Example"))
                        .font(.headline)
                    ForEach(generatedDayPlan) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.id). \(item.meal)")
                                .font(.subheadline.weight(.semibold))
                            Text(item.strategy)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.choose(simplifiedChinese: "⑤ 图中关键阈值（解释性）", english: "5) Key Thresholds in Diagram"))
                        .font(.headline)
                    Text(L10n.choose(simplifiedChinese: "• 饥饿感常在血糖接近较低区间时增强。", english: "• Hunger often rises when glucose nears the lower range."))
                    Text(L10n.choose(simplifiedChinese: "• 高 GI 餐可能更快升降，低 GI 餐通常更平缓更持久。", english: "• High-GI meals can spike/drop faster; low-GI tends to be steadier."))
                    Text(L10n.choose(simplifiedChinese: "• 目标不是“极端低碳”，而是控制波动、保持训练与恢复。", english: "• Goal is not extreme low-carb, but stable fluctuations with quality training/recovery."))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


private struct FatLossMechanismDiagramView: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let left = CGPoint(x: width * 0.2, y: 52)
            let right = CGPoint(x: width * 0.78, y: 82)
            let bottom = CGPoint(x: width * 0.5, y: 190)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.background)

                Path { path in
                    path.move(to: CGPoint(x: left.x + 46, y: left.y + 8))
                    path.addLine(to: CGPoint(x: right.x - 52, y: right.y + 8))
                    path.move(to: CGPoint(x: right.x - 58, y: right.y + 8))
                    path.addLine(to: CGPoint(x: right.x - 68, y: right.y + 2))
                    path.move(to: CGPoint(x: right.x - 58, y: right.y + 8))
                    path.addLine(to: CGPoint(x: right.x - 68, y: right.y + 14))

                    path.move(to: CGPoint(x: right.x - 8, y: right.y + 48))
                    path.addLine(to: CGPoint(x: bottom.x + 20, y: bottom.y - 34))
                    path.move(to: CGPoint(x: bottom.x + 20, y: bottom.y - 34))
                    path.addLine(to: CGPoint(x: bottom.x + 28, y: bottom.y - 36))
                    path.move(to: CGPoint(x: bottom.x + 20, y: bottom.y - 34))
                    path.addLine(to: CGPoint(x: bottom.x + 24, y: bottom.y - 27))

                    path.move(to: CGPoint(x: bottom.x - 16, y: bottom.y - 28))
                    path.addLine(to: CGPoint(x: right.x - 18, y: right.y + 62))
                    path.move(to: CGPoint(x: right.x - 18, y: right.y + 62))
                    path.addLine(to: CGPoint(x: right.x - 25, y: right.y + 55))
                    path.move(to: CGPoint(x: right.x - 18, y: right.y + 62))
                    path.addLine(to: CGPoint(x: right.x - 12, y: right.y + 54))
                }
                .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                MechanismNode(title: L10n.choose(simplifiedChinese: "吃碳水", english: "Carbs"), subtitle: L10n.choose(simplifiedChinese: "血糖↑", english: "Glucose↑"), tint: .orange)
                    .position(left)

                MechanismNode(title: "GLUT4", subtitle: L10n.choose(simplifiedChinese: "肌细胞开门", english: "Cell gate"), tint: .blue)
                    .position(right)

                MechanismNode(title: L10n.choose(simplifiedChinese: "脂肪细胞", english: "Fat cell"), subtitle: L10n.choose(simplifiedChinese: "瘦素→饱腹", english: "Leptin→satiety"), tint: .green)
                    .position(bottom)

                Text(L10n.choose(simplifiedChinese: "胰岛素（INS）", english: "Insulin (INS)"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .position(x: width * 0.52, y: 40)

                Text(L10n.choose(simplifiedChinese: "受体结合", english: "Receptor binding"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: width * 0.7, y: 120)
            }
        }
    }
}

private struct MechanismNode: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        )
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
