import SwiftUI

struct PowerMeterControlPanel: View {
    @ObservedObject var powerMeter: PowerMeterManager
    @State private var isCyclingPowerFieldsExpanded = false

    private var balanceText: String {
        guard let left = powerMeter.liveLeftBalancePercent,
              let right = powerMeter.liveRightBalancePercent else {
            return "--"
        }
        return String(format: "L%.0f%% / R%.0f%%", left, right)
    }

    var body: some View {
        GroupBox("Bike Power Meter (BLE)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("State: \(powerMeter.bluetoothStateText)")
                        .font(.subheadline)
                    Spacer()
                    if powerMeter.isConnected {
                        Text("Connected: \(powerMeter.connectedDeviceName ?? "Power Meter")")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                    }
                }

                HStack {
                    Button(powerMeter.isScanning ? "Scanning..." : "Scan Power Meters") {
                        powerMeter.startScan()
                    }
                    .disabled(powerMeter.isScanning)

                    if powerMeter.isScanning {
                        Button("Stop Scan") {
                            powerMeter.stopScan()
                        }
                    }

                    if powerMeter.isConnected {
                        Button("Disconnect", role: .destructive) {
                            powerMeter.disconnect()
                        }
                    }
                }

                if !powerMeter.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Discovered")
                            .font(.headline)
                        ForEach(powerMeter.discoveredDevices) { device in
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text("RSSI \(device.rssi)")
                                    .foregroundStyle(.secondary)
                                Button(device.isConnected ? "Connected" : "Connect") {
                                    powerMeter.connect(deviceID: device.id)
                                }
                                .disabled(device.isConnected)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if powerMeter.isConnected {
                    HStack(spacing: 14) {
                        PowerMeterMetricChip(title: "PM Power", value: powerMeter.livePowerWatts.map { "\($0) W" } ?? "--")
                        PowerMeterMetricChip(title: "PM Cadence", value: powerMeter.liveCadenceRPM.map { String(format: "%.0f rpm", $0) } ?? "--")
                        PowerMeterMetricChip(title: "PM L/R", value: balanceText)
                    }

                    if let cps = powerMeter.liveCyclingPowerMeasurement {
                        DisclosureGroup(
                            L10n.choose(
                                simplifiedChinese: "展开功率计 Service 字段",
                                english: "Show Power Meter Service Fields"
                            ),
                            isExpanded: $isCyclingPowerFieldsExpanded
                        ) {
                            CyclingPowerFieldsView(
                                title: L10n.choose(
                                    simplifiedChinese: "功率计 CPS 字段（2A63）",
                                    english: "Power Meter CPS Fields (2A63)"
                                ),
                                measurement: cps
                            )
                            .padding(.top, 6)
                        }
                    }
                }

                if let message = powerMeter.lastMessage {
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

private struct PowerMeterMetricChip: View {
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
