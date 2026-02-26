import SwiftUI
import Charts

private enum LactateProtocolType: String, Codable, CaseIterable, Identifiable {
    case fullRamp
    case mlss
    case anaerobicClearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullRamp:
            return L10n.choose(simplifiedChinese: "Full Ramp", english: "Full Ramp")
        case .mlss:
            return "MLSS"
        case .anaerobicClearance:
            return L10n.choose(simplifiedChinese: "Anaerobic + Clearance", english: "Anaerobic + Clearance")
        }
    }

    var recommendation: String {
        switch self {
        case .fullRamp:
            return L10n.choose(simplifiedChinese: "第一次测试建议从 Full Ramp 开始", english: "First-time users should start with Full Ramp.")
        case .mlss:
            return L10n.choose(simplifiedChinese: "如需精确阈值，请使用 MLSS", english: "Use MLSS when you need precise threshold estimation.")
        case .anaerobicClearance:
            return L10n.choose(simplifiedChinese: "用于评估无氧能力与乳酸清除", english: "Use to evaluate anaerobic capacity and lactate clearance.")
        }
    }
}

private enum LactateSessionStatus: String, Codable {
    case notStarted
    case inProgress
    case completed
}

private struct LactatePreconditions: Codable {
    var riderName: String = ""
    var ftp: Int = 240
    var maxHR: Int = 190
    var weightKg: Double?
    var powerSource: String = "Smart Trainer"
    var usesERGMode: Bool = true
    var analyzerModel: String = ""
    var hasAssistant: Bool = false
    var minutesSinceCalories: Int = 90
    var drinkType: String = "Water"
    var caffeineStatus: String = "Normal"
    var fatigueLevel: Int = 2
    var sleepHours: Double = 7.5
    var selfTestMode: Bool = true
}

private struct LactateStageRecord: Identifiable, Codable {
    var id = UUID()
    var stageIndex: Int
    var stageType: String
    var targetPower: Int
    var durationMinutes: Int = 4
    var sampleHint: String = "阶段末 30 秒采样"
    var avgPower: Int?
    var avgHR: Int?
    var posture: String = "Seated"
    var rpe: Int = 5
    var note: String = ""
}

private struct LactateSample: Identifiable, Codable {
    var id = UUID()
    var stageIndex: Int
    var timestamp: Date
    var value: Double
    var isRetest: Bool
    var suspectedContamination: Bool
    var note: String
}

private struct LactateDerivedMetrics: Codable {
    var lt1Estimate: Int?
    var lt2Estimate: Int?
    var mlssLowerBound: Int?
    var mlssUpperBound: Int?
    var baselineLactate: Double?
    var peakLactate: Double?
    var vlaMax: Double?
    var drop20MinPct: Double?
    var clearanceRate: Double?
}

private struct LactateTestSession: Identifiable, Codable {
    var id = UUID()
    var createdAt = Date()
    var protocolType: LactateProtocolType
    var status: LactateSessionStatus = .notStarted
    var preconditions = LactatePreconditions()
    var stages: [LactateStageRecord] = []
    var samples: [LactateSample] = []
    var metrics = LactateDerivedMetrics()
    var checklistCompleted = false
    var checklistItems: [Bool] = Array(repeating: false, count: 4)
    var qualityFlags: [String] = []

    mutating func recalculateMetrics() {
        guard !samples.isEmpty else { return }
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        let maxValue = sorted.map(\.value).max()
        let minValue = sorted.map(\.value).min()
        metrics.baselineLactate = minValue
        metrics.peakLactate = maxValue

        switch protocolType {
        case .fullRamp:
            if let lt1Sample = sorted.first(where: { $0.value >= 2.0 }),
               let stage = stages.first(where: { $0.stageIndex == lt1Sample.stageIndex }) {
                metrics.lt1Estimate = stage.targetPower
            }
            if let lt2Sample = sorted.first(where: { $0.value >= 4.0 }),
               let stage = stages.first(where: { $0.stageIndex == lt2Sample.stageIndex }) {
                metrics.lt2Estimate = stage.targetPower
            }
        case .mlss:
            let grouped = Dictionary(grouping: sorted, by: \.stageIndex)
            let overMlss = grouped.compactMap { key, values -> Int? in
                guard values.count >= 2 else { return nil }
                let local = values.sorted { $0.timestamp < $1.timestamp }
                guard let first = local.first?.value, let last = local.last?.value else { return nil }
                return (last - first) > 1.0 ? key : nil
            }.sorted()
            if let firstOver = overMlss.first {
                metrics.mlssUpperBound = stages.first(where: { $0.stageIndex == firstOver })?.targetPower
                metrics.mlssLowerBound = stages.first(where: { $0.stageIndex == firstOver - 1 })?.targetPower
            }
        case .anaerobicClearance:
            if let peak = maxValue, let baseline = minValue {
                metrics.vlaMax = (peak - baseline) / 16.0
                if sorted.count >= 2 {
                    let first = sorted.first?.value ?? baseline
                    let last = sorted.last?.value ?? baseline
                    let durationMin = sorted.last?.timestamp.timeIntervalSince(sorted.first?.timestamp ?? Date()) ?? 1
                    let minutes = max(durationMin / 60.0, 1)
                    metrics.clearanceRate = (first - last) / minutes
                }
                if let sample20 = sorted.last(where: { Date().timeIntervalSince($0.timestamp) >= 20 * 60 }) {
                    metrics.drop20MinPct = peak == 0 ? nil : ((peak - sample20.value) / peak) * 100
                }
            }
        }
    }
}

