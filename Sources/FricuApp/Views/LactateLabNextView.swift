import SwiftUI
import Charts

struct LactateLabNextView: View {
    private struct Milestone: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let symbol: String
    }

    private struct DemoPoint: Identifiable {
        let id = UUID()
        let minute: Int
        let lactate: Double
        let zone: String
    }

    @State private var plannedDate = Date()
    @State private var ftp: Double = 250
    @State private var lthr: Double = 172
    @State private var testGoal = 0
    @State private var showAssistantTips = true

    private let goals = ["建立首次基线", "精确阈值定位", "冲刺后清除评估"]

    private let milestones: [Milestone] = [
        Milestone(title: "准备", detail: "录入测试目标、FTP、LTHR 与采样偏好", symbol: "slider.horizontal.3"),
        Milestone(title: "执行", detail: "按阶段骑行并在提示点完成乳酸采样", symbol: "figure.outdoor.cycle"),
        Milestone(title: "复盘", detail: "自动生成 LT1/LT2、区间建议和风险提示", symbol: "chart.line.uptrend.xyaxis")
    ]

    private var demoCurve: [DemoPoint] {
        [
            DemoPoint(minute: 0, lactate: 1.2, zone: "Warmup"),
            DemoPoint(minute: 8, lactate: 1.8, zone: "Z2"),
            DemoPoint(minute: 16, lactate: 2.4, zone: "Tempo"),
            DemoPoint(minute: 24, lactate: 3.6, zone: "Threshold"),
            DemoPoint(minute: 32, lactate: 4.6, zone: "Threshold"),
            DemoPoint(minute: 40, lactate: 6.1, zone: "VO2"),
            DemoPoint(minute: 50, lactate: 3.9, zone: "Recovery")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("乳酸实验室 · Next")
                .font(.title2.bold())

            GroupBox("测试规划") {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("计划日期", selection: $plannedDate, displayedComponents: [.date, .hourAndMinute])
                    Picker("测试目标", selection: $testGoal) {
                        ForEach(goals.indices, id: \.self) { index in
                            Text(goals[index]).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("FTP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Stepper("\(Int(ftp)) W", value: $ftp, in: 120...500, step: 5)
                        }

                        VStack(alignment: .leading) {
                            Text("LTHR")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Stepper("\(Int(lthr)) bpm", value: $lthr, in: 120...210, step: 1)
                        }
                    }

                    Toggle("显示单人测试助手提示", isOn: $showAssistantTips)
                }
            }

            GroupBox("流程总览") {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(milestones) { milestone in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(milestone.title, systemImage: milestone.symbol)
                                .font(.headline)
                            Text(milestone.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            GroupBox("示例乳酸曲线") {
                VStack(alignment: .leading, spacing: 8) {
                    Chart(demoCurve) { point in
                        LineMark(
                            x: .value("Minute", point.minute),
                            y: .value("Lactate", point.lactate)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Zone", point.zone))

                        PointMark(
                            x: .value("Minute", point.minute),
                            y: .value("Lactate", point.lactate)
                        )
                        .symbolSize(30)
                    }
                    .frame(height: 220)

                    Text("提示：该页面为全新实验室入口，帮助你先完成规划，再进入完整实时测试流程。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
