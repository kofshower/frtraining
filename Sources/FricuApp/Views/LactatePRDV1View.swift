import SwiftUI

struct LactatePRDV1View: View {
    private enum MainTab: String, CaseIterable, Identifiable {
        case test
        case history
        case templates
        case devices

        var id: String { rawValue }

        var title: String {
            switch self {
            case .test: return "Test"
            case .history: return "History"
            case .templates: return "Templates"
            case .devices: return "Devices"
            }
        }
    }

    @State private var selectedTab: MainTab = .test
    @State private var selectedProtocol = 0
    @State private var showChecklist = true
    @State private var helperMode = true
    @State private var soloPause = false
    @State private var contaminationItems: [Bool] = Array(repeating: false, count: 5)

    private let protocolCards: [(title: String, details: String, strips: String)] = [
        ("Full Ramp Test (6-min stages)", "LT1/LT2 profile and trend", "8-12 strips"),
        ("MLSS (10-min stages)", "Stage drift and MLSS bracket", "6-10 strips"),
        ("Anaerobic Capacity + Clearance", "Peak lactate and clearance", "5-8 strips")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lactate Home Protocol · V1")
                .font(.title2.bold())

            Picker("Tab", selection: $selectedTab) {
                ForEach(MainTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case .test:
                testTab
            case .history:
                historyTab
            case .templates:
                templatesTab
            case .devices:
                devicesTab
            }
        }
    }

    private var testTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Start Test") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(protocolCards.enumerated()), id: \.offset) { index, card in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(card.title)
                                    .font(.headline)
                                Text(card.details)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Label("~45-90 min", systemImage: "clock")
                                    Label(card.strips, systemImage: "drop")
                                    Spacer()
                                    Button("Start") {
                                        selectedProtocol = index
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .font(.caption)
                            }
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }

                GroupBox("Pre-test Checklist") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show checklist before begin", isOn: $showChecklist)
                        Toggle("Helper present", isOn: $helperMode)

                        Text("Contamination prevention (must confirm)")
                            .font(.subheadline.bold())

                        ForEach(contaminationItems.indices, id: \.self) { index in
                            Toggle(contaminationText(for: index), isOn: $contaminationItems[index])
                        }

                        HStack {
                            Button("Begin Warm-up") {}
                                .buttonStyle(.borderedProminent)
                            Button("Save as Draft") {}
                                .buttonStyle(.bordered)
                        }
                    }
                }

                GroupBox("Live Protocol (Full Ramp)") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            liveMetric("Total", "00:32:12")
                            liveMetric("Stage", "05:00 / 06:00")
                            liveMetric("Target", "260W")
                            liveMetric("HR", "168 bpm")
                        }

                        Text("Stage 3 of 10 · sample prompt at 5:00")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sample Workflow")
                                .font(.subheadline.bold())
                            Text("1) Wipe sweat  2) Alcohol swab + dry  3) Wipe first drop  4) Collect second drop")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField("Lactate mmol/L", text: .constant(""))
                                    .textFieldStyle(.roundedBorder)
                                Button("Repeat sample") {}
                                    .buttonStyle(.bordered)
                            }
                            Toggle("Solo mode pause at stage end", isOn: $soloPause)
                        }
                    }
                }
            }
        }
    }

    private var historyTab: some View {
        GroupBox("Session History") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Filters: protocol / date range / high contamination risk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• 2026-02-12 Full Ramp  LT1 225W  LT2 285W")
                Text("• 2026-02-04 MLSS  262-272W")
                Text("• 2026-01-20 Anaerobic  Peak 12.4 mmol/L")
                Divider()
                Text("Compare view: overlay lactate curves + variance bands")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var templatesTab: some View {
        GroupBox("Template Builder") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ramp: start 40% FTP, fixed 6:00 stage, sample @ 5:00")
                Text("MLSS: 10:00 stage, sample @ 3:00 and 9:00")
                Text("Anaerobic: 3/5/7 min + optional 20 min")
                Divider()
                Text("Export columns ready for CSV / XLSX style results template")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var devicesTab: some View {
        GroupBox("Devices & Inputs") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Power Source: Smart Trainer")
                Text("HR Sensor: Connected")
                Text("Lactate Meter: Lactate Pro 2")
                Text("Strip Batch: Optional")
                Text("Sampling Site: Finger / Earlobe")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func contaminationText(for index: Int) -> String {
        switch index {
        case 0: return "Wiped sweat (hand/arm/face)"
        case 1: return "Alcohol swab used and fully dried"
        case 2: return "First drop wiped"
        case 3: return "Strip tip did not touch skin"
        default: return "Hands warmed / blood flow OK"
        }
    }

    private func liveMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
