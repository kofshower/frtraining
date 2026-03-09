import SwiftUI

private enum TrainerWorkflowState {
    case pending
    case running
    case blocked
    case ready
    case done

    var symbol: String {
        switch self {
        case .pending:
            return "circle"
        case .running:
            return "clock.arrow.circlepath"
        case .blocked:
            return "xmark.octagon.fill"
        case .ready:
            return "bolt.circle.fill"
        case .done:
            return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .running:
            return .blue
        case .blocked:
            return .orange
        case .ready:
            return .teal
        case .done:
            return .green
        }
    }
}

struct TrainerPageView: View {
    @EnvironmentObject private var store: AppStore

    private var visibleSessions: [TrainerRiderSession] {
        store.trainerRiderSessionsForSelectedAthlete
    }

    private var connectedTrainerCount: Int {
        visibleSessions.filter { $0.trainer.isConnected }.count
    }

    private var connectedHeartRateCount: Int {
        visibleSessions.filter { $0.heartRateMonitor.isConnected }.count
    }

    private var connectedPowerMeterCount: Int {
        visibleSessions.filter { $0.powerMeter.isConnected }.count
    }

    private var configuredControlCount: Int {
        visibleSessions.filter {
            $0.trainer.ergTargetWatts != nil ||
            $0.trainer.targetGradePercent != nil ||
            $0.trainer.programPhase != nil ||
            $0.trainer.simulationActivityName != nil
        }.count
    }

    private var telemetryReadyCount: Int {
        visibleSessions.filter {
            $0.trainer.livePowerWatts != nil ||
            $0.powerMeter.livePowerWatts != nil ||
            $0.heartRateMonitor.liveHeartRateBPM != nil
        }.count
    }

    private var activeRecordingCount: Int {
        visibleSessions.filter { store.trainerRecordingStatus(for: $0.id).isActive }.count
    }

    private var fitReadyCount: Int {
        visibleSessions.filter { hasMeaningfulValue(store.trainerRecordingStatus(for: $0.id).lastFitPath) }.count
    }

    private var syncedFitCount: Int {
        visibleSessions.filter { hasMeaningfulValue(store.trainerRecordingStatus(for: $0.id).lastSyncSummary) }.count
    }

    private var athleteSelectionStepState: TrainerWorkflowState {
        if visibleSessions.isEmpty { return .pending }
        return store.isAllAthletesSelected ? .ready : .done
    }

    private var connectionStepState: TrainerWorkflowState {
        guard !visibleSessions.isEmpty else { return .pending }
        if connectedTrainerCount == 0 && connectedHeartRateCount == 0 && connectedPowerMeterCount == 0 {
            return .ready
        }
        return connectedTrainerCount == visibleSessions.count ? .done : .running
    }

    private var setupStepState: TrainerWorkflowState {
        guard !visibleSessions.isEmpty else { return .pending }
        guard connectedTrainerCount > 0 else { return .blocked }
        if configuredControlCount == 0 { return .ready }
        return configuredControlCount == visibleSessions.count ? .done : .running
    }

    private var rideStepState: TrainerWorkflowState {
        guard !visibleSessions.isEmpty else { return .pending }
        guard connectedTrainerCount > 0 else { return .blocked }
        if activeRecordingCount > 0 { return .running }
        if fitReadyCount > 0 { return .done }
        if telemetryReadyCount > 0 { return .ready }
        return .pending
    }

    private var saveStepState: TrainerWorkflowState {
        guard !visibleSessions.isEmpty else { return .pending }
        if activeRecordingCount > 0 { return .running }
        if syncedFitCount > 0 { return .done }
        if fitReadyCount > 0 { return .ready }
        return connectedTrainerCount > 0 ? .pending : .blocked
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

                GroupBox(L10n.choose(simplifiedChinese: "骑行台流程", english: "Trainer Workflow")) {
                    VStack(alignment: .leading, spacing: 12) {
                        trainerFlowCard(
                            step: 1,
                            title: L10n.choose(simplifiedChinese: "选择运动员", english: "Select Athlete"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "当前：\(store.selectedAthleteTitle)。建议锁定单个运动员后再执行后续流程。",
                                english: "Current: \(store.selectedAthleteTitle). Select a specific athlete panel before proceeding."
                            ),
                            state: athleteSelectionStepState
                        )

                        trainerFlowCard(
                            step: 2,
                            title: L10n.choose(simplifiedChinese: "连接设备", english: "Connect Devices"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "骑行台 \(connectedTrainerCount)/\(visibleSessions.count) · 心率 \(connectedHeartRateCount)/\(visibleSessions.count) · 功率计 \(connectedPowerMeterCount)/\(visibleSessions.count)",
                                english: "Trainer \(connectedTrainerCount)/\(visibleSessions.count) · HR \(connectedHeartRateCount)/\(visibleSessions.count) · Power meter \(connectedPowerMeterCount)/\(visibleSessions.count)"
                            ),
                            state: connectionStepState
                        )

                        trainerFlowCard(
                            step: 3,
                            title: L10n.choose(simplifiedChinese: "设置训练控制", english: "Configure Control"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "已配置 \(configuredControlCount)/\(visibleSessions.count)（ERG/坡度/课程仿真）。",
                                english: "Configured \(configuredControlCount)/\(visibleSessions.count) sessions (ERG/grade/simulation)."
                            ),
                            state: setupStepState
                        )

                        trainerFlowCard(
                            step: 4,
                            title: L10n.choose(simplifiedChinese: "开始训练与录制", english: "Ride and Record"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "录制中 \(activeRecordingCount) 人 · 实时遥测可用 \(telemetryReadyCount) 人。",
                                english: "Recording \(activeRecordingCount) session(s) · Live telemetry ready for \(telemetryReadyCount) session(s)."
                            ),
                            state: rideStepState
                        )

                        trainerFlowCard(
                            step: 5,
                            title: L10n.choose(simplifiedChinese: "保存 FIT 与同步服务端", english: "Persist FIT and Sync"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "已生成 FIT \(fitReadyCount) 份 · 已同步/入队 \(syncedFitCount) 份。",
                                english: "FIT generated: \(fitReadyCount) · Synced/queued: \(syncedFitCount)."
                            ),
                            state: saveStepState
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

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

    @ViewBuilder
    private func trainerFlowCard(
        step: Int,
        title: String,
        subtitle: String,
        state: TrainerWorkflowState
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(step)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 18, height: 18)
                    .background(state.color.opacity(0.16), in: Circle())
                    .foregroundStyle(state.color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(trainerFlowStateLabel(state), systemImage: state.symbol)
                    .font(.caption)
                    .foregroundStyle(state.color)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func trainerFlowStateLabel(_ state: TrainerWorkflowState) -> String {
        switch state {
        case .pending:
            return L10n.choose(simplifiedChinese: "待执行", english: "Pending")
        case .running:
            return L10n.choose(simplifiedChinese: "执行中", english: "Running")
        case .blocked:
            return L10n.choose(simplifiedChinese: "已阻止", english: "Blocked")
        case .ready:
            return L10n.choose(simplifiedChinese: "可执行", english: "Ready")
        case .done:
            return L10n.choose(simplifiedChinese: "已完成", english: "Done")
        }
    }

    private func hasMeaningfulValue(_ text: String?) -> Bool {
        guard let text else { return false }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty && normalized != "-"
    }
}