private final class LactateLabStore: ObservableObject {
    @Published var currentSession: LactateTestSession?
    @Published var history: [LactateTestSession] = []
    @Published var defaultFTP = 240
    @Published var defaultMaxHR = 190
    @Published var defaultAnalyzerModel = ""
    @Published var defaultSelfTestMode = true
    @Published var reminderEnabled = true

    private let historyKey = "fricu.lactate.history.v1"

    init() {
        loadHistory()
    }

    func startSession(protocolType: LactateProtocolType) {
        var session = LactateTestSession(protocolType: protocolType)
        session.preconditions.ftp = defaultFTP
        session.preconditions.maxHR = defaultMaxHR
        session.preconditions.analyzerModel = defaultAnalyzerModel
        session.preconditions.selfTestMode = defaultSelfTestMode
        session.stages = defaultStages(for: protocolType, ftp: defaultFTP)
        currentSession = session
    }

    func saveCurrent() {
        guard let currentSession else { return }
        if let index = history.firstIndex(where: { $0.id == currentSession.id }) {
            history[index] = currentSession
        } else {
            history.insert(currentSession, at: 0)
        }
        persistHistory()
    }

    func completeSession() {
        guard var session = currentSession else { return }
        session.status = .completed
        session.recalculateMetrics()
        currentSession = session
        saveCurrent()
    }

    private func defaultStages(for protocolType: LactateProtocolType, ftp: Int) -> [LactateStageRecord] {
        switch protocolType {
        case .fullRamp:
            return [
                LactateStageRecord(stageIndex: 0, stageType: "Warm-up", targetPower: Int(Double(ftp) * 0.5), durationMinutes: 10, sampleHint: "热身末尾可选采样"),
                LactateStageRecord(stageIndex: 1, stageType: "Stage 1", targetPower: Int(Double(ftp) * 0.6), durationMinutes: 4),
                LactateStageRecord(stageIndex: 2, stageType: "Stage 2", targetPower: Int(Double(ftp) * 0.7), durationMinutes: 4),
                LactateStageRecord(stageIndex: 3, stageType: "Stage 3", targetPower: Int(Double(ftp) * 0.8), durationMinutes: 4),
                LactateStageRecord(stageIndex: 4, stageType: "Stage 4", targetPower: Int(Double(ftp) * 0.9), durationMinutes: 4),
                LactateStageRecord(stageIndex: 5, stageType: "Stage 5", targetPower: ftp, durationMinutes: 4),
                LactateStageRecord(stageIndex: 6, stageType: "Stage 6", targetPower: Int(Double(ftp) * 1.1), durationMinutes: 4)
            ]
        case .mlss:
            return [
                LactateStageRecord(stageIndex: 1, stageType: "MLSS Block 1", targetPower: ftp - 10, durationMinutes: 30, sampleHint: "10/20/30 分钟采样"),
                LactateStageRecord(stageIndex: 2, stageType: "MLSS Block 2", targetPower: ftp, durationMinutes: 30, sampleHint: "10/20/30 分钟采样"),
                LactateStageRecord(stageIndex: 3, stageType: "MLSS Block 3", targetPower: ftp + 10, durationMinutes: 30, sampleHint: "10/20/30 分钟采样")
            ]
        case .anaerobicClearance:
            return [
                LactateStageRecord(stageIndex: 0, stageType: "Easy Ride", targetPower: Int(Double(ftp) * 0.45), durationMinutes: 10, sampleHint: "热身后采样"),
                LactateStageRecord(stageIndex: 1, stageType: "Rest", targetPower: 0, durationMinutes: 3, sampleHint: "末尾采样"),
                LactateStageRecord(stageIndex: 2, stageType: "Sprint 20s", targetPower: Int(Double(ftp) * 1.8), durationMinutes: 1, sampleHint: "冲刺后 1 分钟采样"),
                LactateStageRecord(stageIndex: 3, stageType: "Recovery", targetPower: Int(Double(ftp) * 0.4), durationMinutes: 20, sampleHint: "每 5 分钟采样")
            ]
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        history = (try? JSONDecoder().decode([LactateTestSession].self, from: data)) ?? []
    }

    private func persistHistory() {
        let data = try? JSONEncoder().encode(history)
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}

private enum LactateFlowPage: String, CaseIterable, Identifiable {
    case hub, protocols, setup, checklist, live, results, history, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hub: return L10n.choose(simplifiedChinese: "测试首页", english: "Test Hub")
        case .protocols: return L10n.choose(simplifiedChinese: "协议总览", english: "Protocol Library")
        case .setup: return L10n.choose(simplifiedChinese: "协议设置", english: "Protocol Setup")
        case .checklist: return L10n.choose(simplifiedChinese: "测试前检查", english: "Pre-Test Checklist")
        case .live: return L10n.choose(simplifiedChinese: "实时测试", english: "Live Test")
        case .results: return L10n.choose(simplifiedChinese: "结果", english: "Results")
        case .history: return L10n.choose(simplifiedChinese: "历史", english: "History")
        case .settings: return L10n.choose(simplifiedChinese: "设置", english: "Settings")
        }
    }
}

private enum LactatePrimaryGoal: String, CaseIterable, Identifiable {
    case firstBaseline
    case preciseThreshold
    case anaerobicCapacity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstBaseline:
            return "我是第一次做乳酸测试"
        case .preciseThreshold:
            return "我要精确阈值（配速/功率区间）"
        case .anaerobicCapacity:
            return "我要评估冲刺后乳酸清除能力"
        }
    }
}

