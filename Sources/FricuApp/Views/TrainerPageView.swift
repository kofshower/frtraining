import SwiftUI

struct TrainerPageView: View {
    @EnvironmentObject private var store: AppStore
    @State private var riderNameDraftByID: [UUID: String] = [:]

    private func persistAllRiderNameDrafts() {
        for session in store.trainerRiderSessions {
            let draft = riderNameDraftByID[session.id] ?? session.name
            store.renameTrainerRiderSession(id: session.id, to: draft)
        }
    }

    private func bindingForRiderName(_ session: TrainerRiderSession) -> Binding<String> {
        Binding<String>(
            get: { riderNameDraftByID[session.id] ?? session.name },
            set: { next in
                riderNameDraftByID[session.id] = next
                // Persist eagerly so rider name is not lost when switching pages without pressing Enter.
                store.renameTrainerRiderSession(id: session.id, to: next)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Trainer")
                        .font(.largeTitle.bold())
                    Spacer()
                    Button("Add Rider") {
                        store.addTrainerRiderSession()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("支持多骑手并行训练：每位骑手独立连接骑行台、心率表、功率计。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(store.trainerRiderSessions) { session in
                    let isPrimary = session.id == store.primaryTrainerSessionID
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("Rider Name", text: bindingForRiderName(session))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                                .onSubmit {
                                    let current = riderNameDraftByID[session.id] ?? session.name
                                    store.renameTrainerRiderSession(id: session.id, to: current)
                                }

                            if isPrimary {
                                Text("Primary")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.blue.opacity(0.14), in: Capsule())
                            }

                            Spacer()

                            if !isPrimary {
                                Button("Remove Rider", role: .destructive) {
                                    store.removeTrainerRiderSession(id: session.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        HeartRateControlPanel(monitor: session.heartRateMonitor)
                        PowerMeterControlPanel(powerMeter: session.powerMeter)
                        TrainerControlPanel(session: session)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                }
                Text("每位骑手可独立录制并保存 FIT；主骑手状态会同步到全局状态栏。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .onAppear {
            for session in store.trainerRiderSessions {
                if riderNameDraftByID[session.id] == nil {
                    riderNameDraftByID[session.id] = session.name
                }
            }
            store.ensureTrainerRiderAutoReconnect()
        }
        .onChange(of: store.trainerRiderSessions.map(\.id)) { _, _ in
            for session in store.trainerRiderSessions {
                if riderNameDraftByID[session.id] == nil {
                    riderNameDraftByID[session.id] = session.name
                }
            }
            let validIDs = Set(store.trainerRiderSessions.map(\.id))
            riderNameDraftByID = riderNameDraftByID.filter { validIDs.contains($0.key) }
            store.ensureTrainerRiderAutoReconnect()
        }
        .onChange(of: store.trainerRiderSessions.map { "\($0.id.uuidString)|\($0.name)" }) { _, _ in
            for session in store.trainerRiderSessions {
                riderNameDraftByID[session.id] = session.name
            }
        }
        .onDisappear {
            persistAllRiderNameDrafts()
        }
    }
}
