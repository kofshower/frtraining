import SwiftUI
import FricuCore

struct FitnessMachineFieldsView: View {
    let indoorBikeData: IndoorBikeDataMeasurement?
    let statusEvent: FitnessMachineStatusEvent?
    let trainingStatus: FitnessMachineTrainingStatus?
    let featureSet: FitnessMachineFeatureSet?
    let resistanceRange: FitnessMachineSupportedRange?
    let powerRange: FitnessMachineSupportedRange?
    let rawCharacteristicHex: [String: String]

    private var indoorRows: [TelemetryField] {
        guard let d = indoorBikeData else {
            return TelemetryFieldFactory.noDataRows(label: L10n.t("Indoor Bike Data", "Indoor Bike Data"))
        }
        return [
            .init(label: L10n.t("Flags", "Flags"), value: String(format: "0x%04X", d.flags.rawValue)),
            .init(label: L10n.t("瞬时速度", "Instant Speed"), value: TelemetryFieldFactory.format(d.instantaneousSpeedKPH, unit: " km/h", digits: 2)),
            .init(label: L10n.t("平均速度", "Average Speed"), value: TelemetryFieldFactory.format(d.averageSpeedKPH, unit: " km/h", digits: 2)),
            .init(label: L10n.t("瞬时踏频", "Instant Cadence"), value: TelemetryFieldFactory.format(d.instantaneousCadenceRPM, unit: " rpm", digits: 1)),
            .init(label: L10n.t("平均踏频", "Average Cadence"), value: TelemetryFieldFactory.format(d.averageCadenceRPM, unit: " rpm", digits: 1)),
            .init(label: L10n.t("总距离", "Total Distance"), value: d.totalDistanceMeters.map { "\($0) m" } ?? "--"),
            .init(label: L10n.t("阻力等级", "Resistance Level"), value: d.resistanceLevel.map { "\($0)" } ?? "--"),
            .init(label: L10n.t("瞬时功率", "Instant Power"), value: d.instantaneousPowerWatts.map { "\($0) W" } ?? "--"),
            .init(label: L10n.t("平均功率", "Average Power"), value: d.averagePowerWatts.map { "\($0) W" } ?? "--"),
            .init(label: L10n.t("总能量", "Total Energy"), value: d.totalEnergyKCal.map { "\($0) kcal" } ?? "--"),
            .init(label: L10n.t("每小时能量", "Energy per Hour"), value: d.energyPerHourKCal.map { "\($0) kcal/h" } ?? "--"),
            .init(label: L10n.t("每分钟能量", "Energy per Minute"), value: d.energyPerMinuteKCal.map { "\($0) kcal/min" } ?? "--"),
            .init(label: L10n.t("心率", "Heart Rate"), value: d.heartRateBPM.map { "\($0) bpm" } ?? "--"),
            .init(label: L10n.t("代谢当量", "Metabolic Equivalent"), value: TelemetryFieldFactory.format(d.metabolicEquivalent, unit: "", digits: 1)),
            .init(label: L10n.t("已用时间", "Elapsed Time"), value: d.elapsedTimeSec.map { "\($0) s" } ?? "--"),
            .init(label: L10n.t("剩余时间", "Remaining Time"), value: d.remainingTimeSec.map { "\($0) s" } ?? "--")
        ]
    }

    private var statusRows: [TelemetryField] {
        var rows: [TelemetryField] = []
        if let statusEvent {
            rows.append(.init(label: L10n.t("状态事件 OpCode", "Status Event OpCode"), value: String(format: "0x%02X · %@", statusEvent.opCode, statusName(statusEvent.opCode))))
            rows.append(.init(label: L10n.t("状态参数", "Status Parameters"), value: statusEvent.parameterBytes.isEmpty ? "--" : statusEvent.parameterBytes.map { String(format: "%02X", $0) }.joined(separator: " ")))
        }
        if let trainingStatus {
            rows.append(.init(label: L10n.t("训练状态", "Training Status"), value: "\(trainingStatus.statusCode) · \(trainingStatus.stringCode)"))
        }
        if let featureSet {
            rows.append(.init(label: L10n.t("特征位(Fitness Machine)", "Feature Bits (Machine)"), value: String(format: "0x%08X", featureSet.machineFeaturesRaw)))
            rows.append(.init(label: L10n.t("特征位(Target Setting)", "Feature Bits (Target)"), value: String(format: "0x%08X", featureSet.targetSettingFeaturesRaw)))
        }
        if let resistanceRange {
            rows.append(.init(label: L10n.t("支持阻力范围", "Supported Resistance Range"), value: "\(resistanceRange.minimum) ... \(resistanceRange.maximum) (step \(resistanceRange.increment))"))
        }
        if let powerRange {
            rows.append(.init(label: L10n.t("支持功率范围", "Supported Power Range"), value: "\(powerRange.minimum) ... \(powerRange.maximum) W (step \(powerRange.increment))"))
        }
        if rows.isEmpty {
            rows += TelemetryFieldFactory.noDataRows(label: L10n.t("状态/特征", "Status/Features"))
        }
        return rows
    }

    private var rawRows: [TelemetryField] {
        TelemetryFieldFactory.rawRows(from: rawCharacteristicHex)
    }

    var body: some View {
        TelemetryFieldPanel(
            title: L10n.t("Fitness Machine Service 字段（1826）", "Fitness Machine Service Fields (1826)"),
            sections: [
                .init(title: L10n.t("Indoor Bike Data (2AD2)", "Indoor Bike Data (2AD2)"), rows: indoorRows),
                .init(title: L10n.t("Status / Feature", "Status / Feature"), rows: statusRows),
                .init(title: L10n.t("Raw Characteristic Cache", "Raw Characteristic Cache"), rows: rawRows)
            ]
        )
    }

    private func statusName(_ opCode: UInt8) -> String {
        switch opCode {
        case 0x01: return "reset"
        case 0x02: return "stopped_or_paused"
        case 0x03: return "stopped_by_safety_key"
        case 0x04: return "started_or_resumed"
        case 0x05: return "target_speed_changed"
        case 0x06: return "target_inclination_changed"
        case 0x07: return "target_resistance_changed"
        case 0x08: return "target_power_changed"
        case 0x09: return "target_hr_changed"
        case 0x0A: return "target_expended_energy_changed"
        case 0x0B: return "target_steps_changed"
        case 0x0C: return "target_strides_changed"
        case 0x0D: return "target_distance_changed"
        case 0x0E: return "target_training_time_changed"
        case 0x0F: return "target_time_in_two_hr_zones_changed"
        case 0x10: return "target_time_in_three_hr_zones_changed"
        case 0x11: return "target_time_in_five_hr_zones_changed"
        case 0x12: return "indoor_bike_simulation_params_changed"
        case 0x13: return "wheel_circumference_changed"
        case 0x14: return "spin_down_status"
        case 0x15: return "target_cadence_changed"
        default: return "unknown_\(opCode)"
        }
    }

}