private enum LactateExperienceLevel: String, CaseIterable, Identifiable {
    case beginner
    case practiced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner:
            return "新手（采血流程不熟）"
        case .practiced:
            return "熟练（可稳定按阶段采样）"
        }
    }
}

private enum LactateReadinessState: String, CaseIterable, Identifiable {
    case fresh
    case tired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fresh:
            return "今天状态较新鲜（睡眠/疲劳可控）"
        case .tired:
            return "今天偏疲劳（恢复不充分）"
        }
    }
}

private struct LactatePathRecommendation {
    var protocolType: LactateProtocolType
    var title: String
    var why: String
    var executionPath: [String]
    var caution: String
}

private struct SetupGuideItem: Identifiable {
    let id = UUID()
    let text: String
    let isWarning: Bool
}

private struct ProtocolFocusSection: Identifiable {
    let id = UUID()
    let title: String
    let bullets: [String]
}

private struct FullRampStageVisual: Identifiable {
    let id = UUID()
    let label: String
    let width: CGFloat
    let height: CGFloat
}

private struct FullRampProtocolGraphicView: View {
    private let stages: [FullRampStageVisual] = [
        FullRampStageVisual(label: "40% FTP", width: 138, height: 44),
        FullRampStageVisual(label: "50% FTP", width: 92, height: 54),
        FullRampStageVisual(label: "60% FTP", width: 92, height: 58),
        FullRampStageVisual(label: "70% FTP", width: 92, height: 62),
        FullRampStageVisual(label: "80% FTP", width: 92, height: 66),
        FullRampStageVisual(label: "90% FTP", width: 92, height: 70),
        FullRampStageVisual(label: "100% FTP", width: 92, height: 74),
        FullRampStageVisual(label: "110% FTP", width: 92, height: 78),
        FullRampStageVisual(label: "120% FTP", width: 92, height: 82)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                            ZStack {
                                Rectangle()
                                    .fill(Color.cyan.opacity(0.75))
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.cyan.opacity(0.95), lineWidth: 1)
                                    )
                                Text(stage.label)
                                    .font(.caption)
                                    .foregroundStyle(.black.opacity(0.78))
                            }
                            .frame(width: stage.width, height: stage.height)
                            .overlay(alignment: .topTrailing) {
                                if index > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 10, height: 10)
                                        .offset(x: -8, y: -14)
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Text("15 mins @ 40% FTP")
                        Text("6 mins @ 50% FTP")
                        Text("Then +10% FTP every 5 mins")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            Text("Red dots indicate blood lactate sampling at each stage end.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TimeLactatePoint: Identifiable {
    let id = UUID()
    let minute: Int
    let value: Double
}

private struct AerobicCurveGraphicView: View {
    private let points: [LactatePowerPoint] = [
        LactatePowerPoint(power: 120, lactate: 1.1, stageIndex: 0),
        LactatePowerPoint(power: 150, lactate: 1.2, stageIndex: 1),
        LactatePowerPoint(power: 180, lactate: 1.5, stageIndex: 2),
        LactatePowerPoint(power: 210, lactate: 2.1, stageIndex: 3),
        LactatePowerPoint(power: 240, lactate: 3.0, stageIndex: 4),
        LactatePowerPoint(power: 270, lactate: 4.4, stageIndex: 5),
        LactatePowerPoint(power: 300, lactate: 6.2, stageIndex: 6)
    ]

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Power", point.power), y: .value("Lactate", point.lactate))
                .foregroundStyle(.orange)
            PointMark(x: .value("Power", point.power), y: .value("Lactate", point.lactate))
                .foregroundStyle(.orange)

            if point.lactate >= 2.0 && point.lactate < 2.3 {
                RuleMark(x: .value("LT1", point.power))
                    .foregroundStyle(.blue)
                    .lineStyle(.init(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("LT1")
                            .font(.caption2)
                    }
            }
            if point.lactate >= 4.0 && point.lactate < 4.8 {
                RuleMark(x: .value("LT2", point.power))
                    .foregroundStyle(.red)
                    .lineStyle(.init(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("LT2")
                            .font(.caption2)
                    }
            }
        }
        .frame(height: 220)
        .chartXAxisLabel("Power (W)")
        .chartYAxisLabel("Lactate (mmol/L)")
    }
}

private struct AnaerobicClearanceGraphicView: View {
    private let points: [TimeLactatePoint] = [
        TimeLactatePoint(minute: 0, value: 1.2),
        TimeLactatePoint(minute: 3, value: 6.8),
        TimeLactatePoint(minute: 5, value: 8.1),
        TimeLactatePoint(minute: 10, value: 6.9),
        TimeLactatePoint(minute: 15, value: 5.8),
        TimeLactatePoint(minute: 20, value: 4.9),
        TimeLactatePoint(minute: 25, value: 4.1)
    ]

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Minute", point.minute), y: .value("Lactate", point.value))
                .foregroundStyle(.mint)
            PointMark(x: .value("Minute", point.minute), y: .value("Lactate", point.value))
                .foregroundStyle(.mint)
        }
        .frame(height: 220)
        .chartXAxisLabel("Time (min)")
        .chartYAxisLabel("Lactate (mmol/L)")
    }
}

