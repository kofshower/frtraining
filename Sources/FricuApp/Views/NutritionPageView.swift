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

                    MetabolismSchematicView()

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

private struct MetabolismSchematicView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                MetabolismNode(title: L10n.choose(simplifiedChinese: "糖", english: "Glucose"), tone: .blue)
                MetabolismNode(title: L10n.choose(simplifiedChinese: "甘油/生糖氨基酸", english: "Glycerol/AA"), tone: .indigo)
                MetabolismNode(title: L10n.choose(simplifiedChinese: "脂肪酸", english: "Fatty Acid"), tone: .orange)
            }

            Text("↓")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                MetabolismNode(title: L10n.choose(simplifiedChinese: "丙酮酸", english: "Pyruvate"), tone: .cyan)
                Text("→")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                MetabolismNode(title: L10n.choose(simplifiedChinese: "乙酰辅酶A", english: "Acetyl-CoA"), tone: .mint)
                Text("+", tableName: nil)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                MetabolismNode(title: L10n.choose(simplifiedChinese: "草酰乙酸", english: "OAA"), tone: .teal)
            }

            Text("↓")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            MetabolismNode(title: L10n.choose(simplifiedChinese: "柠檬酸循环（三羧酸循环）", english: "Citrate Cycle (TCA)"), tone: .green)
                .frame(maxWidth: .infinity)

            Text("↓")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                MetabolismNode(title: L10n.choose(simplifiedChinese: "电子传递链", english: "Electron Transport Chain"), tone: .purple)
                Text("→")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                MetabolismNode(title: "ATP + CO₂ + H₂O", tone: .pink)
            }

            Text(L10n.choose(simplifiedChinese: "图示重点：脂肪“烧得快”依赖三羧酸循环不断料，而不是极端单一饮食。", english: "Key point: faster fat oxidation depends on keeping TCA supplied, not extreme single-macro dieting."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.tertiary)
        )
    }
}

private struct MetabolismNode: View {
    let title: String
    let tone: Color

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(tone.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tone.opacity(0.35), lineWidth: 1)
            )
    }
}
