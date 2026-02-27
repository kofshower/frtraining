import SwiftUI

struct LactateLabView: View {
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

    @State private var selectedTab: LabTab = .latest
    @State private var selectedNode: DecisionNode = .materials
    @State private var showChecklistMode = false
    @State private var selectedAerobicTest: AerobicTest? = nil

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
                sectionCard(title: L10n.t("决策树", "Decision Tree"), icon: "point.topleft.down.curvedto.point.bottomright.up") {
                    VStack(alignment: .leading, spacing: 10) {
                        decisionNodeButton(.materials)
                        flowArrow
                        decisionNodeButton(.bloodSampling)
                        flowArrow
                        decisionNodeButton(.preTestNutrition)

                        Divider().padding(.vertical, 6)

                        decisionNodeButton(.aerobicPath)
                        decisionNodeButton(.anaerobicPath)
                        decisionNodeButton(.sharedInterpretation)
                    }
                }

                selectedNodeContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
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
            aerobicPathwayView
        case .anaerobicPath:
            simpleDetailCard(
                title: L10n.t("无氧与清除路径", "Anaerobic + Clearance Pathway"),
                description: L10n.t(
                    "• 清除能力评估\n• 重复冲刺恢复评估\n\n最终统一汇总到结果解释。",
                    "• Clearance capacity assessment\n• Repeated sprint recovery assessment\n\nResults are merged into Shared Interpretation."
                )
            )
        case .sharedInterpretation:
            simpleDetailCard(
                title: L10n.t("统一结果解释", "Shared Interpretation"),
                description: L10n.t(
                    "所有测试数据会统一汇总到同一份“结果解释”中，便于对比有氧与无氧能力，并生成后续训练建议。",
                    "All test data is consolidated into one interpretation report for aerobic/anaerobic comparison and follow-up training suggestions."
                )
            )
        }
    }

    private var aerobicPathwayView: some View {
        sectionCard(title: L10n.t("有氧测试路径", "Aerobic Pathway"), icon: "lungs.fill") {
            VStack(alignment: .leading, spacing: 10) {
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
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedAerobicTest == test ? Color.teal : Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let selectedAerobicTest {
                    simpleInlineInfoCard(
                        title: selectedAerobicTest.title,
                        description: selectedAerobicTest.summary
                    )
                }

                Text(L10n.t("最终统一汇总到结果解释。", "Results are merged into Shared Interpretation."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
        ContentUnavailableView(
            L10n.t("暂无历史测试结果", "No historical test results"),
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            description: Text(L10n.t("完成乳酸测试后，历史结果会在这里展示。", "History appears here after completing lactate tests."))
        )
    }
}
