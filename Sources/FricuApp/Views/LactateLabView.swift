import SwiftUI
import Charts

struct LactateLabView: View {
    @EnvironmentObject private var store: AppStore

    private enum LabTab: String, CaseIterable, Identifiable {
        case latest
        case history

        var id: String { rawValue }

        var title: String {
            switch self {
            case .latest:
                return L10n.t("最新测试", "Latest Test")
            case .history:
                return L10n.t("历史测试结果", "History")
            }
        }
    }

    private enum DecisionNode: String, Identifiable {
        case materials
        case bloodSampling
        case preTestNutrition
        case aerobicPath
        case anaerobicPath
        case sharedInterpretation

        var id: String { rawValue }

        var title: String {
            switch self {
            case .materials:
                return L10n.t("所需材料", "Materials")
            case .bloodSampling:
                return L10n.t("如何采血", "Blood Sampling")
            case .preTestNutrition:
                return L10n.t("测前营养", "Pre-Test Nutrition")
            case .aerobicPath:
                return L10n.t("有氧测试", "Aerobic Pathway")
            case .anaerobicPath:
                return L10n.t("无氧能力和清除测试", "Anaerobic + Clearance")
            case .sharedInterpretation:
                return L10n.t("统一结果解释", "Shared Interpretation")
            }
        }

        var icon: String {
            switch self {
            case .materials:
                return "shippingbox.fill"
            case .bloodSampling:
                return "drop.fill"
            case .preTestNutrition:
                return "fork.knife"
            case .aerobicPath:
                return "lungs.fill"
            case .anaerobicPath:
                return "flame.fill"
            case .sharedInterpretation:
                return "chart.xyaxis.line"
            }
        }
    }

