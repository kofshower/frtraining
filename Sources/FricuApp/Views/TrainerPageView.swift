import SwiftUI

struct TrainerPageView: View {
    @EnvironmentObject private var store: AppStore

    private var visibleSessions: [TrainerRiderSession] {
        store.trainerRiderSessionsForSelectedAthlete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Trainer")
                    .font(.largeTitle.bold())

                Text("支持多骑手并行训练：每位骑手独立连接骑行台、心率表、功率计。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("运动员切换统一使用顶部下拉框。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("新增/删除运动员面板请在 Settings 的 Athlete Panel Management 中操作。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if visibleSessions.isEmpty {
                    ContentUnavailableView(
                        L10n.choose(simplifiedChinese: "当前运动员无骑行台会话", english: "No trainer rider for selected athlete"),
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                } else {
                    ForEach(visibleSessions) { session in
                        let isPrimary = session.id == store.primaryTrainerSessionID
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text(session.name)
                                    .font(.headline)

                                if isPrimary {
                                    Text("Primary")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.blue.opacity(0.14), in: Capsule())
                                }

                                Spacer()
                            }

                            HeartRateControlPanel(monitor: session.heartRateMonitor)
                            PowerMeterControlPanel(powerMeter: session.powerMeter)
                            TrainerControlPanel(session: session)
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Text("每位骑手可独立录制并保存 FIT；主骑手状态会同步到全局状态栏。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .onAppear {
            store.ensureTrainerRiderAutoReconnect()
        }
        .onChange(of: store.trainerRiderSessions.map(\.id)) { _, _ in
            store.ensureTrainerRiderAutoReconnect()
        }
    }
}
