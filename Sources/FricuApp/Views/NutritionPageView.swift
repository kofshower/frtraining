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

            FatLossPrincipleDiagramCard()

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
                    Text(L10n.choose(simplifiedChinese: "② 饮食计划如何生成", english: "2) How Meal Plans Are Generated"))
                        .font(.headline)
                    ForEach(planGenerationRules.indices, id: \.self) { idx in
                        Text("• \(planGenerationRules[idx])")
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.choose(simplifiedChinese: "③ 图中关键阈值（解释性）", english: "3) Key Thresholds in Diagram"))
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

private struct FatLossPrincipleDiagramCard: View {
    private struct FlowNode: Identifiable {
        let id: Int
        let text: String
    }

    private var leptinFlowNodes: [FlowNode] {
        [
            .init(
                id: 1,
                text: L10n.choose(simplifiedChinese: "进食后\n血糖↑ 胰岛素↑", english: "After meal\nGlucose↑ Insulin↑")
            ),
            .init(
                id: 2,
                text: L10n.choose(simplifiedChinese: "脂肪细胞\n分泌瘦素", english: "Fat cell\nLeptin release")
            ),
            .init(
                id: 3,
                text: L10n.choose(simplifiedChinese: "瘦素经血液\n到下丘脑", english: "Leptin via blood\nto hypothalamus")
            ),
            .init(
                id: 4,
                text: L10n.choose(simplifiedChinese: "受体结合成功\n饱腹信号↑", english: "Receptor binds\nSatiety↑")
            )
        ]
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.choose(simplifiedChinese: "原理图（根据你给的图整理）", english: "Principle Diagram (from your reference)"))
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "① 血糖曲线对比（高 GI vs 低 GI）", english: "1) Glucose Curve (High GI vs Low GI)"))
                        .font(.subheadline.weight(.semibold))
                    GlucoseCurveDiagramView()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "② 瘦素饱腹信号链路", english: "2) Leptin Satiety Signal Chain"))
                        .font(.subheadline.weight(.semibold))

                    VStack(spacing: 8) {
                        ForEach(leptinFlowNodes.indices, id: \.self) { index in
                            LeptinFlowNodeView(text: leptinFlowNodes[index].text)
                            if index < leptinFlowNodes.count - 1 {
                                Image(systemName: "arrow.down")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LeptinFlowNodeView: View {
    let text: String

    var body: some View {
        Text(text)
            .multilineTextAlignment(.center)
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
            )
    }
}

private struct GlucoseCurveDiagramView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let x0 = width * 0.08
                let y0 = height * 0.84
                let xMax = width * 0.95
                let yTop = height * 0.08
                let thresholdY = height * 0.56

                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: x0, y: y0))
                        path.addLine(to: CGPoint(x: xMax, y: y0))
                        path.move(to: CGPoint(x: x0, y: y0))
                        path.addLine(to: CGPoint(x: x0, y: yTop))
                    }
                    .stroke(.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                    Path { path in
                        path.move(to: CGPoint(x: x0, y: thresholdY))
                        path.addLine(to: CGPoint(x: xMax, y: thresholdY))
                    }
                    .stroke(.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

                    Path { path in
                        path.move(to: CGPoint(x: x0, y: y0))
                        path.addCurve(
                            to: CGPoint(x: width * 0.44, y: y0),
                            control1: CGPoint(x: width * 0.18, y: height * 0.06),
                            control2: CGPoint(x: width * 0.34, y: height * 0.16)
                        )
                    }
                    .stroke(.red.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    Path { path in
                        path.move(to: CGPoint(x: x0, y: y0))
                        path.addCurve(
                            to: CGPoint(x: width * 0.74, y: y0),
                            control1: CGPoint(x: width * 0.25, y: height * 0.30),
                            control2: CGPoint(x: width * 0.58, y: height * 0.32)
                        )
                    }
                    .stroke(.blue.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    Text("高GI")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                        .position(x: width * 0.29, y: height * 0.16)

                    Text("低GI")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                        .position(x: width * 0.55, y: height * 0.28)

                    Text(L10n.choose(simplifiedChinese: "胰岛素阈值", english: "Insulin threshold"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .position(x: width * 0.78, y: thresholdY - 10)
                }
            }
            .frame(height: 170)

            Text(
                L10n.choose(
                    simplifiedChinese: "高 GI 往往“升得快、掉得快”；低 GI 通常更平缓，饱腹维持更稳定。",
                    english: "High-GI often spikes and drops faster; lower-GI is steadier with longer satiety."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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