    private enum AerobicTest: String, Identifiable, CaseIterable {
        case fullRamp
        case mlss

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fullRamp:
                return "Full ramp test"
            case .mlss:
                return "Maximal lactate steady state"
            }
        }

        var summary: String {
            switch self {
            case .fullRamp:
                return L10n.t(
                    "连续递增负荷，快速定位乳酸上升拐点和最大有氧能力范围。",
                    "Progressive ramp protocol to quickly identify lactate rise breakpoint and upper aerobic capacity range."
                )
            case .mlss:
                return L10n.t(
                    "在近阈值强度下持续稳定输出，确认可持续的最高乳酸稳态功率。",
                    "Sustained near-threshold protocol to confirm maximal sustainable power at lactate steady state."
                )
            }
        }
    }

    private enum LactateTestType: String, CaseIterable, Identifiable {
        case ramp
        case mlss
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ramp:
                return L10n.t("全递增乳酸测试", "Ramp Test")
            case .mlss:
                return L10n.t("最大乳酸稳态测试", "MLSS Test")
            case .custom:
                return L10n.t("自定义测试", "Custom Test")
            }
        }
    }

    private struct LactateSamplePoint: Identifiable {
        let id = UUID()
        let power: Double
        let lactate: Double
    }

    private struct LactateHistoryRecord: Identifiable {
        let id = UUID()
        let tester: String
        let type: LactateTestType
        let createdAt: Date
        let points: [LactateSamplePoint]
    }

    @State private var selectedTab: LabTab = .latest
    @State private var selectedNode: DecisionNode = .materials
    @State private var showChecklistMode = false
    @State private var selectedAerobicTest: AerobicTest? = nil
    @State private var historyRecords: [LactateHistoryRecord] = []
    @State private var selectedHistoryType: LactateTestType = .ramp
    @State private var draftPower = ""
    @State private var draftLactate = ""
    @State private var draftPoints: [LactateSamplePoint] = []

    private var labSport: SportType {
        store.selectedSportFilter ?? .cycling
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("乳酸实验室", "Lactate Lab"))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))

            Picker("", selection: $selectedTab) {
                ForEach(LabTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Group {
                switch selectedTab {
                case .latest:
                    latestTestView
                case .history:
                    historyTestView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.94), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var latestTestView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sportHeaderCard

                if labSport == .running {
                    runningLactateProtocolView
                } else {
                    cyclingLactateProtocolView
                }

                addHistoryRecordCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
    }

    private var addHistoryRecordCard: some View {
        sectionCard(title: L10n.t("新增测试记录", "Add Test Record"), icon: "square.and.pencil") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(L10n.t("测试人", "Tester")): \(store.selectedAthleteNameForWrite)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker(L10n.t("测试类型", "Test Type"), selection: $selectedHistoryType) {
                    ForEach(LactateTestType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }

                HStack {
                    TextField("Power (W)", text: $draftPower)
                        .textFieldStyle(.roundedBorder)
                    TextField("Lactate (mmol/L)", text: $draftLactate)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.t("添加点", "Add Point")) {
                        appendDraftPoint()
                    }
                    .buttonStyle(.bordered)
                }

                if !draftPoints.isEmpty {
                    Text(L10n.t("当前结果点", "Current Result Points"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(draftPoints.map { "\(Int($0.power))W / \(String(format: "%.1f", $0.lactate))" }.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(L10n.t("保存历史记录", "Save Record")) {
                    saveHistoryRecord()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftPoints.count < 2)
            }
        }
    }

    private var sportHeaderCard: some View {
        HStack(spacing: 8) {
            Image(systemName: labSport == .running ? "figure.run" : "bicycle")
                .foregroundStyle(.teal)
            Text(
                L10n.t(
                    "当前运动：\(labSport.label)（可在顶部工具栏切换）",
                    "Current sport: \(labSport.label) (switch from toolbar)"
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var cyclingLactateProtocolView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard(title: L10n.t("决策树", "Decision Tree"), icon: "point.topleft.down.curvedto.point.bottomright.up") {
                VStack(alignment: .leading, spacing: 10) {
                    decisionNodeButton(.materials)
                    flowArrow
                    decisionNodeButton(.bloodSampling)
                    flowArrow
                    decisionNodeButton(.preTestNutrition)

                    Divider().padding(.vertical, 6)

                    HStack(spacing: 10) {
                        decisionNodeButton(.aerobicPath)
                            .frame(maxWidth: .infinity)
                        decisionNodeButton(.anaerobicPath)
                            .frame(maxWidth: .infinity)
                    }

                    if selectedNode == .aerobicPath {
                        aerobicSubtestPanel
                    }

                    decisionNodeButton(.sharedInterpretation)
                }
            }

            selectedNodeContent
        }
    }

    private var runningLactateProtocolView: some View {
        sectionCard(title: L10n.t("跑步乳酸测试流程", "Running Lactate Test Protocol"), icon: "figure.run") {
            VStack(alignment: .leading, spacing: 12) {
                simpleInlineInfoCard(
                    title: L10n.t("适用场景", "Use Case"),
                    description: L10n.t(
                        "用于跑步阈值评估，得到 LT1/LT2 对应配速与心率，指导跑步分区训练。",
                        "Evaluate running thresholds and map LT1/LT2 to pace and heart rate for zone-based run training."
                    )
                )

                stepCard(
                    number: "1",
                    title: L10n.t("热身 15–20 分钟", "Warm Up 15–20 min"),
                    points: [
                        L10n.t("轻松跑 + 3 次 20 秒加速跑", "Easy jog + 3 × 20s strides"),
                        L10n.t("准备好乳酸仪、采血针和记录表", "Prepare lactate meter, lancet, and recording sheet")
                    ]
                )

                stepCard(
                    number: "2",
                    title: L10n.t("递增阶段（每级 4 分钟）", "Incremental Stages (4 min each)"),
                    points: [
                        L10n.t("建议每级提速 0.5 km/h（或约 10–15 秒/km）", "Increase by 0.5 km/h each stage (or ~10–15 sec/km)"),
                        L10n.t("每级末 30 秒内完成采血并记录乳酸、心率、主观强度", "Collect blood within 30s at stage end and log lactate, HR, and RPE")
                    ]
                )

                stepCard(
                    number: "3",
                    title: L10n.t("终止标准", "Stop Criteria"),
                    points: [
                        L10n.t("RPE ≥ 19 或无法维持目标配速", "RPE ≥ 19 or unable to hold target pace"),
                        L10n.t("乳酸急剧上升并伴随跑姿明显破坏", "Sharp lactate rise with obvious form breakdown")
                    ]
                )

                emphasisCard(
                    title: L10n.t("测试输出", "Outputs"),
                    body: L10n.t(
                        "按乳酸-配速曲线拟合 LT1/LT2，并换算为训练区间配速与阈值心率。",
                        "Fit lactate-vs-pace curve to derive LT1/LT2 and convert them into pace zones and threshold HR."
                    ),
                    highlight: L10n.t("建议每 4–6 周复测一次", "Retest every 4–6 weeks")
                )
            }
        }
    }

    @ViewBuilder
    private var selectedNodeContent: some View {
        switch selectedNode {
        case .materials:
            setupMaterialsView
        case .bloodSampling:
            bloodSamplingGuideView
        case .preTestNutrition:
            preTestNutritionView
        case .aerobicPath:
            EmptyView()
        case .anaerobicPath:
            anaerobicProtocolCard
        case .sharedInterpretation:
            sharedInterpretationView
        }
    }

    private var aerobicSubtestPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
                aerobicProtocolIntroCard

                HStack(spacing: 10) {
                    ForEach(AerobicTest.allCases) { test in
                        Button {
                            selectedAerobicTest = test
                        } label: {
                            HStack {
                                Text(test.title)
                                    .font(.headline)
                                    .foregroundStyle(selectedAerobicTest == test ? .white : .primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(selectedAerobicTest == test ? .white.opacity(0.8) : .secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selectedAerobicTest == test ? Color.teal : Color.primary.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selectedAerobicTest {
                    aerobicSelectedDetailView(selectedAerobicTest)
                }

                Text(L10n.t("最终统一汇总到结果解释。", "Results are merged into Shared Interpretation."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sharedInterpretationView: some View {
        sectionCard(title: L10n.t("📊 测试结果解读", "📊 Test Result Interpretation"), icon: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 12) {
                simpleInlineInfoCard(
                    title: L10n.t("LT1 有氧阈", "LT1 Aerobic Threshold"),
                    description: L10n.t(
                        "LT1 代表有氧效率水平。\n提升意味着：脂肪利用增强、有氧能力提升、乳酸转运增强。\n训练应用：LT1 ≈ Zone 1 上限。",
                        "LT1 represents aerobic efficiency.\nHigher LT1 means better fat use, stronger aerobic base, and better lactate transport.\nTraining use: LT1 ≈ upper limit of Zone 1."
                    )
                )

                simpleInlineInfoCard(
                    title: L10n.t("LT2 乳酸阈", "LT2 Lactate Threshold"),
                    description: L10n.t(
                        "LT2 代表最大稳态能力（MLSS），即乳酸生成 = 乳酸清除。\n提升意味着：有氧增强、代谢效率更高、持续输出更强。\n训练应用：LT2 ≈ Zone 2 上限。",
                        "LT2 represents maximal steady-state ability (MLSS), where lactate production equals clearance.\nHigher LT2 means better aerobic power, efficiency, and sustained output.\nTraining use: LT2 ≈ upper limit of Zone 2."
                    )
                )

                simpleInlineInfoCard(
                    title: L10n.t("VLaMax 无氧能力", "VLaMax Anaerobic Capacity"),
                    description: L10n.t(
                        "冲刺测试后最高乳酸值反映糖酵解能力（无氧潜力）。\n提升意味着无氧爆发增强，但可能降低脂肪供能比例。",
                        "Peak lactate after sprint reflects glycolytic power (anaerobic potential).\nHigher VLaMax often means stronger explosiveness, but may reduce relative fat-fueling share."
                    )
                )

                emphasisCard(
                    title: L10n.t("🧠 综合解读", "🧠 Combined Interpretation"),
                    body: L10n.t("单个指标意义有限，关键看组合变化。", "Single metrics are limited; the key is the combined pattern."),
                    highlight: L10n.t("趋势 > 单次数值", "Trend > single value")
                )

                stepCard(
                    number: "1",
                    title: L10n.t("LT1 ↑ LT2 ↑ VLaMax ↓", "LT1 ↑ LT2 ↑ VLaMax ↓"),
                    points: [
                        L10n.t("➡️ 更强脂代谢", "➡️ Stronger fat metabolism"),
                        L10n.t("➡️ 更耐久型能力", "➡️ Better endurance profile")
                    ]
                )

                stepCard(
                    number: "2",
                    title: L10n.t("LT1 ↑ LT2 ↑ VLaMax →", "LT1 ↑ LT2 ↑ VLaMax →"),
                    points: [
                        L10n.t("➡️ 有氧能力提升", "➡️ Aerobic performance improved")
                    ]
                )

                stepCard(
                    number: "3",
                    title: L10n.t("LT1 ↑ LT2 ↑ VLaMax ↑", "LT1 ↑ LT2 ↑ VLaMax ↑"),
                    points: [
                        L10n.t("➡️ VO2max 提升", "➡️ VO2max likely improved"),
                        L10n.t("➡️ 无氧能力增强", "➡️ Anaerobic capacity increased")
                    ]
                )

                stepCard(
                    number: "4",
                    title: L10n.t("LT1 ↓ LT2 ↓ VLaMax →", "LT1 ↓ LT2 ↓ VLaMax →"),
                    points: [
                        L10n.t("➡️ 有氧能力下降", "➡️ Aerobic ability declined")
                    ]
                )

                stepCard(
                    number: "5",
                    title: L10n.t("LT1 ↓ LT2 ↓ VLaMax ↑", "LT1 ↓ LT2 ↓ VLaMax ↑"),
                    points: [
                        L10n.t("➡️ 糖酵解增强", "➡️ Glycolytic contribution increased"),
                        L10n.t("➡️ 脂代谢下降", "➡️ Fat metabolism contribution decreased")
                    ]
                )

                stepCard(
                    number: "6",
                    title: L10n.t("LT1 ↓ LT2 ↓ VLaMax ↓", "LT1 ↓ LT2 ↓ VLaMax ↓"),
                    points: [
                        L10n.t("➡️ 整体有氧能力下降", "➡️ Overall aerobic profile declined")
                    ]
                )

                simpleInlineInfoCard(
                    title: L10n.t("⚠️ 结果限制", "⚠️ Result Limits"),
                    description: L10n.t(
                        "结果会受营养状态、疲劳、咖啡因、测试时间与压力影响。\n建议至少进行 3–4 次测试形成可靠趋势。",
                        "Results are affected by nutrition, fatigue, caffeine, testing time, and stress.\nUse at least 3–4 tests to build a reliable trend."
                    )
                )

                Text(L10n.t("🟢 一句话总结：看变化组合，而不是单个指标", "🟢 One-line summary: read combinations of change, not isolated metrics."))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.teal)
            }
        }
    }

    private var anaerobicProtocolCard: some View {
        sectionCard(title: L10n.t("⚡ 无氧能力测试", "⚡ Anaerobic Capacity + Clearance"), icon: "flame.fill") {
            VStack(alignment: .leading, spacing: 12) {
                simpleInlineInfoCard(
                    title: L10n.t("📌 测试目的", "📌 Purpose"),
                    description: L10n.t(
                        "了解无氧能力（VLaMax）、糖酵解速率、乳酸生成能力与乳酸清除能力。\n\n✔️ 建议与有氧测试搭配进行，完整评估体能结构。",
                        "Understand anaerobic capacity (VLaMax), glycolytic rate, lactate production, and clearance.\n\n✔️ Pair with aerobic testing for a complete fitness profile."
                    )
                )

                simpleInlineInfoCard(
                    title: L10n.t("⏱ 测试时长", "⏱ Duration"),
                    description: L10n.t("约 30–40 分钟，通常需要 4–5 次采样。", "About 30–40 minutes, typically 4–5 samples.")
                )

                anaerobicSchematic

                stepCard(
                    number: "1",
                    title: L10n.t("低强度恢复", "Low-Intensity Recovery"),
                    points: [
                        L10n.t("有氧测试后轻松骑行 15 分钟，强度约 40–50% FTP。", "After aerobic test, ride easy for 15 minutes at ~40–50% FTP."),
                        L10n.t("目的：清除残余乳酸。", "Goal: clear residual lactate.")
                    ]
                )

                stepCard(
                    number: "2",
                    title: L10n.t("静息准备", "Rest Preparation"),
                    points: [
                        L10n.t("完全休息 5 分钟，采样需 < 2.5 mmol/L。", "Rest fully for 5 minutes; sample should be < 2.5 mmol/L."),
                        L10n.t("若偏高：继续休息再测。", "If higher: keep resting and re-test.")
                    ]
                )

                stepCard(
                    number: "3",
                    title: L10n.t("20 秒全力冲刺", "20s Max Sprint"),
                    points: [
                        L10n.t("进行 20 秒最大努力冲刺。", "Perform a 20-second all-out sprint."),
                        L10n.t("❌ 不使用 ERG；✔️ 预先调高阻力。", "❌ No ERG mode; ✔️ pre-set higher resistance.")
                    ]
                )

                stepCard(
                    number: "4",
                    title: L10n.t("冲刺后完全停止", "Full Stop After Sprint"),
                    points: [
                        L10n.t("冲刺结束后立即停止踩踏。", "Stop pedaling immediately after sprint."),
                        L10n.t("原因：继续骑行会降低乳酸读数。", "Reason: continued pedaling can lower lactate readings.")
                    ]
                )

                stepCard(
                    number: "5",
                    title: L10n.t("恢复期采样", "Recovery Sampling"),
                    points: [
                        L10n.t("保持静止，在 3/5/7 分钟采样。", "Stay still and sample at 3/5/7 minutes."),
                        L10n.t("可加测 4/6 分钟提高精度。", "Optional 4/6-minute samples can improve precision.")
                    ]
                )

                stepCard(
                    number: "6",
                    title: L10n.t("可选清除能力测试", "Optional Clearance Check"),
                    points: [
                        L10n.t("继续休息至 20 分钟，再采样一次评估清除能力。", "Continue resting to minute 20, then sample once more for clearance assessment.")
                    ]
                )

                emphasisCard(
                    title: L10n.t("⚙️ 测试提示", "⚙️ Test Tips"),
                    body: L10n.t("建议选择大齿比进行冲刺，避免踩空；可提前测试齿比以保证冲刺稳定输出。", "Use a larger gear to avoid spinning out; pre-test gear choice to keep sprint output stable."),
                    highlight: L10n.t("📊 结果可用于评估最大乳酸生成能力、无氧爆发潜力与乳酸代谢能力", "📊 Results estimate max lactate production, anaerobic explosiveness, and lactate metabolism capacity")
                )
            }
        }
    }

    private var anaerobicSchematic: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("示意图", "Schematic"))
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .bottom, spacing: 6) {
                Rectangle()
                    .fill(Color.teal.opacity(0.75))
                    .frame(width: 130, height: 34)
                    .overlay(Text("40–50% FTP").font(.caption2.weight(.semibold)))

                VStack(spacing: 2) {
                    Text("5 min").font(.caption2)
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Rectangle().fill(Color.teal.opacity(0.85)).frame(width: 24, height: 80)
                    Text("20s").font(.caption2.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                    }
                    Text(L10n.t("采样 @ 3 / 5 / 7 分钟", "Samples @ 3 / 5 / 7 min"))
                        .font(.caption2)
                    HStack {
                        Rectangle().fill(Color.teal.opacity(0.35)).frame(height: 2)
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                    }
                    Text(L10n.t("可选 20 分钟终末采样", "Optional final sample @ 20 min"))
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(L10n.t("15 分钟恢复（40–50% FTP）→ 5 分钟静息 → 20 秒冲刺 → 静止恢复并定时采样。", "15-min recovery (40–50% FTP) → 5-min rest → 20s sprint → passive recovery with timed sampling."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var preTestNutritionView: some View {
        sectionCard(title: L10n.t("测试前营养控制", "Pre-Test Nutrition Control"), icon: "fork.knife") {
            VStack(alignment: .leading, spacing: 12) {
                emphasisCard(
                    title: L10n.t("测试前 1 小时", "1 Hour Before Test"),
                    body: L10n.t("请不要进食，避免任何含热量饮料。", "Do not eat and avoid any caloric drinks."),
                    highlight: L10n.t("✔️ 仅允许：水 / 无糖饮料", "✔️ Only allowed: water / sugar-free drinks")
                )

                emphasisCard(
                    title: L10n.t("测试过程中", "During Test"),
                    body: L10n.t("全程不摄入任何热量：能量饮料、碳水补给、含糖液体都应避免。", "No calories during the test: avoid energy drinks, carbohydrate fueling, and sugary liquids."),
                    highlight: L10n.t("👉 否则会直接影响乳酸读数", "👉 Calorie intake directly alters lactate readings")
                )

                stepCard(
                    number: "1",
                    title: L10n.t("记录营养状态", "Log Nutrition Status"),
                    points: [
                        L10n.t("上一次进食时间", "Last meal time"),
                        L10n.t("食物类型", "Food type"),
                        L10n.t("饮品类型", "Drink type")
                    ]
                )

                emphasisCard(
                    title: L10n.t("记录目的", "Why Record This"),
                    body: L10n.t("在测试开始前记录饮食状态，可用于后续复测对照。", "Recording pre-test nutrition enables reliable future comparisons."),
                    highlight: L10n.t("👉 让未来测试可复现", "👉 Make future tests reproducible")
                )

                simpleInlineInfoCard(
                    title: L10n.t("核心原则", "Core Principle"),
                    description: L10n.t(
                        "保持每次测试前的饮食条件一致，才能保证乳酸结果具有可比性。",
                        "Keep pre-test nutrition conditions consistent to ensure comparable lactate results."
                    )
                )
            }
        }
    }

    private var bloodSamplingGuideView: some View {
        sectionCard(title: L10n.t("采血流程", "Blood Sampling Workflow"), icon: "drop.fill") {
            VStack(alignment: .leading, spacing: 12) {
                emphasisCard(
                    title: L10n.t("采血位置", "Sampling Site"),
                    body: L10n.t("乳酸可采手指或耳垂；但自测必须使用手指。", "Lactate can be sampled from finger or earlobe; self-testing should use finger only."),
                    highlight: L10n.t("👉 自测必须用手指", "👉 Self-test: finger only")
                )

                emphasisCard(
                    title: L10n.t("最大误差来源", "Largest Error Source"),
                    body: L10n.t("最常见错误来自血样污染：汗、酒精、组织液或皮肤接触。", "The most common error is sample contamination: sweat, alcohol, tissue fluid, or skin contact."),
                    highlight: L10n.t("👉 关键不是取血，而是防污染", "👉 The key is contamination control")
                )

                stepCard(
                    number: "1",
                    title: L10n.t("先准备设备", "Prepare Equipment"),
                    points: [
                        L10n.t("打开酒精棉，准备采血针，提前插入试纸。", "Open alcohol swab, prepare lancet, and insert strip in advance."),
                        L10n.t("❌ 不要触碰试纸两端，避免污染导致误读。", "❌ Do not touch strip ends; contamination causes wrong readings.")
                    ]
                )

                stepCard(
                    number: "2",
                    title: L10n.t("先擦汗", "Dry Sweat First"),
                    points: [
                        L10n.t("采血前擦干手指及周围区域。", "Dry finger and surrounding area before sampling."),
                        L10n.t("出汗多时需擦手、手臂甚至脸，防止汗滴污染。", "If sweating heavily, dry hand/arm/face to avoid sweat-drop contamination.")
                    ]
                )

                stepCard(
                    number: "3",
                    title: L10n.t("酒精消毒", "Alcohol Disinfection"),
                    points: [
                        L10n.t("用酒精棉清洁采血位置。", "Clean site with alcohol swab."),
                        L10n.t("👉 必须完全干燥后再继续。", "👉 Must be fully dry before continuing.")
                    ]
                )

                stepCard(
                    number: "4",
                    title: L10n.t("扎针位置", "Lancing Site"),
                    points: [
                        L10n.t("扎手指侧面，不扎指腹正中。", "Lance the side of finger, not the finger pad center.")
                    ]
                )

                stepCard(
                    number: "5",
                    title: L10n.t("丢弃第一滴血", "Discard First Drop"),
                    points: [
                        L10n.t("第一滴常含组织液，不可靠，必须擦掉。", "First drop may contain tissue fluid; wipe it away.")
                    ]
                )

                stepCard(
                    number: "6",
                    title: L10n.t("取第二滴血", "Take Second Drop"),
                    points: [
                        L10n.t("轻挤形成圆形血珠；若血流下来，擦掉后重取。", "Gently form a round drop; if it runs, wipe and retry.")
                    ]
                )

                stepCard(
                    number: "7",
                    title: L10n.t("试纸接触血滴", "Strip Contact"),
                    points: [
                        L10n.t("✔️ 只碰血滴，❌ 不碰皮肤。", "✔️ Touch blood drop only, ❌ never touch skin."),
                        L10n.t("成功后分析仪会吸血并提示。", "Analyzer will draw blood and prompt when successful.")
                    ]
                )

                stepCard(
                    number: "8",
                    title: L10n.t("记录结果", "Record Result"),
                    points: [
                        L10n.t("等待读数并立即记录。", "Wait for reading and record immediately.")
                    ]
                )

                emphasisCard(
                    title: L10n.t("实战注意事项", "Field Notes"),
                    body: L10n.t("血出不来可先暖手、摇臂或热水预热；避免用力挤压以防组织液稀释乳酸。", "If blood flow is poor, warm hands, swing arm, or pre-warm with hot water; avoid hard squeezing to prevent dilution."),
                    highlight: L10n.t("👉 采血时手要有支撑；乳酸异常跳升建议复测", "👉 Keep hand supported; retest if values jump abnormally")
                )
            }
        }
    }

    private func stepCard(number: String, title: String, points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number)️⃣ \(title)")
                .font(.headline)
            ForEach(points, id: \.self) { point in
                Text("• \(point)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func emphasisCard(title: String, body: String, highlight: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(highlight)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.teal)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var setupMaterialsView: some View {
        sectionCard(title: "🧪 \(L10n.t("乳酸测试准备", "Lactate Test Setup"))", icon: "checklist") {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.t("开始前", "Before You Start"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(L10n.t("乳酸测试准备", "Lactate Test Setup"))
                    .font(.title2.weight(.bold))

                Picker(L10n.t("模式", "Mode"), selection: $showChecklistMode) {
                    Text(L10n.t("准备", "Setup")).tag(false)
                    Text("Checklist").tag(true)
                }
                .pickerStyle(.segmented)

                if showChecklistMode {
                    checklistCard
                } else {
                    setupDetailCards
                }

                Text(L10n.t(
                    "乳酸测试是一个可控实验。\n\n准备比强度更重要。",
                    "Lactate testing is a controlled experiment.\n\nPreparation matters more than intensity."
                ))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

                Text(L10n.t(
                    "把训练变成生理洞察。\n\n开始之前先搭好你的乳酸测试环境。",
                    "Turn your training into physiology insight.\n\nSet up your lactate test environment before you begin."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var setupDetailCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            equipmentCard(
                title: L10n.t("带功率的室内骑行设备", "Indoor Trainer with Power"),
                body: L10n.t("• 智能骑行台\n或\n• 配功率计的自行车", "• Smart trainer\nor\n• Bike with power meter")
            )

            equipmentCard(
                title: L10n.t("乳酸测试仪", "Lactate Analyzer"),
                body: L10n.t(
                    "推荐：\nLactate Pro 2\n\n• 易于使用\n• 无需校准\n• 可使用小血样\n• 误差率低",
                    "Recommended:\nLactate Pro 2\n\n• Easy to use\n• No calibration needed\n• Works with small blood samples\n• Low error rate"
                )
            )

            equipmentCard(
                title: L10n.t("乳酸试纸", "Lactate Test Strips"),
                body: L10n.t("必须与测试仪兼容", "Must be compatible with your analyzer")
            )

            equipmentCard(
                title: L10n.t("安全采血针", "Safety Lancets"),
                body: L10n.t(
                    "新手建议：\n使用较低针规的采血针\n→ 更容易形成更大血滴",
                    "Tip for beginners:\nUse lower gauge lancets\n→ Helps produce larger blood drops"
                )
            )

            equipmentCard(title: L10n.t("酒精棉片", "Alcohol Swabs"), body: "")

            equipmentCard(
                title: L10n.t("辅助用品", "Support Items"),
                body: L10n.t("• 纸巾\n• 毛巾（用于擦汗）", "• Tissues\n• Towel (to remove sweat)")
            )

            equipmentCard(
                title: L10n.t("计时工具", "Timer"),
                body: L10n.t("（例如手机）", "(e.g. phone)")
            )

            equipmentCard(
                title: L10n.t("结果记录", "Results Recording"),
                body: L10n.t("• 笔记本\n• 电脑\n• 表格\n\n使用我们的结果模板", "• Notebook\n• Laptop\n• Spreadsheet\n\nUse our Results Template")
            )

            Text(L10n.t("推荐设备（可选）", "Recommended (Optional)"))
                .font(.headline)
                .padding(.top, 4)

            equipmentCard(
                title: L10n.t("功率稳定软件（ERG 模式）", "ERG Mode Software"),
                body: L10n.t("例如：\n• Zwift\n• TrainerRoad", "e.g.\n• Zwift\n• TrainerRoad")
            )

            equipmentCard(
                title: L10n.t("协助人员（推荐）", "Helper (recommended)"),
                body: L10n.t("建议使用一次性手套\n避免乳胶\n改用丁腈材质", "Disposable gloves advised\nAvoid latex\nUse nitrile instead")
            )
        }
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("测试前清单", "Pre-Test Checklist"))
                .font(.headline)

            Group {
                Text(L10n.t("☑ 骑行台已就绪", "☑ Trainer ready"))
                Text(L10n.t("☑ 测试仪已就绪", "☑ Analyzer ready"))
                Text(L10n.t("☑ 试纸已备齐", "☑ Strips available"))
                Text(L10n.t("☑ 采血针已准备", "☑ Lancets prepared"))
                Text(L10n.t("☑ 酒精棉片已准备", "☑ Alcohol swabs ready"))
                Text(L10n.t("☑ 计时工具已就绪", "☑ Timer ready"))
                Text(L10n.t("☑ 记录方式已就绪", "☑ Recording method ready"))
            }
            .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func decisionNodeButton(_ node: DecisionNode) -> some View {
        Button {
            selectedNode = node
            if node != .aerobicPath {
                selectedAerobicTest = nil
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: node.icon)
                    .frame(width: 24)
                    .foregroundStyle(selectedNode == node ? .white : .teal)

                Text(node.title)
                    .font(.headline)
                    .foregroundStyle(selectedNode == node ? .white : .primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selectedNode == node ? .white.opacity(0.8) : .secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selectedNode == node ? Color.teal : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private var flowArrow: some View {
        HStack {
            Spacer()
            Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func equipmentCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: body.isEmpty ? 0 : 6) {
            Text(title)
                .font(.headline)
            if !body.isEmpty {
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func simpleDetailCard(title: String, description: String) -> some View {
        sectionCard(title: title, icon: "doc.text.magnifyingglass") {
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aerobicProtocolIntroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("🧪 选择你的测试类型", "🧪 Choose Your Test Type"))
                .font(.headline)

            Text(L10n.t("Protocol 1 · 📊 有氧全貌测试", "Protocol 1 · 📊 Aerobic Overview"))
                .font(.subheadline.weight(.semibold))
            Text(L10n.t(
                "用于了解不同强度下乳酸生成情况、整体代谢特征与长期变化趋势。适合初次测试、周期性追踪与训练效果观察。",
                "Used to understand lactate production across intensities, whole metabolic profile, and long-term changes. Best for first test, periodic tracking, and observing training effects."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)

            Text(L10n.t("⚠️ 注意：不能精准确定阈值功率", "⚠️ Limitation: cannot precisely define threshold power"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)

            Divider()

            Text(L10n.t("Protocol 2 · 🎯 阈值精准测试", "Protocol 2 · 🎯 Threshold Precision"))
                .font(.subheadline.weight(.semibold))
            Text(L10n.t(
                "用于确定真实乳酸阈值功率（MLSS），即乳酸生成与清除的最大稳定点。适合精准设置间歇强度、阈值训练与阈值变化监测。",
                "Used to determine true lactate threshold power (MLSS), the maximal steady balance between lactate production and clearance. Best for precise interval targets, threshold training, and threshold monitoring."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)

            Divider()

            Text(L10n.t("🟢 如何选择？", "🟢 How to choose?"))
                .font(.subheadline.weight(.semibold))
            Text(L10n.t("了解整体能力 → 选 Protocol 1\n精准训练阈值 → 选 Protocol 2", "Overall capability insight → Protocol 1\nPrecise threshold targeting → Protocol 2"))
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(L10n.t("📌 一句话总结：Protocol 1 看趋势，Protocol 2 定阈值", "📌 One-liner: Protocol 1 tracks trends, Protocol 2 sets threshold."))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.teal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func aerobicSelectedDetailView(_ test: AerobicTest) -> some View {
        switch test {
        case .fullRamp:
            fullRampProtocolCard
        case .mlss:
            mlssProtocolCard
        }
    }

    private var mlssProtocolCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("🎯 Protocol 2", "🎯 Protocol 2"))
                .font(.headline)
            Text(L10n.t("MLSS 精准阈值测试", "MLSS Precision Threshold Test"))
                .font(.title3.weight(.semibold))

            simpleInlineInfoCard(
                title: L10n.t("📌 测试目的", "📌 Purpose"),
                description: L10n.t(
                    "确定最大乳酸稳态（MLSS）：即乳酸生成 = 乳酸清除时的最大稳定功率。",
                    "Determine maximal lactate steady state (MLSS): the highest stable power where lactate production equals clearance."
                )
            )

            simpleInlineInfoCard(
                title: L10n.t("适用场景", "Best For"),
                description: L10n.t(
                    "✔️ 精准设定阈值训练\n✔️ 制定间歇强度\n✔️ 监测阈值变化",
                    "✔️ Precise threshold training setup\n✔️ Interval intensity prescription\n✔️ Threshold change monitoring"
                )
            )

            simpleInlineInfoCard(
                title: L10n.t("⏱ 测试时长", "⏱ Duration"),
                description: L10n.t("约 40 分钟 +，通常需要 4 次以上采样。", "About 40+ minutes, typically 4+ lactate samples.")
            )

            mlssSchematic

            stepCard(
                number: "1",
                title: L10n.t("准备 MLSS 估计值", "Estimate MLSS"),
                points: [
                    L10n.t("可参考 FTP、Ramp Test 与主观骑行感觉。", "Use FTP, ramp test outcomes, and perceived exertion as references."),
                    L10n.t("👉 MLSS 通常低于 FTP。", "👉 MLSS is usually lower than FTP.")
                ]
            )

            stepCard(
                number: "2",
                title: L10n.t("热身", "Warm-up"),
                points: [
                    L10n.t("热身 15 分钟，逐步提升到目标功率的 80–90%。", "Warm up 15 minutes, ramping to 80–90% of target power."),
                    L10n.t("目的：避免突然强度跳升导致初始乳酸失真。", "Goal: avoid initial lactate distortion from abrupt intensity jumps.")
                ]
            )

            stepCard(
                number: "3",
                title: L10n.t("Stage 1", "Stage 1"),
                points: [
                    L10n.t("10 分钟稳定骑行，功率≈估算 MLSS -10W（不确定可 -15~20W）。", "10-min steady ride at estimated MLSS -10W (or -15~20W if unsure)."),
                    L10n.t("在第 3 分钟与第 9 分钟采样。", "Sample at minute 3 and minute 9."),
                    L10n.t("若乳酸升高 ≤ 1 mmol/L：进入下一阶段；> 1 mmol/L：休息 10 分钟降功率重试。", "If rise ≤ 1 mmol/L: continue; if > 1 mmol/L: rest 10 min and restart with lower power.")
                ]
            )

            stepCard(
                number: "4",
                title: L10n.t("Stage 2+", "Stage 2+"),
                points: [
                    L10n.t("每阶段再增加约 10W，继续 10 分钟稳定骑行。", "Increase ~10W per stage, continue 10-min steady riding."),
                    L10n.t("同样在第 3 分钟与第 9 分钟采样。", "Again sample at minute 3 and minute 9.")
                ]
            )

            emphasisCard(
                title: L10n.t("🧠 关键判断逻辑", "🧠 Key Decision Logic"),
                body: L10n.t("当某阶段乳酸升高 > 1 mmol/L，说明已超过 MLSS；MLSS 位于当前阶段与前一阶段之间，可停止测试。", "When lactate rise in a stage exceeds 1 mmol/L, MLSS has been exceeded; MLSS lies between current and previous stage."),
                highlight: L10n.t("👉 若乳酸仍稳定可继续 +10W，或改日继续测试", "👉 If stable, continue +10W or continue on another day")
            )

            emphasisCard(
                title: L10n.t("⚙️ 测试提示", "⚙️ Test Tips"),
                body: L10n.t("建议使用 ERG 模式、保持功率稳定，并避免功率波动影响乳酸值。", "Use ERG mode, keep power steady, and avoid fluctuations that perturb lactate values."),
                highlight: L10n.t("🎯 该协议通常可将 MLSS 定位至 ±10W；后续可用更小增量提精度", "🎯 This protocol typically locates MLSS within ±10W; use smaller increments later for higher precision")
            )
        }
    }

    private var fullRampProtocolCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("🧪 Protocol 1", "🧪 Protocol 1"))
                .font(.headline)
            Text(L10n.t("全递增乳酸测试", "Full Ramp Lactate Test"))
                .font(.title3.weight(.semibold))

            simpleInlineInfoCard(
                title: L10n.t("📌 测试目的", "📌 Purpose"),
                description: L10n.t(
                    "了解整体乳酸曲线、有氧能力变化趋势，以及 LT1 / LT2 的大致位置。",
                    "Understand the full lactate curve, aerobic trend changes, and approximate LT1/LT2 positions."
                )
            )

            simpleInlineInfoCard(
                title: L10n.t("适用场景", "Best For"),
                description: L10n.t(
                    "✔️ 第一次乳酸测试\n✔️ 长时间未测试\n✔️ 了解整体代谢状态",
                    "✔️ First lactate test\n✔️ Long gap since last test\n✔️ Overall metabolic status review"
                )
            )

            simpleInlineInfoCard(
                title: L10n.t("⏱ 测试时长", "⏱ Duration"),
                description: L10n.t("约 1 小时 + 冷身，通常需要 9–13 次乳酸采样。", "About 1 hour + cooldown, typically 9–13 lactate samples.")
            )

            fullRampSchematic

            stepCard(
                number: "1",
                title: L10n.t("热身", "Warm-up"),
                points: [
                    L10n.t("低强度骑行 15 分钟，建议从约 40% FTP 开始。", "Ride easy for 15 minutes, starting around 40% FTP."),
                    L10n.t("目的：避免起点过高错过 LT1。", "Goal: avoid starting too high and missing LT1.")
                ]
            )

            stepCard(
                number: "2",
                title: L10n.t("热身末采样", "End-Warmup Sample"),
                points: [
                    L10n.t("在第 10–14 分钟进行一次乳酸采样并记录功率。", "Take one lactate sample at minute 10–14 and record power.")
                ]
            )

            stepCard(
                number: "3",
                title: L10n.t("进入递增阶段", "Start Ramp Stages"),
                points: [
                    L10n.t("每阶段持续 6 分钟，第 5 分钟采血。", "Each stage lasts 6 minutes; sample at minute 5.")
                ]
            )

            stepCard(
                number: "4",
                title: L10n.t("功率递增", "Increase Power"),
                points: [
                    L10n.t("每阶段增加约 10% FTP，并持续记录功率与乳酸值。", "Increase by ~10% FTP per stage and keep logging power + lactate.")
                ]
            )

            stepCard(
                number: "5",
                title: L10n.t("停止条件", "Stop Conditions"),
                points: [
                    L10n.t("🛑 乳酸 > 6 mmol/L，或 🛑 心率 > 95% 最大心率时立即停止。", "🛑 Stop immediately if lactate > 6 mmol/L or HR > 95% max HR.")
                ]
            )

            emphasisCard(
                title: L10n.t("🧠 测试提示", "🧠 Practical Tips"),
                body: L10n.t("建议 ERG 模式保持稳定功率；坐姿/站姿全程一致；若乳酸跳升 > 2 mmol 建议复测。", "Use ERG mode for stable power; keep posture consistent; retest if lactate jumps > 2 mmol."),
                highlight: L10n.t("👉 单人测试可在阶段末短暂停止采血，6 分钟阶段仍稳定", "👉 Solo test can pause briefly for sampling at stage end without losing 6-min stage stability")
            )

            simpleInlineInfoCard(
                title: L10n.t("📊 结果用途", "📊 Result Usage"),
                description: L10n.t(
                    "用于观察乳酸曲线形态、代谢变化趋势和训练效果。\n⚠️ 不用于精准确定阈值功率。",
                    "Used to observe lactate curve shape, metabolic trends, and training effects.\n⚠️ Not for precise threshold power determination."
                )
            )
        }
    }

    private var mlssSchematic: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("示意图", "Schematic"))
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 6) {
                mlssStageBlock(title: L10n.t("Stage 1", "Stage 1"), subtitle: L10n.t("~10W 低于估算 MLSS", "~10W below estimated MLSS"))
                mlssStageBlock(title: L10n.t("Stage 2", "Stage 2"), subtitle: L10n.t("+10W", "+10W"))
                mlssStageBlock(title: L10n.t("Stage 3", "Stage 3"), subtitle: L10n.t("+10W", "+10W"))
            }

            Text(L10n.t("每个 Stage 10 分钟；第 3 分钟与第 9 分钟各采样 1 次。", "Each stage is 10 minutes; sample once at minute 3 and minute 9."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func mlssStageBlock(title: String, subtitle: String) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                Text("3m")
                    .font(.caption2)
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("9m")
                    .font(.caption2)
                Circle().fill(Color.red).frame(width: 8, height: 8)
            }
            Rectangle()
                .fill(Color.teal.opacity(0.75))
                .frame(height: 42)
                .overlay(
                    VStack(spacing: 2) {
                        Text(subtitle)
                            .font(.caption2.weight(.semibold))
                        Text("10 min")
                            .font(.caption2)
                    }
                )
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private var fullRampSchematic: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("示意图", "Schematic"))
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .bottom, spacing: 4) {
                rampBlock(label: "40%", height: 28)
                rampBlock(label: "50%", height: 34)
                rampBlock(label: "60%", height: 40)
                rampBlock(label: "70%", height: 46)
                rampBlock(label: "80%", height: 52)
                rampBlock(label: "90%", height: 58)
                rampBlock(label: "100%", height: 64)
                rampBlock(label: "110%", height: 70)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(L10n.t("15 分钟热身（40% FTP）→ 每 6 分钟 +10% FTP，阶段第 5 分钟采血。", "15-min warm-up (40% FTP) → +10% FTP every 6 minutes, sample at minute 5 of each stage."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func rampBlock(label: String, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(Color.teal.opacity(0.75))
                .frame(width: 44, height: height)
                .overlay(
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                )
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func simpleInlineInfoCard(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var historyTestView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if historyRecords.isEmpty {
                    ContentUnavailableView(
                        L10n.t("暂无历史测试结果", "No historical test results"),
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text(L10n.t("完成乳酸测试后，历史结果会在这里展示。", "History appears here after completing lactate tests."))
                    )
                } else {
                    ForEach(historyRecords.reversed()) { record in
                        sectionCard(title: "\(record.type.title) · \(record.tester)", icon: "chart.xyaxis.line") {
                            Text("\(L10n.t("测试人", "Tester")): \(record.tester)    \(L10n.t("测试类型", "Type")): \(record.type.title)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Chart(record.points) { point in
                                LineMark(
                                    x: .value("Power", point.power),
                                    y: .value("Lactate", point.lactate)
                                )
                                .foregroundStyle(.orange)

                                PointMark(
                                    x: .value("Power", point.power),
                                    y: .value("Lactate", point.lactate)
                                )
                                .foregroundStyle(.orange)
                            }
                            .frame(height: 220)
                            .chartXAxisLabel("Power (W)")
                            .chartYAxisLabel("Lactate (mmol/L)")
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func appendDraftPoint() {
        guard let power = Double(draftPower), let lactate = Double(draftLactate) else { return }
        draftPoints.append(LactateSamplePoint(power: power, lactate: lactate))
        draftPoints.sort { $0.power < $1.power }
        draftPower = ""
        draftLactate = ""
    }

    private func saveHistoryRecord() {
        let name = store.selectedAthleteNameForWrite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, draftPoints.count >= 2 else { return }
        historyRecords.append(
            LactateHistoryRecord(
                tester: name,
                type: selectedHistoryType,
                createdAt: .now,
                points: draftPoints
            )
        )
        selectedHistoryType = .ramp
        draftPoints = []
    }
}
