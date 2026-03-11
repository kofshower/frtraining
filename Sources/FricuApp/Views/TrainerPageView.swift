import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    @State private var expandedSteps: Set<Int> = [2]

    private var visibleSessions: [TrainerRiderSession] {
        store.trainerRiderSessionsForSelectedAthlete
    }

    private var primarySession: TrainerRiderSession? {
        visibleSessions.first
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

                Text("单运动员训练流：当前账号仅保留一个骑行会话，不支持并行骑手。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                GroupBox(L10n.choose(simplifiedChinese: "骑行台流程", english: "Trainer Workflow")) {
                    VStack(alignment: .leading, spacing: 12) {
                        trainerFlowSection(
                            step: 1,
                            title: L10n.choose(simplifiedChinese: "确认当前账号", english: "Confirm Account"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "当前运动员：\(store.selectedAthleteTitle)。",
                                english: "Current athlete: \(store.selectedAthleteTitle)."
                            ),
                            state: visibleSessions.isEmpty ? .pending : .done
                        ) {
                            flowDetailContainer {
                                Text(
                                    L10n.choose(
                                        simplifiedChinese: "账号与运动员一一对应，本流程中的设备连接、训练控制、录制与 FIT 保存都归属当前账号。",
                                        english: "Account and athlete are 1:1. Device connection, control, recording, and FIT persistence in this flow all belong to the current account."
                                    )
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }

                        trainerFlowSection(
                            step: 2,
                            title: L10n.choose(simplifiedChinese: "连接设备", english: "Connect Devices"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "骑行台 \(connectedTrainerCount)/\(visibleSessions.count) · 心率 \(connectedHeartRateCount)/\(visibleSessions.count) · 功率计 \(connectedPowerMeterCount)/\(visibleSessions.count)",
                                english: "Trainer \(connectedTrainerCount)/\(visibleSessions.count) · HR \(connectedHeartRateCount)/\(visibleSessions.count) · Power meter \(connectedPowerMeterCount)/\(visibleSessions.count)"
                            ),
                            state: connectionStepState
                        ) {
                            flowDetailContainer {
                                if let session = primarySession {
                                    HeartRateControlPanel(monitor: session.heartRateMonitor)
                                    PowerMeterControlPanel(powerMeter: session.powerMeter)
                                } else {
                                    ContentUnavailableView(
                                        L10n.choose(simplifiedChinese: "当前账号无可用设备会话", english: "No available device session"),
                                        systemImage: "bolt.horizontal.circle"
                                    )
                                }
                            }
                        }

                        trainerFlowSection(
                            step: 3,
                            title: L10n.choose(simplifiedChinese: "设置训练控制", english: "Configure Control"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "已配置 \(configuredControlCount)/\(visibleSessions.count)（ERG/坡度/课程仿真）。",
                                english: "Configured \(configuredControlCount)/\(visibleSessions.count) sessions (ERG/grade/simulation)."
                            ),
                            state: setupStepState
                        ) {
                            flowDetailContainer {
                                if let session = primarySession {
                                    TrainerControlPanel(session: session)
                                } else {
                                    ContentUnavailableView(
                                        L10n.choose(simplifiedChinese: "当前账号无骑行台会话", english: "No trainer session for current account"),
                                        systemImage: "person.crop.circle.badge.exclamationmark"
                                    )
                                }
                            }
                        }

                        trainerFlowSection(
                            step: 4,
                            title: L10n.choose(simplifiedChinese: "开始训练与录制", english: "Ride and Record"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "录制中 \(activeRecordingCount) 人 · 实时遥测可用 \(telemetryReadyCount) 人。",
                                english: "Recording \(activeRecordingCount) session(s) · Live telemetry ready for \(telemetryReadyCount) session(s)."
                            ),
                            state: rideStepState
                        ) {
                            flowDetailContainer {
                                #if os(iOS)
                                if UIDevice.current.userInterfaceIdiom == .pad {
                                    TrainerIPadCapturePanel()
                                }
                                #endif
                                Text(
                                    L10n.choose(
                                        simplifiedChinese: "录制入口已嵌入在上一步“设置训练控制”卡片中。开始骑行后，这里会同步显示状态。",
                                        english: "Recording controls are embedded in the previous Configure Control card. Status here updates in sync after ride start."
                                    )
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }

                        trainerFlowSection(
                            step: 5,
                            title: L10n.choose(simplifiedChinese: "保存 FIT 与同步服务端", english: "Persist FIT and Sync"),
                            subtitle: L10n.choose(
                                simplifiedChinese: "已生成 FIT \(fitReadyCount) 份 · 已同步/入队 \(syncedFitCount) 份。",
                                english: "FIT generated: \(fitReadyCount) · Synced/queued: \(syncedFitCount)."
                            ),
                            state: saveStepState
                        ) {
                            flowDetailContainer {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("FIT: \(store.trainerRecordingLastFitPath ?? "-")")
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text("Sync: \(store.trainerRecordingLastSyncSummary ?? "-")")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("记录状态会同步到全局状态栏，并自动写入 FIT。")
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
    private func trainerFlowSection<Content: View>(
        step: Int,
        title: String,
        subtitle: String,
        state: TrainerWorkflowState,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let expanded = expandedSteps.contains(step)
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if expanded {
                        expandedSteps.remove(step)
                    } else {
                        expandedSteps.insert(step)
                    }
                }
            } label: {
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
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if expanded {
                content()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            }
        }
    }

    @ViewBuilder
    private func flowDetailContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