private struct ProtocolComparisonGraphicView: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Protocol").font(.caption.bold())
                Text("Duration").font(.caption.bold())
                Text("Strips").font(.caption.bold())
                Text("Primary Outcome").font(.caption.bold())
            }
            Divider()
                .gridCellUnsizedAxes([.horizontal, .vertical])
            GridRow {
                Text("Full Ramp")
                Text("~60 min")
                Text("9-13")
                Text("LT1/LT2 粗估")
            }
            GridRow {
                Text("MLSS")
                Text("90-150 min")
                Text("12+")
                Text("可持续阈值精确定位")
            }
            GridRow {
                Text("Anaerobic + Clearance")
                Text("35-45 min")
                Text("6-10")
                Text("峰值与清除速度")
            }
        }
        .font(.caption)
    }
}

private struct LactatePowerPoint: Identifiable {
    let id = UUID()
    let power: Int
    let lactate: Double
    let stageIndex: Int
}

struct LactateLabView: View {
    @StateObject private var store = LactateLabStore()
    @State private var page: LactateFlowPage = .hub
    @State private var selectedProtocol: LactateProtocolType = .fullRamp
    @State private var selectedStage = 0
    @State private var showingSampleSheet = false
    @State private var sampleValue = ""
    @State private var sampleRetest = false
    @State private var sampleContaminated = false
    @State private var sampleNote = ""
    @State private var liveAlert: String?
    @State private var selectedHistorySession: LactateTestSession?
    @State private var primaryGoal: LactatePrimaryGoal = .firstBaseline
    @State private var experienceLevel: LactateExperienceLevel = .beginner
    @State private var readiness: LactateReadinessState = .fresh
    @State private var has90MinWindow = true

    private var guidedRecommendation: LactatePathRecommendation {
        if readiness == .tired {
            return LactatePathRecommendation(
                protocolType: .fullRamp,
                title: "今天建议走：轻量 Full Ramp（仅做基线）",
                why: "疲劳会抬高或压低阈值点，先做低成本基线比强行做 MLSS 更可靠。",
                executionPath: [
                    "测试首页 → Full Ramp",
                    "协议设置里确认 FTP/睡眠/疲劳",
                    "仅记录关键台阶（2.0 / 4.0 mmol/L 附近）",
                    "48-72 小时恢复后再做 MLSS 精测"
                ],
                caution: "若 RPE 异常高或乳酸跳升 >2 mmol/L，请停止并改天复测。"
            )
        }

        switch primaryGoal {
        case .anaerobicCapacity:
            return LactatePathRecommendation(
                protocolType: .anaerobicClearance,
                title: "建议走：Anaerobic + Clearance",
                why: "目标是看冲刺后峰值与回落速度，该协议最直接反映无氧产乳酸与清除能力。",
                executionPath: [
                    "测试首页 → Anaerobic + Clearance",
                    "按冲刺→恢复节奏采样",
                    "重点看峰值、20 分钟回落比例、清除率",
                    "结果页回写到无氧训练与恢复策略"
                ],
                caution: "冲刺前确保热身充分；若独自测试，优先保证采血质量再追求样本数量。"
            )
        case .preciseThreshold:
            if experienceLevel == .practiced && has90MinWindow {
                return LactatePathRecommendation(
                    protocolType: .mlss,
                    title: "建议走：MLSS 精测路径",
                    why: "你有稳定采样能力与充足时间，MLSS 更适合做精确阈值和训练区间标定。",
                    executionPath: [
                        "测试首页 → MLSS",
                        "每阶段保持稳定功率，阶段内至少采两次",
                        "观察同阶段乳酸漂移（>1.0 mmol/L 视为超 MLSS）",
                        "结果页写入 MLSS 上下界并更新训练区"
                    ],
                    caution: "若中途配速/功率波动大，优先保证稳定输出，否则结果会偏差。"
                )
            }

            return LactatePathRecommendation(
                protocolType: .fullRamp,
                title: "建议先走：Full Ramp 预筛，再进 MLSS",
                why: "当时间不足或流程还不熟时，先用阶梯测试缩小阈值范围，再做 MLSS 更省样本。",
                executionPath: [
                    "先做 Full Ramp，定位 LT1/LT2 粗估功率",
                    "24-72 小时后安排 MLSS 精测",
                    "MLSS 阶段功率围绕粗估阈值上下 10W",
                    "将最终阈值回写训练区间"
                ],
                caution: "Full Ramp 仅用于路径选择和范围收敛，不替代 MLSS 阈值判定。"
            )
        case .firstBaseline:
            return LactatePathRecommendation(
                protocolType: .fullRamp,
                title: "建议走：Full Ramp 入门路径",
                why: "首次测试要优先建立采血节奏与质量控制，分级测试更容易执行且风险更低。",
                executionPath: [
                    "测试首页 → Full Ramp",
                    "完成测试前检查（尤其是污染控制）",
                    "每阶段末采样并记录 RPE/心率",
                    "得到初步 LT1/LT2 后再决定是否进 MLSS"
                ],
                caution: "出现污染怀疑请立刻重测，避免用错误读数推导阈值。"
            )
        }
    }

