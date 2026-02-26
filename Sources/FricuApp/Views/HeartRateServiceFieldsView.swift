import SwiftUI
import FricuCore

struct HeartRateServiceFieldsView: View {
    let measurement: HeartRateMeasurement?
    let bodySensorLocation: HeartRateBodySensorLocation?
    let controlPointAvailable: Bool
    let rawCharacteristicHex: [String: String]

    private var measurementRows: [TelemetryField] {
        guard let measurement else {
            return TelemetryFieldFactory.noDataRows(label: L10n.t("测量值(2A37)", "Measurement (2A37)"))
        }

        let contactText: String
        if measurement.sensorContactSupported {
            if let detected = measurement.sensorContactDetected {
                contactText = detected ? L10n.t("支持，已检测到接触", "Supported, contact detected") : L10n.t("支持，未检测到接触", "Supported, contact not detected")
            } else {
                contactText = L10n.t("支持", "Supported")
            }
        } else {
            contactText = L10n.t("不支持", "Not supported")
        }

        let rrList: String
        if measurement.rrIntervalsMS.isEmpty {
            rrList = "--"
        } else {
            rrList = measurement.rrIntervalsMS
                .prefix(8)
                .map { String(format: "%.0f", $0) }
                .joined(separator: ", ")
                + " ms"
        }

        return [
            .init(label: L10n.t("Flags", "Flags"), value: String(format: "0x%02X", measurement.flags.rawValue)),
            .init(label: L10n.t("心率值", "Heart Rate"), value: "\(measurement.heartRateBPM) bpm"),
            .init(label: L10n.t("心率格式", "Value Format"), value: measurement.valueIsUInt16 ? "UInt16" : "UInt8"),
            .init(label: L10n.t("传感器接触", "Sensor Contact"), value: contactText),
            .init(label: L10n.t("累计消耗能量", "Energy Expended"), value: measurement.energyExpendedKJ.map { "\($0) kJ" } ?? "--"),
            .init(label: L10n.t("RR 间期数量", "RR Count"), value: "\(measurement.rrIntervalsMS.count)"),
            .init(label: L10n.t("最新 RR 间期", "Latest RR"), value: measurement.latestRRIntervalMS.map { String(format: "%.0f ms", $0) } ?? "--"),
            .init(label: L10n.t("RR 间期列表", "RR Intervals"), value: rrList)
        ]
    }

    private var profileRows: [TelemetryField] {
        let bodyLocation: String
        if let bodySensorLocation {
            bodyLocation = "\(bodySensorLocation.stringCode) (\(bodySensorLocation.rawValue))"
        } else {
            bodyLocation = "--"
        }

        return [
            .init(label: L10n.t("身体佩戴位置(2A38)", "Body Sensor Location (2A38)"), value: bodyLocation),
            .init(label: L10n.t("控制点(2A39)", "Control Point (2A39)"), value: controlPointAvailable ? L10n.t("可写", "Writable") : L10n.t("不可用/不可写", "Unavailable/Not writable"))
        ]
    }

    private var rawRows: [TelemetryField] {
        TelemetryFieldFactory.rawRows(from: rawCharacteristicHex)
    }

    var body: some View {
        TelemetryFieldPanel(
            title: L10n.t("Heart Rate Service 字段（180D）", "Heart Rate Service Fields (180D)"),
            sections: [
                .init(title: L10n.t("测量值", "Measurement"), rows: measurementRows, minimumColumnWidth: 260),
                .init(title: L10n.t("设备信息", "Device Info"), rows: profileRows, minimumColumnWidth: 260),
                .init(title: L10n.t("Raw Characteristic Cache", "Raw Characteristic Cache"), rows: rawRows, minimumColumnWidth: 260)
            ]
        )
    }
}
