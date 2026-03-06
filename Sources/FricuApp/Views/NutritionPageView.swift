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

    private struct MacroPlan {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
    }

    private var generatedPlan: MacroPlan {
        let protein = max(1_00, Int((bodyWeightKg * 1.8).rounded()))
        let carbs = max(120, Int((bodyWeightKg * trainingLoad.carbFactor).rounded()))
        let fat = max(45, Int((bodyWeightKg * 0.8).rounded()))

        let macroCalories = Double((protein + carbs) * 4 + fat * 9)
        let targetCalories = Int((bodyWeightKg * trainingLoad.baselineCaloriesPerKg + targetSpeed.calorieAdjustment).rounded())
        let calories = max(targetCalories, Int(macroCalories.rounded()))

        return MacroPlan(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    private var tcaLogicSteps: [String] {
        [
            L10n.choose(
                simplifiedChinese: "糖、甘油、生糖氨基酸可汇入丙酮酸；丙酮酸可回补草酰乙酸。",
                english: "Glucose, glycerol, and glucogenic amino acids can feed pyruvate; pyruvate can replenish oxaloacetate."
            ),
            L10n.choose(
                simplifiedChinese: "丙酮酸可转为乙酰辅酶A，脂肪酸 β 氧化也会产生乙酰辅酶A。",
                english: "Pyruvate converts to acetyl-CoA, while fatty-acid β-oxidation also generates acetyl-CoA."
            ),
            L10n.choose(
                simplifiedChinese: "乙酰辅酶A需要与草酰乙酸结合进入柠檬酸循环，才能高效产能。",
                english: "Acetyl-CoA needs oxaloacetate to enter the citrate cycle for efficient energy output."
            ),
            L10n.choose(
                simplifiedChinese: "三羧酸循环产物进入电子传递链，最终形成 ATP、CO₂ 和 H₂O。",
                english: "TCA products feed the electron transport chain to produce ATP, CO₂, and H₂O."
            ),
            L10n.choose(
                simplifiedChinese: "因此减脂不是单纯极低碳，而是保证循环不断料：适量碳水 + 足够蛋白 + 必需脂肪 + 线粒体刺激。",
                english: "So fat loss is not extreme low-carb; keep the cycle fueled with enough carbs, protein, fat, and mitochondrial stimulus."
            )
        ]
    }

    private var generatedRules: [String] {
        [
            L10n.choose(
                simplifiedChinese: "碳水按训练负荷分配：关键训练前后放主碳水，休息时段收敛碳水。",
                english: "Distribute carbs by training demand: more around key sessions, less on easy periods."
            ),
            L10n.choose(
                simplifiedChinese: "蛋白固定优先（约 1.8 g/kg）用于保肌和提升饱腹。",
                english: "Lock protein first (~1.8 g/kg) to preserve muscle and satiety."
            ),
            L10n.choose(
                simplifiedChinese: "脂肪保持底线（约 0.8 g/kg）支持激素和恢复，不做极低脂。",
                english: "Keep fat at a minimum (~0.8 g/kg) for hormonal support and recovery."
            ),
            L10n.choose(
                simplifiedChinese: "补齐 B 族维生素、铁锌镁与水分，避免三羧酸循环和电子传递链“降速”。",
                english: "Ensure B vitamins, iron/zinc/magnesium, and hydration to avoid slowing TCA/ETC throughput."
            )
        ]
    }

    private var perMealProtein: Int {
        max(20, generatedPlan.protein / max(mealsPerDay, 1))
    }

    private var perMealCarbs: Int {
        max(20, generatedPlan.carbs / max(mealsPerDay, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.choose(simplifiedChinese: "减肥页面：底层逻辑 → 饮食计划生成", english: "Fat-loss Page: Core Logic → Meal Generation"))
                .font(.title3.weight(.bold))

            Text(
                L10n.choose(
                    simplifiedChinese: "根据你提供的三羧酸循环示意图，下面把“代谢路径”翻译成可执行的饮食模板。",
                    english: "Based on your TCA-cycle sketch, the page translates metabolic pathways into executable meal templates."
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "1) 底层逻辑（图示同款）", english: "1) Core Logic (from diagram)"))
                        .font(.headline)
                    ForEach(tcaLogicSteps.indices, id: \.self) { index in
                        Text("• \(tcaLogicSteps[index])")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.choose(simplifiedChinese: "2) 计划生成参数", english: "2) Plan Inputs"))
                        .font(.headline)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.choose(simplifiedChinese: "体重 (kg)", english: "Bodyweight (kg)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Stepper(value: $bodyWeightKg, in: 40 ... 130, step: 1) {
                                Text("\(Int(bodyWeightKg)) kg")
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.choose(simplifiedChinese: "每日餐次", english: "Meals per Day"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Stepper(value: $mealsPerDay, in: 2 ... 6) {
                                Text("\(mealsPerDay)")
                            }
                        }
                    }

                    Picker(L10n.choose(simplifiedChinese: "减脂速度", english: "Cut Speed"), selection: $targetSpeed) {
                        ForEach(TargetSpeed.allCases) { speed in
                            Text(speed.title).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(L10n.choose(simplifiedChinese: "训练负荷", english: "Training Load"), selection: $trainingLoad) {
                        ForEach(TrainingLoad.allCases) { load in
                            Text(load.title).tag(load)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.choose(simplifiedChinese: "3) 自动生成结果", english: "3) Auto-generated Targets"))
                        .font(.headline)

                    Text(L10n.choose(simplifiedChinese: "建议总热量", english: "Suggested Calories"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(generatedPlan.calories) kcal/day")
                        .font(.title3.weight(.semibold))

                    HStack(spacing: 14) {
                        Label("P \(generatedPlan.protein)g", systemImage: "figure.strengthtraining.traditional")
                        Label("C \(generatedPlan.carbs)g", systemImage: "bolt.fill")
                        Label("F \(generatedPlan.fat)g", systemImage: "drop.fill")
                    }
                    .font(.callout)

                    Divider()

                    Text(L10n.choose(simplifiedChinese: "每餐分配（\(mealsPerDay) 餐）", english: "Per-meal split (\(mealsPerDay) meals)"))
                        .font(.subheadline.weight(.semibold))
                    Text(
                        L10n.choose(
                            simplifiedChinese: "每餐蛋白约 \(perMealProtein)g，每餐碳水约 \(perMealCarbs)g。关键训练前后餐可上浮 15–25% 碳水。",
                            english: "About \(perMealProtein)g protein and \(perMealCarbs)g carbs per meal. Increase carbs by 15–25% around key sessions."
                        )
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "4) 由逻辑推导出的执行规则", english: "4) Execution Rules Derived from Logic"))
                        .font(.headline)
                    ForEach(generatedRules.indices, id: \.self) { index in
                        Text("• \(generatedRules[index])")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FatLossMechanismDiagram: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.choose(simplifiedChinese: "原理图", english: "Mechanism Diagram"))
                .font(.headline)

            HStack(alignment: .center, spacing: 8) {
                DiagramNode(title: L10n.choose(simplifiedChinese: "脂肪细胞", english: "Fat Cell"), subtitle: "HSL")
                DiagramArrow()
                DiagramNode(title: L10n.choose(simplifiedChinese: "游离脂肪酸", english: "FFA"), subtitle: L10n.choose(simplifiedChinese: "入血运输", english: "Bloodstream"))
                DiagramArrow()
                DiagramNode(title: L10n.choose(simplifiedChinese: "肌细胞", english: "Muscle Cell"), subtitle: L10n.choose(simplifiedChinese: "肉碱穿梭", english: "Carnitine shuttle"))
            }

            HStack(alignment: .center, spacing: 8) {
                DiagramNode(title: L10n.choose(simplifiedChinese: "线粒体", english: "Mitochondria"), subtitle: L10n.choose(simplifiedChinese: "β氧化", english: "β-oxidation"))
                DiagramArrow()
                DiagramNode(title: L10n.choose(simplifiedChinese: "三羧酸循环", english: "TCA Cycle"), subtitle: "Krebs")
                DiagramArrow()
                DiagramNode(title: "ETC", subtitle: "CO₂ + H₂O + ATP")
            }

            Text(
                L10n.choose(
                    simplifiedChinese: "计划生成映射：训练负荷→碳水分配；体重目标→总热量缺口；恢复需求→蛋白与补水下限。",
                    english: "Plan mapping: training load→carb allocation; weight goal→energy deficit; recovery demand→protein and hydration floors."
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.tertiary)
        )
    }
}

private struct DiagramNode: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct DiagramArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.body.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: 18)
    }
}