    private func protocolFocusSections(for type: LactateProtocolType) -> [ProtocolFocusSection] {
        switch type {
        case .fullRamp:
            return [
                ProtocolFocusSection(
                    title: "Key Details",
                    bullets: [
                        "Duration: ~1H plus cool-down.",
                        "No. of lactate strips required: ~9-13 (more if you need to take repeat measures).",
                        "Use this test to determine: overall lactate profile and approximate locations of LT1 and LT2.",
                        "Notes: Recommended for those with no prior testing or where last test is out of date."
                    ]
                ),
                ProtocolFocusSection(
                    title: "Protocol",
                    bullets: [
                        "Start at 40% FTP for 15 mins.",
                        "Ride 50% FTP for 6 mins.",
                        "Increase by 10% FTP every 5 mins (60% → 70% → 80% ...), with lactate sampling near each stage end.",
                        "100%-120% FTP stages may not be needed if test objective has already been reached."
                    ]
                ),
                ProtocolFocusSection(
                    title: "Testing Tips",
                    bullets: [
                        "优先保证采样质量：擦汗→消毒→酒精干燥→弃第一滴血。",
                        "若独自测试，建议在阶段末短暂停车取样。",
                        "将功率作为 x 轴、乳酸作为 y 轴观察拐点。"
                    ]
                )
            ]
        case .mlss:
            return [
                ProtocolFocusSection(
                    title: "Key Details",
                    bullets: [
                        "总时长约 90 分钟以上，适合精确阈值标定。",
                        "同阶段内至少采 2 次，观察乳酸漂移。",
                        "后段相对前段增加 >1.0 mmol/L，通常提示超过 MLSS。"
                    ]
                ),
                ProtocolFocusSection(
                    title: "Protocol",
                    bullets: [
                        "围绕预估阈值设置多个 30 分钟稳态功率块。",
                        "每个功率块记录 10/20/30 分钟乳酸。",
                        "根据漂移趋势微调下一次测试功率。"
                    ]
                ),
                ProtocolFocusSection(
                    title: "Testing Tips",
                    bullets: [
                        "稳态输出比追求更高功率更重要。",
                        "当天补给、睡眠和疲劳水平需尽量标准化。",
                        "建议使用 Full Ramp 结果先缩小 MLSS 搜索范围。"
                    ]
                )
            ]
        case .anaerobicClearance:
            return [
                ProtocolFocusSection(
                    title: "Key Details",
                    bullets: [
                        "用于评估冲刺后乳酸峰值与清除速度。",
                        "重点指标：峰值、20 分钟回落比例、清除率。",
                        "适合用于无氧训练和恢复策略调整。"
                    ]
                ),
                ProtocolFocusSection(
                    title: "Protocol",
                    bullets: [
                        "低强度热身后进行短冲刺刺激乳酸升高。",
                        "恢复阶段每 5 分钟采样，追踪下降曲线。",
                        "同一协议重复测试时，冲刺方式需保持一致。"
                    ]
                ),
                ProtocolFocusSection(
                    title: "Testing Tips",
                    bullets: [
                        "冲刺前务必充分热身，减少受伤风险。",
                        "若峰值异常低，先排查采样污染或时机过晚。",
                        "关注曲线斜率变化而不是单次绝对值。"
                    ]
                )
            ]
        }
    }

    private func powerLactatePoints(for session: LactateTestSession) -> [LactatePowerPoint] {
        session.samples
            .filter { !$0.suspectedContamination }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { sample in
                guard let stage = session.stages.first(where: { $0.stageIndex == sample.stageIndex }) else {
                    return nil
                }
                return LactatePowerPoint(power: stage.targetPower, lactate: sample.value, stageIndex: sample.stageIndex)
            }
    }

