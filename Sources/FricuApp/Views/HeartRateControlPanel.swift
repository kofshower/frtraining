import SwiftUI
import Charts

struct HeartRateControlPanel: View {
    @ObservedObject var monitor: HeartRateMonitorManager
    @State private var isServiceFieldsExpanded = false

    var body: some View {
        GroupBox("Heart Rate Monitor (Bluetooth)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("State: \(monitor.bluetoothStateText)")
                        .font(.subheadline)
                    Spacer()
                    if monitor.isConnected {
                        Text("Connected: \(monitor.connectedDeviceName ?? "HR Monitor")")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                    }
                }

                HStack {
                    Button(monitor.isScanning ? "Scanning..." : "Scan HR Monitors") {
                        monitor.startScan()
                    }
                    .disabled(monitor.isScanning)

                    if monitor.isScanning {
                        Button("Stop Scan") {
                            monitor.stopScan()
                        }
                    }

                    if monitor.isConnected {
                        Button("Disconnect", role: .destructive) {
                            monitor.disconnect()
                        }
                    }
                }

                if !monitor.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Discovered")
                            .font(.headline)
                        ForEach(monitor.discoveredDevices) { device in
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text("RSSI \(device.rssi)")
                                    .foregroundStyle(.secondary)
                                Button(device.isConnected ? "Connected" : "Connect") {
                                    monitor.connect(deviceID: device.id)
                                }
                                .disabled(device.isConnected)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if monitor.isConnected {
                    Divider()

                    HStack(spacing: 14) {
                        HRMetricChip(
                            title: "Heart Rate",
                            value: monitor.liveHeartRateBPM.map { "\($0) bpm" } ?? "--"
                        )

                        HRMetricChip(
                            title: "1m Average",
                            value: monitor.oneMinuteAverageHeartRateBPM.map { String(format: "%.1f bpm", $0) } ?? "--"
                        )

                        HRMetricChip(
                            title: "RR Interval",
                            value: monitor.liveRRIntervalMS.map { String(format: "%.0f ms", $0) } ?? "--"
                        )

                        HRMetricChip(
                            title: "HRV RMSSD",
                            value: monitor.liveHRVRMSSDMS.map { String(format: "%.1f ms", $0) } ?? "--"
                        )

                        HRMetricChip(
                            title: "HRV SDNN",
                            value: monitor.liveHRVSDNNMS.map { String(format: "%.1f ms", $0) } ?? "--"
                        )

                        HRMetricChip(
                            title: "HRV pNN50",
                            value: monitor.liveHRVPNN50Percent.map { String(format: "%.1f %%", $0) } ?? "--"
                        )
                    }

                    Text("HRV window: 5 min · RR samples \(monitor.liveHRVSampleCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        HeartRateSparklineCard(
                            label: "RR Interval",
                            value: monitor.liveRRIntervalMS.map { String(format: "%.0f ms", $0) } ?? "--",
                            points: monitor.rrTrendPoints,
                            tint: .pink
                        )
                        HeartRateSparklineCard(
                            label: "HRV RMSSD",
                            value: monitor.liveHRVRMSSDMS.map { String(format: "%.1f ms", $0) } ?? "--",
                            points: monitor.hrvRMSSDTrendPoints,
                            tint: .teal
                        )
                        HeartRateSparklineCard(
                            label: "Energy",
                            value: monitor.liveEnergyExpendedKJ.map { "\($0) kJ" } ?? "--",
                            points: monitor.energyTrendPoints,
                            tint: .brown
                        )
                    }

                    DisclosureGroup(
                        L10n.choose(
                            simplifiedChinese: "展开 Heart Rate Service 字段",
                            english: "Show Heart Rate Service Fields"
                        ),
                        isExpanded: $isServiceFieldsExpanded
                    ) {
                        HeartRateServiceFieldsView(
                            measurement: monitor.liveHeartRateMeasurement,
                            bodySensorLocation: monitor.bodySensorLocation,
                            controlPointAvailable: monitor.controlPointAvailable,
                            rawCharacteristicHex: monitor.heartRateRawCharacteristicHex
                        )
                        .padding(.top, 6)
                    }
                }

                if let message = monitor.lastMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private struct HRMetricChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HeartRateSparklineCard: View {
    let label: String
    let value: String
    let points: [HeartRateTrendPoint]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit().bold())
            }

            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(tint)
                    .interpolationMethod(.linear)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(tint.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .cartesianHoverTip(
                    xTitle: L10n.choose(simplifiedChinese: "时间", english: "Time"),
                    yTitle: label
                )
                .frame(height: 48)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.08))
                    .frame(height: 48)
                    .overlay(
                        Text("Waiting data")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
