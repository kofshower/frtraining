import Foundation

public struct IndoorBikeDataFlags: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let moreData = Self(rawValue: 1 << 0)
    public static let averageSpeedPresent = Self(rawValue: 1 << 1)
    public static let instantaneousCadencePresent = Self(rawValue: 1 << 2)
    public static let averageCadencePresent = Self(rawValue: 1 << 3)
    public static let totalDistancePresent = Self(rawValue: 1 << 4)
    public static let resistanceLevelPresent = Self(rawValue: 1 << 5)
    public static let instantaneousPowerPresent = Self(rawValue: 1 << 6)
    public static let averagePowerPresent = Self(rawValue: 1 << 7)
    public static let expendedEnergyPresent = Self(rawValue: 1 << 8)
    public static let heartRatePresent = Self(rawValue: 1 << 9)
    public static let metabolicEquivalentPresent = Self(rawValue: 1 << 10)
    public static let elapsedTimePresent = Self(rawValue: 1 << 11)
    public static let remainingTimePresent = Self(rawValue: 1 << 12)
}

public struct IndoorBikeDataMeasurement: Equatable, Sendable {
    public let flags: IndoorBikeDataFlags

    public let instantaneousSpeedKPH: Double?
    public let averageSpeedKPH: Double?
    public let instantaneousCadenceRPM: Double?
    public let averageCadenceRPM: Double?
    public let totalDistanceMeters: Int?
    public let resistanceLevel: Int?
    public let instantaneousPowerWatts: Int?
    public let averagePowerWatts: Int?

    public let totalEnergyKCal: Int?
    public let energyPerHourKCal: Int?
    public let energyPerMinuteKCal: Int?

    public let heartRateBPM: Int?
    public let metabolicEquivalent: Double?
    public let elapsedTimeSec: Int?
    public let remainingTimeSec: Int?

    public init(
        flags: IndoorBikeDataFlags,
        instantaneousSpeedKPH: Double?,
        averageSpeedKPH: Double?,
        instantaneousCadenceRPM: Double?,
        averageCadenceRPM: Double?,
        totalDistanceMeters: Int?,
        resistanceLevel: Int?,
        instantaneousPowerWatts: Int?,
        averagePowerWatts: Int?,
        totalEnergyKCal: Int?,
        energyPerHourKCal: Int?,
        energyPerMinuteKCal: Int?,
        heartRateBPM: Int?,
        metabolicEquivalent: Double?,
        elapsedTimeSec: Int?,
        remainingTimeSec: Int?
    ) {
        self.flags = flags
        self.instantaneousSpeedKPH = instantaneousSpeedKPH
        self.averageSpeedKPH = averageSpeedKPH
        self.instantaneousCadenceRPM = instantaneousCadenceRPM
        self.averageCadenceRPM = averageCadenceRPM
        self.totalDistanceMeters = totalDistanceMeters
        self.resistanceLevel = resistanceLevel
        self.instantaneousPowerWatts = instantaneousPowerWatts
        self.averagePowerWatts = averagePowerWatts
        self.totalEnergyKCal = totalEnergyKCal
        self.energyPerHourKCal = energyPerHourKCal
        self.energyPerMinuteKCal = energyPerMinuteKCal
        self.heartRateBPM = heartRateBPM
        self.metabolicEquivalent = metabolicEquivalent
        self.elapsedTimeSec = elapsedTimeSec
        self.remainingTimeSec = remainingTimeSec
    }
}

public struct FitnessMachineFeatureSet: Equatable, Sendable {
    public let machineFeaturesRaw: UInt32
    public let targetSettingFeaturesRaw: UInt32
}

public struct FitnessMachineSupportedRange: Equatable, Sendable {
    public let minimum: Int
    public let maximum: Int
    public let increment: Int
}

public struct FitnessMachineStatusEvent: Equatable, Sendable {
    public let opCode: UInt8
    public let parameterBytes: [UInt8]
}

public struct FitnessMachineTrainingStatus: Equatable, Sendable {
    public let statusCode: UInt8
    public let stringCode: String
}