    private func setupGuideItems(for session: Binding<LactateTestSession>) -> [SetupGuideItem] {
        var items: [SetupGuideItem] = [
            SetupGuideItem(text: "先确认 FTP 与 Max HR，后续阈值推导都会依赖这两个基准。", isWarning: false),
            SetupGuideItem(text: "若独自测试，建议保持 Self-Test Mode 打开，阶段末再统一采样。", isWarning: false),
            SetupGuideItem(text: "开测前至少保留 60 分钟无热量摄入窗口，避免乳酸基线被抬高。", isWarning: false)
        ]

        if session.preconditions.minutesSinceCalories.wrappedValue < 60 {
            items.append(SetupGuideItem(text: "当前距上次进食不足 60 分钟，建议延后测试。", isWarning: true))
        }

        if session.preconditions.fatigueLevel.wrappedValue >= 4 {
            items.append(SetupGuideItem(text: "疲劳较高（4/5 及以上），优先做轻量基线或改天精测。", isWarning: true))
        }

        if session.preconditions.sleepHours.wrappedValue < 6 {
            items.append(SetupGuideItem(text: "睡眠少于 6 小时，阈值结果可能偏差，建议谨慎解读。", isWarning: true))
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lactate Lab")
                .font(.largeTitle.bold())

            Picker("Page", selection: $page) {
                ForEach(LactateFlowPage.allCases) { p in
                    Text(verbatim: p.title).tag(p)
                }
            }
            .appDropdownTheme(width: 260)

            ScrollView {
                switch page {
                case .hub:
                    hubPage
                case .protocols:
                    protocolLibraryPage
                case .setup:
                    setupPage
                case .checklist:
                    checklistPage
                case .live:
                    livePage
                case .results:
                    resultsPage
                case .history:
                    historyPage
                case .settings:
                    settingsPage
                }
            }
        }
        .padding(20)
        .sheet(isPresented: $showingSampleSheet) {
            sampleSheet
        }
        .sheet(item: $selectedHistorySession) { session in
            historyDetailSheet(session)
        }
        .alert("提醒", isPresented: Binding(get: { liveAlert != nil }, set: { if !$0 { liveAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(liveAlert ?? "")
        }
    }

    private var hubPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("第 1 步：选择测试 protocol") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Protocol", selection: $selectedProtocol) {
                        ForEach(LactateProtocolType.allCases) { type in
                            Text(verbatim: type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(verbatim: selectedProtocol.recommendation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("进入测试重点与设置") {
                            store.startSession(protocolType: selectedProtocol)
                            page = .setup
                        }
                        .buttonStyle(.borderedProminent)

                        Button("查看完整协议库与图示") {
                            page = .protocols
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            GroupBox("路径引导（可选）") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("主要目标", selection: $primaryGoal) {
                        ForEach(LactatePrimaryGoal.allCases) { goal in
                            Text(goal.title).tag(goal)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("经验水平", selection: $experienceLevel) {
                        ForEach(LactateExperienceLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("当天状态", selection: $readiness) {
                        ForEach(LactateReadinessState.allCases) { state in
                            Text(state.title).tag(state)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("我有 90 分钟以上完整测试窗口", isOn: $has90MinWindow)

                    Divider()

                    Text(guidedRecommendation.title)
                        .font(.headline)
                    Text(guidedRecommendation.why)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("建议操作路径")
                            .font(.subheadline.bold())
                        ForEach(Array(guidedRecommendation.executionPath.enumerated()), id: \.offset) { idx, step in
                            Text("\(idx + 1). \(step)")
                                .font(.subheadline)
                        }
                    }

                    Text("注意：\(guidedRecommendation.caution)")
                        .font(.subheadline)
                        .foregroundStyle(.orange)

                    HStack {
                        Button("采用建议路径并开始") {
                            selectedProtocol = guidedRecommendation.protocolType
                            store.startSession(protocolType: selectedProtocol)
                            page = .setup
                        }
                        .buttonStyle(.borderedProminent)

                        Text("推荐协议：\(guidedRecommendation.protocolType.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let current = store.currentSession, current.status != .completed {
                GroupBox(L10n.choose(simplifiedChinese: "未完成测试", english: "Incomplete Test")) {
                    HStack {
                        Text("\(current.protocolType.title) · \(current.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        Spacer()
                        Button(L10n.choose(simplifiedChinese: "继续", english: "Continue")) {
                            page = .live
                        }
                    }
                }
            }
        }
    }

    private var protocolLibraryPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Blood Lactate Testing: Protocols For Cyclists") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("这页整合完整测试说明、图示与执行要点，并拆分到乳酸实验室各页面可直接操作。")
                        .foregroundStyle(.secondary)
                    Text("核心目标：先拿到干净数据，再做阈值判定，最后回写训练区间。")
                }
            }

            GroupBox("What do I need for a lactate test?") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 乳酸仪 + 试纸（建议预留重测余量）")
                    Text("• 采血针、酒精棉、干纸巾、垃圾收纳")
                    Text("• 稳定功率来源（智能台/功率计）与心率带")
                    Text("• 风扇、饮水、计时器、记录表（功率/心率/RPE/乳酸）")
                    Text("• 可选：协助者（显著降低独自采样误差）")
                }
                .font(.subheadline)
            }

            GroupBox("How To Take A Lactate Sample") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. 擦汗并保持手指/耳垂清洁，避免汗液污染。")
                    Text("2. 酒精消毒后等待完全干燥。")
                    Text("3. 穿刺后丢弃第一滴血，第二滴用于测试。")
                    Text("4. 若读数异常或试纸沾污，立刻重测并标记 isRetest。")
                    Text("5. 各阶段采样时机保持一致（阶段末 20-40 秒窗口）。")
                }
                .font(.subheadline)
            }

            GroupBox("Full Ramp: protocol diagram") {
                VStack(alignment: .leading, spacing: 10) {
                    FullRampProtocolGraphicView()
                    Text("上图已对应 Setup 页的默认阶段。红点 = 阶段末采血。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Aerobic Test (LT1 / LT2)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("判读逻辑：")
                        .font(.subheadline.bold())
                    Text("• LT1：乳酸从基线出现持续上拐（常在 ~2.0 mmol/L 附近）")
                    Text("• LT2：上升斜率明显增加（常在 ~4.0 mmol/L 附近）")
                    AerobicCurveGraphicView()
                }
                .font(.subheadline)
            }

            GroupBox("Anaerobic Power + Clearance Test") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("步骤：热身 → 冲刺刺激 → 20 分钟恢复追踪。")
                    Text("关注：峰值、20 分钟回落比例、单位时间清除率。")
                    AnaerobicClearanceGraphicView()
                }
                .font(.subheadline)
            }

            GroupBox("Protocol comparison") {
                ProtocolComparisonGraphicView()
            }

            GroupBox("Incorporating The Results") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 把 LT1/LT2 对应功率与心率写入训练区间。")
                    Text("• 有氧日围绕 LT1 下方；阈值训练围绕 LT2 上下。")
                    Text("• 无氧课按清除速度决定间歇密度与恢复时长。")
                    Text("• 4-8 周复测一次；训练负荷变化大时提前复测。")
                }
                .font(.subheadline)
            }

            GroupBox("Limitations") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 不同日状态（睡眠/补给/压力）会改变读数。")
                    Text("• 采样污染是最大误差源，需严格流程控制。")
                    Text("• 单次测试不等于长期能力，必须结合训练日志。")
                    Text("• 乳酸仅反映代谢侧面，需与主观体感和表现共同解读。")
                }
                .font(.subheadline)
            }

            GroupBox("Get Fast, Faster") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("执行顺序建议：协议总览 → Setup → Checklist → Live → Results。")
                    Text("若今天状态不佳，先做低成本基线，避免把错误阈值写入训练计划。")
                    Button("基于当前推荐协议开始测试") {
                        store.startSession(protocolType: selectedProtocol)
                        page = .setup
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var setupPage: some View {
        Group {
            if let session = Binding($store.currentSession) {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("本页引导（填完这些再进入下一步）") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("推荐协议：\(session.protocolType.wrappedValue.title)")
                                .font(.subheadline.bold())
                            ForEach(setupGuideItems(for: session)) { item in
                                Label {
                                    Text(item.text)
                                        .foregroundStyle(item.isWarning ? .orange : .primary)
                                } icon: {
                                    Image(systemName: item.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                        .foregroundStyle(item.isWarning ? .orange : .green)
                                }
                            }
                        }
                    }

                    GroupBox("测试重点（类似 Full ramp test 说明）") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(session.protocolType.wrappedValue.title)
                                .font(.headline)

                            if session.protocolType.wrappedValue == .fullRamp {
                                FullRampProtocolGraphicView()
                            }

                            ForEach(protocolFocusSections(for: session.protocolType.wrappedValue)) { section in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(section.title)
                                        .font(.subheadline.bold())
                                    ForEach(section.bullets, id: \.self) { bullet in
                                        Text("• \(bullet)")
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    }

                    GroupBox("Athlete") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Name", text: session.preconditions.riderName)
                            Stepper("FTP: \(session.preconditions.ftp.wrappedValue) W", value: session.preconditions.ftp, in: 120...500)
                            Stepper("Max HR: \(session.preconditions.maxHR.wrappedValue) bpm", value: session.preconditions.maxHR, in: 140...230)
                            Toggle("Self-Test Mode", isOn: session.preconditions.selfTestMode)
                        }
                    }

                    GroupBox("阶段计划") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(session.stages.wrappedValue) { stage in
                                Text("\(stage.stageType): \(stage.targetPower) W · \(stage.durationMinutes) 分钟 · \(stage.sampleHint)")
                                    .font(.subheadline)
                            }
                        }
                    }

                    GroupBox("Preconditions") {
                        VStack(alignment: .leading, spacing: 8) {
                            Stepper("Minutes since calories: \(session.preconditions.minutesSinceCalories.wrappedValue)", value: session.preconditions.minutesSinceCalories, in: 0...360)
                            Stepper("Fatigue: \(session.preconditions.fatigueLevel.wrappedValue)/5", value: session.preconditions.fatigueLevel, in: 1...5)
                            Stepper("Sleep: \(String(format: "%.1f", session.preconditions.sleepHours.wrappedValue)) h", value: session.preconditions.sleepHours, in: 0...12, step: 0.5)
                            Toggle("ERG Mode", isOn: session.preconditions.usesERGMode)
                        }
                    }

                    Button("保存并继续") {
                        store.saveCurrent()
                        page = .checklist
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("请先在 Test Hub 开始一个测试。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var checklistPage: some View {
        Group {
            if let session = Binding($store.currentSession) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("样本污染是错误读数最常见原因")
                        .font(.headline)
                    Text("测试前约 1 小时避免摄入含热量饮料/食物；测试中避免含热量补给。")
                        .foregroundStyle(.secondary)

                    checklistRow("已准备乳酸仪/试纸/采血针/酒精棉/纸巾/毛巾", binding: session.checklistItems[0])
                    checklistRow("已知晓：擦汗→酒精干燥→丢弃第一滴血", binding: session.checklistItems[1])
                    checklistRow("已记录营养状态", binding: session.checklistItems[2])
                    checklistRow("已知自测模式可阶段结束后暂停采样", binding: session.checklistItems[3])

                    let ready = session.checklistItems.wrappedValue.allSatisfy { $0 }
                    Button("进入实时测试") {
                        session.checklistCompleted.wrappedValue = true
                        store.saveCurrent()
                        page = .live
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ready)
                }
            } else {
                Text("暂无测试。")
            }
        }
    }

