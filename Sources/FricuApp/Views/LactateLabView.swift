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
                return "所需材料"
            case .bloodSampling:
                return "如何采血"
            case .preTestNutrition:
                return "测前营养"
            case .aerobicPath:
                return "有氧测试"
            case .anaerobicPath:
                return "无氧能力和清除测试"
            case .sharedInterpretation:
                return "统一结果解释"
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

    @State private var selectedTab: LabTab = .latest
    @State private var selectedNode: DecisionNode = .materials
    @State private var showChecklistMode = false

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
            simpleDetailCard(
                title: L10n.t("采血说明", "Blood Sampling Guide"),
                description: L10n.t(
                    "点击后将进入采血步骤页：包含手指加温、第一滴弃样、采样时机与污染规避。",
                    "Open blood sampling steps: finger warming, first-drop discard, timing, and contamination control."
                )
            )
        case .preTestNutrition:
            simpleDetailCard(
                title: L10n.t("测前营养", "Pre-Test Nutrition"),
                description: L10n.t(
                    "点击后将进入测前营养页：包含测试前 24 小时碳水、咖啡因和补水一致性策略。",
                    "Open pre-test nutrition: 24-hour carbohydrate, caffeine, and hydration consistency strategy."
                )
            )
        case .aerobicPath:
            simpleDetailCard(
                title: L10n.t("有氧测试路径", "Aerobic Pathway"),
                description: L10n.t(
                    "• Full ramp test\n• Maximal lactate steady state\n\n最终统一汇总到结果解释。",
                    "• Full ramp test\n• Maximal lactate steady state\n\nResults are merged into Shared Interpretation."
                )
            )
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
                body: L10n.t("• 智能骑行台\nor\n• 配功率计的自行车", "• Smart trainer\nor\n• Bike with power meter")
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
                title: "ERG Mode Software",
                body: "e.g.\n• Zwift\n• TrainerRoad"
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

    private var setupDetailCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            equipmentCard(
                title: "Indoor Trainer with Power",
                body: "• Smart trainer\nor\n• Bike with power meter"
            )

            equipmentCard(
                title: "Lactate Analyzer",
                body: "Recommended:\nLactate Pro 2\n\n• Easy to use\n• No calibration needed\n• Works with small blood samples\n• Low error rate"
            )

            equipmentCard(
                title: "Lactate Test Strips",
                body: "Must be compatible with your analyzer"
            )

            equipmentCard(
                title: "Safety Lancets",
                body: "Tip for beginners:\nUse lower gauge lancets\n→ Helps produce larger blood drops"
            )

            equipmentCard(title: "Alcohol Swabs", body: "")

            equipmentCard(
                title: "Support Items",
                body: "• Tissues\n• Towel (to remove sweat)"
            )

            equipmentCard(
                title: "Timer",
                body: "(e.g. phone)"
            )

            equipmentCard(
                title: "Results Recording",
                body: "• Notebook\n• Laptop\n• Spreadsheet\n\nUse our Results Template"
            )

            Text("推荐设备（可选）")
                .font(.headline)
                .padding(.top, 4)

            equipmentCard(
                title: "ERG Mode Software",
                body: "e.g.\n• Zwift\n• TrainerRoad"
            )

            equipmentCard(
                title: "Helper (recommended)",
                body: "Disposable gloves advised\nAvoid latex\nUse nitrile instead"
            )
        }
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pre-Test Checklist")
                .font(.headline)

            Group {
                Text("☑ Trainer ready")
                Text("☑ Analyzer ready")
                Text("☑ Strips available")
                Text("☑ Lancets prepared")
                Text("☑ Alcohol swabs ready")
                Text("☑ Timer ready")
                Text("☑ Recording method ready")
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
