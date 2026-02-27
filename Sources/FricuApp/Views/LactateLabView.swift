import SwiftUI

struct LactateLabView: View {
    private enum LabTab: String, CaseIterable, Identifiable {
        case latest
        case history

        var id: String { rawValue }

        var title: String {
            switch self {
            case .latest:
                return "最新测试"
            case .history:
                return "历史测试结果"
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
            Text("乳酸实验室")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))

            Picker("页面", selection: $selectedTab) {
                ForEach(LabTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
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
                colors: [Color(.systemGray6), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var latestTestView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionCard(title: "决策树", icon: "point.topleft.down.curvedto.point.bottomright.up") {
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
                title: "Blood Sampling Guide",
                description: "点击后将进入采血步骤页：包含手指加温、第一滴弃样、采样时机与污染规避。"
            )
        case .preTestNutrition:
            simpleDetailCard(
                title: "Pre-Test Nutrition",
                description: "点击后将进入测前营养页：包含测试前 24 小时碳水、咖啡因和补水一致性策略。"
            )
        case .aerobicPath:
            simpleDetailCard(
                title: "Aerobic Pathway",
                description: "• Full ramp test\n• Maximal lactate steady state\n\n最终统一汇总到结果解释。"
            )
        case .anaerobicPath:
            simpleDetailCard(
                title: "Anaerobic + Clearance Pathway",
                description: "• 清除能力评估\n• 重复冲刺恢复评估\n\n最终统一汇总到结果解释。"
            )
        case .sharedInterpretation:
            simpleDetailCard(
                title: "统一结果解释",
                description: "所有测试数据会统一汇总到同一份“结果解释”中，便于对比有氧与无氧能力，并生成后续训练建议。"
            )
        }
    }

    private var setupMaterialsView: some View {
        sectionCard(title: "🧪 Lactate Test Setup", icon: "checklist") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Before You Start")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Lactate Test Setup")
                    .font(.title2.weight(.bold))

                Picker("模式", selection: $showChecklistMode) {
                    Text("Setup").tag(false)
                    Text("Checklist").tag(true)
                }
                .pickerStyle(.segmented)

                if showChecklistMode {
                    checklistCard
                } else {
                    setupDetailCards
                }

                Text("Lactate testing is a controlled experiment.\n\nPreparation matters more than intensity.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Text("Turn your training into physiology insight.\n\nSet up your lactate test environment before you begin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    .fill(selectedNode == node ? Color.teal : Color(.secondarySystemBackground))
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            "暂无历史测试结果",
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            description: Text("完成乳酸测试后，历史结果会在这里展示。")
        )
    }
}