    private func checklistRow(_ label: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(verbatim: label)
        }
    }

    private var livePage: some View {
        Group {
            if let session = Binding($store.currentSession) {
                let stage = session.stages.wrappedValue.indices.contains(selectedStage) ? session.stages.wrappedValue[selectedStage] : nil
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("状态") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Protocol: \(session.protocolType.wrappedValue.title)")
                            Text("当前阶段: \(stage?.stageType ?? "-")")
                            Text("目标功率: \(stage?.targetPower ?? 0) W")
                            Text("阶段时长: \(stage?.durationMinutes ?? 0) 分钟")
                            Text("下一次采样: \(stage?.sampleHint ?? (session.preconditions.selfTestMode.wrappedValue ? "阶段末暂停采样" : "第5分钟"))")
                        }
                    }

                    GroupBox("主操作") {
                        HStack {
                            Button("记录乳酸") {
                                showingSampleSheet = true
                            }
                            .buttonStyle(.borderedProminent)

                            Button("完成本阶段") {
                                selectedStage = min(selectedStage + 1, max(session.stages.wrappedValue.count - 1, 0))
                            }
                            .buttonStyle(.bordered)

                            Button("结束测试") {
                                store.completeSession()
                                page = .results
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    GroupBox("已记录") {
                        if session.samples.wrappedValue.isEmpty {
                            Text("暂无乳酸样本")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(session.samples.wrappedValue) { sample in
                                HStack {
                                    Text("Stage \(sample.stageIndex) · \(String(format: "%.1f", sample.value)) mmol/L")
                                    if sample.isRetest { Text("重测").foregroundStyle(.orange) }
                                    if sample.suspectedContamination { Text("污染").foregroundStyle(.red) }
                                }
                            }
                        }
                    }
                }
            } else {
                Text("暂无进行中的测试")
            }
        }
    }

    private var sampleSheet: some View {
        NavigationStack {
            Form {
                TextField("乳酸值 mmol/L", text: $sampleValue)
                Toggle("重测", isOn: $sampleRetest)
                Toggle("疑似污染", isOn: $sampleContaminated)
                TextField("备注", text: $sampleNote)
            }
            .navigationTitle("Sample Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { resetSampleForm() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { addSample() }
                }
            }
        }
    }

    private func addSample() {
        guard var session = store.currentSession, let value = Double(sampleValue) else { return }
        let sample = LactateSample(
            stageIndex: selectedStage,
            timestamp: Date(),
            value: value,
            isRetest: sampleRetest,
            suspectedContamination: sampleContaminated,
            note: sampleNote
        )
        session.samples.append(sample)

        if session.samples.count >= 2 {
            let sorted = session.samples.sorted { $0.timestamp < $1.timestamp }
            if let previous = sorted.dropLast().last,
               (sample.value - previous.value) > 2.0 {
                liveAlert = "相邻两次乳酸跳升超过 2 mmol/L，建议复测。"
            }
        }

        if session.protocolType == .fullRamp {
            if sample.value > 6.0 {
                liveAlert = "Full Ramp 已超过 6 mmol/L，建议结束测试。"
            }
        }

        store.currentSession = session
        store.saveCurrent()
        resetSampleForm()
    }

    private func resetSampleForm() {
        sampleValue = ""
        sampleRetest = false
        sampleContaminated = false
        sampleNote = ""
        showingSampleSheet = false
    }

    private var resultsPage: some View {
        Group {
            if let session = store.currentSession {
                let points = powerLactatePoints(for: session)
                VStack(alignment: .leading, spacing: 10) {
                    GroupBox("测试概览") {
                        VStack(alignment: .leading) {
                            Text("协议: \(session.protocolType.title)")
                            Text("日期: \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            Text("有效样本: \(session.samples.filter { !$0.suspectedContamination }.count)")
                        }
                    }

                    GroupBox("关键结论") {
                        switch session.protocolType {
                        case .fullRamp:
                            Text("LT1 粗估: \(session.metrics.lt1Estimate.map { "\($0) W" } ?? "-")")
                            Text("LT2 粗估: \(session.metrics.lt2Estimate.map { "\($0) W" } ?? "-")")
                            Text("本协议仅用于粗略观察，不是精确阈值判定。")
                                .foregroundStyle(.secondary)
                        case .mlss:
                            Text("MLSS 区间: \(session.metrics.mlssLowerBound.map(String.init) ?? "-") - \(session.metrics.mlssUpperBound.map(String.init) ?? "-") W")
                        case .anaerobicClearance:
                            Text("基线: \(session.metrics.baselineLactate.map { String(format: "%.1f", $0) } ?? "-") mmol/L")
                            Text("峰值: \(session.metrics.peakLactate.map { String(format: "%.1f", $0) } ?? "-") mmol/L")
                            Text("VLaMax: \(session.metrics.vlaMax.map { String(format: "%.3f", $0) } ?? "-")")
                            Text("清除率: \(session.metrics.clearanceRate.map { String(format: "%.3f", $0) } ?? "-") mmol/L/min")
                        }
                    }

                    GroupBox("功率-乳酸曲线") {
                        if points.isEmpty {
                            Text("暂无有效样本，完成阶段采样后将显示曲线。")
                                .foregroundStyle(.secondary)
                        } else {
                            Chart(points) { point in
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
                            .frame(height: 250)
                            .chartXAxisLabel("Power (W)")
                            .chartYAxisLabel("Lactate (mmol/L)")
                        }
                    }
                }
            } else {
                Text("暂无结果")
            }
        }
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.history.isEmpty {
                Text("暂无历史记录")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.history) { item in
                    Button {
                        selectedHistorySession = item
                    } label: {
                        GroupBox {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text("\(item.protocolType.title) · \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    Text("样本数: \(item.samples.count) · 状态: \(item.status.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func historyDetailSheet(_ session: LactateTestSession) -> some View {
        let points = powerLactatePoints(for: session)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("测试概览") {
                        VStack(alignment: .leading) {
                            Text("协议: \(session.protocolType.title)")
                            Text("日期: \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            Text("样本数: \(session.samples.count)")
                        }
                    }

                    GroupBox("历史曲线") {
                        if points.isEmpty {
                            Text("暂无有效样本，无法绘制曲线。")
                                .foregroundStyle(.secondary)
                        } else {
                            Chart(points) { point in
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
                            .frame(height: 260)
                            .chartXAxisLabel("Power (W)")
                            .chartYAxisLabel("Lactate (mmol/L)")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 20)
            .navigationTitle("历史详情")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        selectedHistorySession = nil
                    }
                }
            }
        }
    }

    private var settingsPage: some View {
        GroupBox("默认配置") {
            VStack(alignment: .leading, spacing: 8) {
                Stepper("默认 FTP: \(store.defaultFTP) W", value: $store.defaultFTP, in: 120...500)
                Stepper("默认 Max HR: \(store.defaultMaxHR) bpm", value: $store.defaultMaxHR, in: 140...230)
                TextField("默认乳酸仪型号", text: $store.defaultAnalyzerModel)
                Toggle("默认自测模式", isOn: $store.defaultSelfTestMode)
                Toggle("默认采样提醒", isOn: $store.reminderEnabled)
            }
        }
    }
}

private extension Binding {
    init?(_ source: Binding<Value?>) {
        guard source.wrappedValue != nil else { return nil }
        self.init(
            get: { source.wrappedValue! },
            set: { source.wrappedValue = $0 }
        )
    }
}
