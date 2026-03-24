import SwiftUI

struct DashboardWorkspaceView: View {
    private enum DashboardWorkspaceTab: String, CaseIterable, Identifiable {
        case overview
        case insights

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview:
                return L10n.choose(simplifiedChinese: "概览", english: "Overview")
            case .insights:
                return L10n.choose(simplifiedChinese: "洞察", english: "Insights")
            }
        }
    }

    @State private var selectedTab: DashboardWorkspaceTab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L10n.choose(simplifiedChinese: "仪表盘内容", english: "Dashboard Content"), selection: $selectedTab) {
                ForEach(DashboardWorkspaceTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 6)

            Group {
                switch selectedTab {
                case .overview:
                    DashboardView()
                case .insights:
                    InsightsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