public enum FitnessMachineParsers {
    public static func parseIndoorBikeData(_ data: Data) -> IndoorBikeDataMeasurement? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }

        var reader = GenericByteReader(bytes: bytes)
        guard let rawFlags = reader.readUInt16() else { return nil }
        let flags = IndoorBikeDataFlags(rawValue: rawFlags)

        var instantaneousSpeedKPH: Double?
        if !flags.contains(.moreData) {
            guard let raw = reader.readUInt16() else { return nil }
            instantaneousSpeedKPH = Double(raw) / 100.0
        }

        var averageSpeedKPH: Double?
        if flags.contains(.averageSpeedPresent) {
            guard let raw = reader.readUInt16() else { return nil }
            averageSpeedKPH = Double(raw) / 100.0
        }

        var instantaneousCadenceRPM: Double?
        if flags.contains(.instantaneousCadencePresent) {
            guard let raw = reader.readUInt16() else { return nil }
            instantaneousCadenceRPM = Double(raw) / 2.0
        }

        var averageCadenceRPM: Double?
        if flags.contains(.averageCadencePresent) {
            guard let raw = reader.readUInt16() else { return nil }
            averageCadenceRPM = Double(raw) / 2.0
        }

        var totalDistanceMeters: Int?
        if flags.contains(.totalDistancePresent) {
            guard let raw = reader.readUInt24() else { return nil }
            totalDistanceMeters = Int(raw)
        }

        var resistanceLevel: Int?
        if flags.contains(.resistanceLevelPresent) {
            guard let raw = reader.readInt16() else { return nil }
            resistanceLevel = Int(raw)
        }

        var instantaneousPowerWatts: Int?
        if flags.contains(.instantaneousPowerPresent) {
            guard let raw = reader.readInt16() else { return nil }
            instantaneousPowerWatts = Int(raw)
        }

        var averagePowerWatts: Int?
        if flags.contains(.averagePowerPresent) {
            guard let raw = reader.readInt16() else { return nil }
            averagePowerWatts = Int(raw)
        }

        var totalEnergyKCal: Int?
        var energyPerHourKCal: Int?
        var energyPerMinuteKCal: Int?
        if flags.contains(.expendedEnergyPresent) {
            guard let total = reader.readUInt16(),
                  let perHour = reader.readUInt16(),
                  let perMinute = reader.readUInt8()
            else { return nil }
            totalEnergyKCal = Int(total)
            energyPerHourKCal = Int(perHour)
            energyPerMinuteKCal = Int(perMinute)
        }

        var heartRateBPM: Int?
        if flags.contains(.heartRatePresent) {
            guard let raw = reader.readUInt8() else { return nil }
            heartRateBPM = Int(raw)
        }

        var metabolicEquivalent: Double?
        if flags.contains(.metabolicEquivalentPresent) {
            guard let raw = reader.readUInt8() else { return nil }
            metabolicEquivalent = Double(raw) / 10.0
        }

        var elapsedTimeSec: Int?
        if flags.contains(.elapsedTimePresent) {
            guard let raw = reader.readUInt16() else { return nil }
            elapsedTimeSec = Int(raw)
        }

        var remainingTimeSec: Int?
        if flags.contains(.remainingTimePresent) {
            guard let raw = reader.readUInt16() else { return nil }
            remainingTimeSec = Int(raw)
        }

        return IndoorBikeDataMeasurement(
            flags: flags,
            instantaneousSpeedKPH: instantaneousSpeedKPH,
            averageSpeedKPH: averageSpeedKPH,
            instantaneousCadenceRPM: instantaneousCadenceRPM,
            averageCadenceRPM: averageCadenceRPM,
            totalDistanceMeters: totalDistanceMeters,
            resistanceLevel: resistanceLevel,
            instantaneousPowerWatts: instantaneousPowerWatts,
            averagePowerWatts: averagePowerWatts,
            totalEnergyKCal: totalEnergyKCal,
            energyPerHourKCal: energyPerHourKCal,
            energyPerMinuteKCal: energyPerMinuteKCal,
            heartRateBPM: heartRateBPM,
            metabolicEquivalent: metabolicEquivalent,
            elapsedTimeSec: elapsedTimeSec,
            remainingTimeSec: remainingTimeSec
        )
    }

    public static func parseFitnessMachineFeature(_ data: Data) -> FitnessMachineFeatureSet? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }
        var reader = GenericByteReader(bytes: bytes)
        guard let machine = reader.readUInt32(),
              let target = reader.readUInt32()
        else { return nil }
        return FitnessMachineFeatureSet(machineFeaturesRaw: machine, targetSettingFeaturesRaw: target)
    }

    public static func parseSupportedRange(_ data: Data) -> FitnessMachineSupportedRange? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        var reader = GenericByteReader(bytes: bytes)
        guard let minimum = reader.readInt16(),
              let maximum = reader.readInt16(),
              let increment = reader.readUInt16()
        else { return nil }
        return FitnessMachineSupportedRange(
            minimum: Int(minimum),
            maximum: Int(maximum),
            increment: Int(increment)
        )
    }

    public static func parseFitnessMachineStatus(_ data: Data) -> FitnessMachineStatusEvent? {
        let bytes = [UInt8](data)
        guard let opCode = bytes.first else { return nil }
        return FitnessMachineStatusEvent(opCode: opCode, parameterBytes: Array(bytes.dropFirst()))
    }

    public static func parseTrainingStatus(_ data: Data) -> FitnessMachineTrainingStatus? {
        let bytes = [UInt8](data)
        guard let status = bytes.first else { return nil }
        return FitnessMachineTrainingStatus(
            statusCode: status,
            stringCode: trainingStatusStringCode(status)
        )
    }

    public static func trainingStatusStringCode(_ status: UInt8) -> String {
        switch status {
        case 0x00: return "other"
        case 0x01: return "idle"
        case 0x02: return "warming_up"
        case 0x03: return "low_intensity"
        case 0x04: return "interval"
        case 0x05: return "high_intensity"
        case 0x06: return "recovery"
        case 0x07: return "isometric"
        case 0x08: return "heart_rate_control"
        case 0x09: return "fitness_test"
        case 0x0A: return "speed_outside_control_region"
        case 0x0B: return "cool_down"
        case 0x0C: return "watt_control"
        case 0x0D: return "manual_mode"
        case 0x0E: return "pre_workout"
        case 0x0F: return "post_workout"
        default: return "unknown_\(status)"
        }
    }
}

private struct GenericByteReader {
    private let bytes: [UInt8]
    private(set) var index: Int = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func readUInt8() -> UInt8? {
        guard index + 1 <= bytes.count else { return nil }
        defer { index += 1 }
        return bytes[index]
    }

    mutating func readUInt16() -> UInt16? {
        guard index + 2 <= bytes.count else { return nil }
        defer { index += 2 }
        return UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    mutating func readUInt24() -> UInt32? {
        guard index + 3 <= bytes.count else { return nil }
        defer { index += 3 }
        return UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
    }

    mutating func readUInt32() -> UInt32? {
        guard index + 4 <= bytes.count else { return nil }
        defer { index += 4 }
        return UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }

    mutating func readInt16() -> Int16? {
        guard let raw = readUInt16() else { return nil }
        return Int16(bitPattern: raw)
    }
}
