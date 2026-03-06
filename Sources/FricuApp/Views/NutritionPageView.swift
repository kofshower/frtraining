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

private struct FatLossPageView: View {
    private struct DailyMeal: Identifiable {
        let id: Int
        let meal: String
        let strategy: String
    }

    private var physiologyFlow: [String] {
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

            FatLossPrincipleDiagramCard()

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
