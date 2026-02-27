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

    @State private var selectedTab: LabTab = .latest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("乳酸实验室")
                .font(.title2.bold())

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
        .padding()
    }

    private var latestTestView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("决策树")
                    .font(.headline)

                Text("所需材料")
                Text("↓")
                Text("如何采血")
                Text("↓")
                Text("测前营养")
                Text("↓")

                Text("测试路径")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("→ 有氧测试")
                        .font(.headline)
                    Text("    ↳ Full ramp test")
                    Text("    ↳ Maximal lactate steady state")
                    Text("    ↳ 结果解释")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("→ 无氧能力和清除测试")
                        .font(.headline)
                    Text("    ↳ 结果解释")
                }

                Text("说明：有氧测试与无氧能力和清除测试最终都汇总到“结果解释”。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var historyTestView: some View {
        ContentUnavailableView(
            "暂无历史测试结果",
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            description: Text("完成乳酸测试后，历史结果会在这里展示。")
        )
    }
}
