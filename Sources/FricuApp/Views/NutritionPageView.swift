import SwiftUI

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
                return L10n.choose(simplifiedChinese: "减肥逻辑", english: "Fat-loss Logic")
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
    @State private var bodyWeightKg: Double = 70
    @State private var targetSpeed: TargetSpeed = .steady
    @State private var trainingLoad: TrainingLoad = .moderate
    @State private var mealsPerDay: Int = 3

    private enum TargetSpeed: String, CaseIterable, Identifiable {
        case steady
        case aggressive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .steady:
                return L10n.choose(simplifiedChinese: "稳健减脂", english: "Steady Cut")
            case .aggressive:
                return L10n.choose(simplifiedChinese: "加速减脂", english: "Aggressive Cut")
            }
        }

        var calorieAdjustment: Double {
            switch self {
            case .steady: return -250
            case .aggressive: return -450
            }
        }
    }

    private enum TrainingLoad: String, CaseIterable, Identifiable {
        case low
        case moderate
        case high

        var id: String { rawValue }

        var title: String {
            switch self {
            case .low:
                return L10n.choose(simplifiedChinese: "低训练量", english: "Low Load")
            case .moderate:
                return L10n.choose(simplifiedChinese: "中训练量", english: "Moderate Load")
            case .high:
                return L10n.choose(simplifiedChinese: "高训练量", english: "High Load")
            }
        }

        var carbFactor: Double {
            switch self {
            case .low: return 2.2
            case .moderate: return 3.0
            case .high: return 4.0
            }
        }

        var baselineCaloriesPerKg: Double {
            switch self {
            case .low: return 29
            case .moderate: return 33
            case .high: return 37
            }
        }
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
