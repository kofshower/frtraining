import Foundation

public struct HeartRateMeasurementFlags: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let valueFormatUInt16 = Self(rawValue: 1 << 0)
    public static let sensorContactStatusBit = Self(rawValue: 1 << 1)
    public static let sensorContactSupportedBit = Self(rawValue: 1 << 2)
    public static let energyExpendedPresent = Self(rawValue: 1 << 3)
    public static let rrIntervalPresent = Self(rawValue: 1 << 4)
}

public struct HeartRateMeasurement: Equatable, Sendable {
    public let flags: HeartRateMeasurementFlags
    public let heartRateBPM: Int
    public let valueIsUInt16: Bool
    public let sensorContactSupported: Bool
    public let sensorContactDetected: Bool?
    public let energyExpendedKJ: Int?
    public let rrIntervals1024: [UInt16]
    public let rrIntervalsMS: [Double]
    public let latestRRIntervalMS: Double?

    public init(
        flags: HeartRateMeasurementFlags,
        heartRateBPM: Int,
        valueIsUInt16: Bool,
        sensorContactSupported: Bool,
        sensorContactDetected: Bool?,
        energyExpendedKJ: Int?,
        rrIntervals1024: [UInt16],
        rrIntervalsMS: [Double],
        latestRRIntervalMS: Double?
    ) {
        self.flags = flags
        self.heartRateBPM = heartRateBPM
        self.valueIsUInt16 = valueIsUInt16
        self.sensorContactSupported = sensorContactSupported
        self.sensorContactDetected = sensorContactDetected
        self.energyExpendedKJ = energyExpendedKJ
        self.rrIntervals1024 = rrIntervals1024
        self.rrIntervalsMS = rrIntervalsMS
        self.latestRRIntervalMS = latestRRIntervalMS
    }
}

public enum HeartRateBodySensorLocation: Equatable, Sendable {
    case other
    case chest
    case wrist
    case finger
    case hand
    case earLobe
    case foot
    case unknown(UInt8)

    public var rawValue: UInt8 {
        switch self {
        case .other: return 0
        case .chest: return 1
        case .wrist: return 2
        case .finger: return 3
        case .hand: return 4
        case .earLobe: return 5
        case .foot: return 6
        case let .unknown(value): return value
        }
    }

    public var stringCode: String {
        switch self {
        case .other: return "other"
        case .chest: return "chest"
        case .wrist: return "wrist"
        case .finger: return "finger"
        case .hand: return "hand"
        case .earLobe: return "ear_lobe"
        case .foot: return "foot"
        case .unknown(let value): return "unknown_\(value)"
        }
    }
}

public enum HeartRateParsers {
    public static func parseMeasurement(_ data: Data) -> HeartRateMeasurement? {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }

        let flags = HeartRateMeasurementFlags(rawValue: bytes[0])
        var index = 1

        let valueIsUInt16 = flags.contains(.valueFormatUInt16)
        let heartRateBPM: Int
        if valueIsUInt16 {
            guard index + 2 <= bytes.count else { return nil }
            let raw = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            heartRateBPM = Int(raw)
            index += 2
        } else {
            guard index + 1 <= bytes.count else { return nil }
            heartRateBPM = Int(bytes[index])
            index += 1
        }

        let sensorContactSupported = flags.contains(.sensorContactSupportedBit)
        let sensorContactDetected: Bool? = sensorContactSupported ? flags.contains(.sensorContactStatusBit) : nil

        var energyExpendedKJ: Int?
        if flags.contains(.energyExpendedPresent) {
            guard index + 2 <= bytes.count else { return nil }
            let raw = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            energyExpendedKJ = Int(raw)
            index += 2
        }

        var rrIntervals1024: [UInt16] = []
        var rrIntervalsMS: [Double] = []
        if flags.contains(.rrIntervalPresent) {
            while index + 2 <= bytes.count {
                let raw = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
                rrIntervals1024.append(raw)
                rrIntervalsMS.append(Double(raw) * 1000.0 / 1024.0)
                index += 2
            }
        }

        return HeartRateMeasurement(
            flags: flags,
            heartRateBPM: heartRateBPM,
            valueIsUInt16: valueIsUInt16,
            sensorContactSupported: sensorContactSupported,
            sensorContactDetected: sensorContactDetected,
            energyExpendedKJ: energyExpendedKJ,
            rrIntervals1024: rrIntervals1024,
            rrIntervalsMS: rrIntervalsMS,
            latestRRIntervalMS: rrIntervalsMS.last
        )
    }

    public static func parseBodySensorLocation(_ data: Data) -> HeartRateBodySensorLocation? {
        guard let raw = data.first else { return nil }
        switch raw {
        case 0: return .other
        case 1: return .chest
        case 2: return .wrist
        case 3: return .finger
        case 4: return .hand
        case 5: return .earLobe
        case 6: return .foot
        default: return .unknown(raw)
        }
    }
}
