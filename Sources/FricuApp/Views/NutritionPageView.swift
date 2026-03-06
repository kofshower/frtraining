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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "减肥页：底层逻辑", english: "Fat-loss: Core Logic"))
                        .font(.headline)
                    Text(
                        L10n.choose(
                            simplifiedChinese: "核心不是“某一顿吃胖了”，而是细胞内外溶质浓度变化引起的水分转移。高碳+高盐时，短期体重上涨常由水分变化主导；计划会据此区分“水重波动”和“脂肪变化”。",
                            english: "The core is not just 'one meal made me fat'. Solute shifts between extracellular and intracellular spaces move water. With high-carb + high-salt intake, short-term weight gains are often water-driven, and the planner separates water fluctuation from fat change."
                        )
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.choose(simplifiedChinese: "① 原理图（渗透作用）", english: "1) Mechanism Diagram (Osmosis)"))
                        .font(.headline)

                    OsmosisMechanismCard()
                        .frame(height: 250)

                    Text(
                        L10n.choose(
                            simplifiedChinese: "当细胞内“溶质浓度”更高时，水分向细胞内移动；当间质液钠负荷更高时，水分更易滞留在细胞外。系统将该逻辑用于解释体重日波动。",
                            english: "When intracellular solute concentration is higher, water shifts into cells. When extracellular sodium load is higher, water is retained outside cells. The system uses this to explain day-to-day weight changes."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.choose(simplifiedChinese: "② 饮食计划生成引擎", english: "2) Meal-plan Generation Engine"))
                        .font(.headline)

                    PlanGenerationFlowCard()
                        .frame(maxWidth: .infinity)

                    Text(
                        L10n.choose(
                            simplifiedChinese: "输入层：体重趋势、训练负荷、近 3 日碳水/盐/饮水；规则层：先判别水重波动，再计算热量缺口与三大营养素；输出层：生成每餐建议与次日调节策略。",
                            english: "Input layer: weight trend, training load, and recent 3-day carbs/salt/water. Rule layer: detect water-weight fluctuation first, then compute deficit and macros. Output layer: meal suggestions plus next-day adjustment strategy."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.choose(simplifiedChinese: "③ 页面如何指导执行", english: "3) How This Page Guides Execution"))
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

private struct OsmosisMechanismCard: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background.tertiary)

                Path { path in
                    let x = width * 0.5
                    path.move(to: CGPoint(x: x, y: 18))
                    path.addLine(to: CGPoint(x: x, y: 230))
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "细胞外", english: "Extracellular"))
                        .font(.caption.weight(.semibold))
                    Text(L10n.choose(simplifiedChinese: "溶质浓度 40%", english: "Solute 40%"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("○  ○\n○")
                        .font(.title3)
                }
                .position(x: width * 0.25, y: 76)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "细胞内", english: "Intracellular"))
                        .font(.caption.weight(.semibold))
                    Text(L10n.choose(simplifiedChinese: "溶质浓度 60%", english: "Solute 60%"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("○  ○\n○  ○\n○")
                        .font(.title3)
                }
                .position(x: width * 0.75, y: 84)

                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .position(x: width * 0.52, y: 112)

                Text(L10n.choose(simplifiedChinese: "水分由细胞外流向细胞内", english: "Water moves from extracellular to intracellular"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .position(x: width * 0.5, y: 210)
            }
        }
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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.tertiary)
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
