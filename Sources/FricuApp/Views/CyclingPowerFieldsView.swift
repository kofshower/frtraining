import SwiftUI
import FricuCore

struct CyclingPowerFieldsView: View {
    let title: String
    let measurement: CyclingPowerMeasurement

    private var rows: [TelemetryField] {
        let refText: String
        if let isRight = measurement.pedalPowerBalanceReferenceIsRight {
            refText = isRight ? L10n.t("右侧参考", "Right-referenced") : L10n.t("左侧参考", "Left-referenced")
        } else {
            refText = "--"
        }

        let balanceText: String
        if let percent = measurement.pedalPowerBalancePercent {
            balanceText = String(format: "%.1f%% · %@", percent, refText)
        } else {
            balanceText = "--"
        }

        let lrText: String
        if let left = measurement.estimatedLeftBalancePercent,
           let right = measurement.estimatedRightBalancePercent {
            lrText = String(format: "L%.1f%% / R%.1f%%", left, right)
        } else {
            lrText = "--"
        }

        let forceText: String
        if let maxForce = measurement.maximumForceNewton,
           let minForce = measurement.minimumForceNewton {
            forceText = "\(maxForce) / \(minForce) N"
        } else {
            forceText = "--"
        }

        let torqueText: String
        if let maxTorque = measurement.maximumTorqueNm,
           let minTorque = measurement.minimumTorqueNm {
            torqueText = String(format: "%.2f / %.2f Nm", maxTorque, minTorque)
        } else {
            torqueText = "--"
        }

        let extremeAngleText: String
        if let maxAngle = measurement.maximumAngleDegrees,
           let minAngle = measurement.minimumAngleDegrees {
            extremeAngleText = String(format: "%.1f° / %.1f°", maxAngle, minAngle)
        } else {
            extremeAngleText = "--"
        }

        let torqueSource: String
        if let source = measurement.accumulatedTorqueSource {
            switch source {
            case .wheelBased: torqueSource = L10n.t("轮基", "Wheel-based")
            case .crankBased: torqueSource = L10n.t("曲柄基", "Crank-based")
            }
        } else {
            torqueSource = "--"
        }

        return [
            .init(label: L10n.t("标志位", "Flags"), value: String(format: "0x%04X", measurement.flags.rawValue)),
            .init(label: L10n.t("瞬时功率", "Instantaneous Power"), value: "\(measurement.instantaneousPowerWatts) W"),
            .init(label: L10n.t("踏板平衡", "Pedal Balance"), value: balanceText),
            .init(label: L10n.t("估算左右平衡", "Estimated L/R"), value: lrText),
            .init(label: L10n.t("累计扭矩", "Accumulated Torque"), value: TelemetryFieldFactory.format(measurement.accumulatedTorqueNm, unit: " Nm", digits: 2)),
            .init(label: L10n.t("扭矩来源", "Torque Source"), value: torqueSource),
            .init(label: L10n.t("累计轮转", "Wheel Revolutions"), value: measurement.cumulativeWheelRevolutions.map { "\($0)" } ?? "--"),
            .init(label: L10n.t("轮事件时间", "Wheel Event Time"), value: measurement.lastWheelEventTime1024.map { "\($0) /1024s" } ?? "--"),
            .init(label: L10n.t("累计曲柄转", "Crank Revolutions"), value: measurement.cumulativeCrankRevolutions.map { "\($0)" } ?? "--"),
            .init(label: L10n.t("曲柄事件时间", "Crank Event Time"), value: measurement.lastCrankEventTime1024.map { "\($0) /1024s" } ?? "--"),
            .init(label: L10n.t("极值力(最大/最小)", "Extreme Force (Max/Min)"), value: forceText),
            .init(label: L10n.t("极值扭矩(最大/最小)", "Extreme Torque (Max/Min)"), value: torqueText),
            .init(label: L10n.t("极值角(最大/最小)", "Extreme Angle (Max/Min)"), value: extremeAngleText),
            .init(label: L10n.t("上死点角", "Top Dead Spot"), value: TelemetryFieldFactory.format(measurement.topDeadSpotAngleDegrees, unit: "°")),
            .init(label: L10n.t("下死点角", "Bottom Dead Spot"), value: TelemetryFieldFactory.format(measurement.bottomDeadSpotAngleDegrees, unit: "°")),
            .init(label: L10n.t("累计能量", "Accumulated Energy"), value: measurement.accumulatedEnergyKJ.map { "\($0) kJ" } ?? "--"),
            .init(label: L10n.t("偏移补偿标记", "Offset Compensation"), value: measurement.offsetCompensationIndicator ? L10n.t("是", "Yes") : L10n.t("否", "No"))
        ]
    }

    var body: some View {
        TelemetryFieldPanel(
            title: title,
            sections: [.init(title: L10n.t("Cycling Power Measurement", "Cycling Power Measurement"), rows: rows)]
        )
    }
}
