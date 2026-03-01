import Foundation

public struct CyclingPowerMeasurementFlags: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let pedalPowerBalancePresent = Self(rawValue: 1 << 0)
    public static let pedalPowerBalanceReference = Self(rawValue: 1 << 1)
    public static let accumulatedTorquePresent = Self(rawValue: 1 << 2)
    public static let accumulatedTorqueSource = Self(rawValue: 1 << 3)
    public static let wheelRevolutionDataPresent = Self(rawValue: 1 << 4)
    public static let crankRevolutionDataPresent = Self(rawValue: 1 << 5)
    public static let extremeForceMagnitudesPresent = Self(rawValue: 1 << 6)
    public static let extremeTorqueMagnitudesPresent = Self(rawValue: 1 << 7)
    public static let extremeAnglesPresent = Self(rawValue: 1 << 8)
    public static let topDeadSpotAnglePresent = Self(rawValue: 1 << 9)
    public static let bottomDeadSpotAnglePresent = Self(rawValue: 1 << 10)
    public static let accumulatedEnergyPresent = Self(rawValue: 1 << 11)
    public static let offsetCompensationIndicator = Self(rawValue: 1 << 12)
}

public enum CyclingPowerTorqueSource: String, Equatable, Sendable {
    case wheelBased
    case crankBased
}

public struct CyclingPowerMeasurement: Equatable, Sendable {
    public let flags: CyclingPowerMeasurementFlags
    public let instantaneousPowerWatts: Int

    public let pedalPowerBalancePercent: Double?
    public let pedalPowerBalanceReferenceIsRight: Bool?
    public let estimatedLeftBalancePercent: Double?
    public let estimatedRightBalancePercent: Double?

    public let accumulatedTorqueNm: Double?
    public let accumulatedTorqueSource: CyclingPowerTorqueSource?

    public let cumulativeWheelRevolutions: UInt32?
    public let lastWheelEventTime1024: UInt16?
    public let cumulativeCrankRevolutions: UInt16?
    public let lastCrankEventTime1024: UInt16?

    public let maximumForceNewton: Int?
    public let minimumForceNewton: Int?
    public let maximumTorqueNm: Double?
    public let minimumTorqueNm: Double?

    public let maximumAngleDegrees: Double?
    public let minimumAngleDegrees: Double?
    public let topDeadSpotAngleDegrees: Double?
    public let bottomDeadSpotAngleDegrees: Double?

    public let accumulatedEnergyKJ: Int?
    public let offsetCompensationIndicator: Bool

    public init(
        flags: CyclingPowerMeasurementFlags,
        instantaneousPowerWatts: Int,
        pedalPowerBalancePercent: Double?,
        pedalPowerBalanceReferenceIsRight: Bool?,
        estimatedLeftBalancePercent: Double?,
        estimatedRightBalancePercent: Double?,
        accumulatedTorqueNm: Double?,
        accumulatedTorqueSource: CyclingPowerTorqueSource?,
        cumulativeWheelRevolutions: UInt32?,
        lastWheelEventTime1024: UInt16?,
        cumulativeCrankRevolutions: UInt16?,
        lastCrankEventTime1024: UInt16?,
        maximumForceNewton: Int?,
        minimumForceNewton: Int?,
        maximumTorqueNm: Double?,
        minimumTorqueNm: Double?,
        maximumAngleDegrees: Double?,
        minimumAngleDegrees: Double?,
        topDeadSpotAngleDegrees: Double?,
        bottomDeadSpotAngleDegrees: Double?,
        accumulatedEnergyKJ: Int?,
        offsetCompensationIndicator: Bool
    ) {
        self.flags = flags
        self.instantaneousPowerWatts = instantaneousPowerWatts
        self.pedalPowerBalancePercent = pedalPowerBalancePercent
        self.pedalPowerBalanceReferenceIsRight = pedalPowerBalanceReferenceIsRight
        self.estimatedLeftBalancePercent = estimatedLeftBalancePercent
        self.estimatedRightBalancePercent = estimatedRightBalancePercent
        self.accumulatedTorqueNm = accumulatedTorqueNm
        self.accumulatedTorqueSource = accumulatedTorqueSource
        self.cumulativeWheelRevolutions = cumulativeWheelRevolutions
        self.lastWheelEventTime1024 = lastWheelEventTime1024
        self.cumulativeCrankRevolutions = cumulativeCrankRevolutions
        self.lastCrankEventTime1024 = lastCrankEventTime1024
        self.maximumForceNewton = maximumForceNewton
        self.minimumForceNewton = minimumForceNewton
        self.maximumTorqueNm = maximumTorqueNm
        self.minimumTorqueNm = minimumTorqueNm
        self.maximumAngleDegrees = maximumAngleDegrees
        self.minimumAngleDegrees = minimumAngleDegrees
        self.topDeadSpotAngleDegrees = topDeadSpotAngleDegrees
        self.bottomDeadSpotAngleDegrees = bottomDeadSpotAngleDegrees
        self.accumulatedEnergyKJ = accumulatedEnergyKJ
        self.offsetCompensationIndicator = offsetCompensationIndicator
    }
}

public enum CyclingPowerMeasurementParser {
    public static func parse(_ data: Data) -> CyclingPowerMeasurement? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }

        var reader = ByteReader(bytes: bytes)
        guard let rawFlags = reader.readUInt16(),
              let powerRaw = reader.readInt16()
        else {
            return nil
        }

        let flags = CyclingPowerMeasurementFlags(rawValue: rawFlags)
        let instantaneousPowerWatts = Int(powerRaw)

        var pedalPowerBalancePercent: Double?
        var pedalPowerBalanceReferenceIsRight: Bool?
        var estimatedLeftBalancePercent: Double?
        var estimatedRightBalancePercent: Double?

        if flags.contains(.pedalPowerBalancePresent) {
            guard let raw = reader.readUInt8() else { return nil }
            // CPS pedal balance uses 0.5% resolution and valid range 0...200.
            // Values above 200 are reserved/invalid and should be ignored.
            if raw <= 200 {
                let balancePercent = Double(raw) * 0.5
                let referenceIsRight = flags.contains(.pedalPowerBalanceReference)
                let right = referenceIsRight ? balancePercent : (100.0 - balancePercent)
                let left = 100.0 - right
                pedalPowerBalancePercent = balancePercent
                pedalPowerBalanceReferenceIsRight = referenceIsRight
                estimatedLeftBalancePercent = max(0.0, min(100.0, left))
                estimatedRightBalancePercent = max(0.0, min(100.0, right))
            }
        }

        var accumulatedTorqueNm: Double?
        var accumulatedTorqueSource: CyclingPowerTorqueSource?
        if flags.contains(.accumulatedTorquePresent) {
            guard let raw = reader.readUInt16() else { return nil }
            accumulatedTorqueNm = Double(raw) / 32.0
            accumulatedTorqueSource = flags.contains(.accumulatedTorqueSource) ? .crankBased : .wheelBased
        }

        var cumulativeWheelRevolutions: UInt32?
        var lastWheelEventTime1024: UInt16?
        if flags.contains(.wheelRevolutionDataPresent) {
            guard let revs = reader.readUInt32(),
                  let eventTime = reader.readUInt16()
            else { return nil }
            cumulativeWheelRevolutions = revs
            lastWheelEventTime1024 = eventTime
        }

        var cumulativeCrankRevolutions: UInt16?
        var lastCrankEventTime1024: UInt16?
        if flags.contains(.crankRevolutionDataPresent) {
            guard let revs = reader.readUInt16(),
                  let eventTime = reader.readUInt16()
            else { return nil }
            cumulativeCrankRevolutions = revs
            lastCrankEventTime1024 = eventTime
        }

        var maximumForceNewton: Int?
        var minimumForceNewton: Int?
        if flags.contains(.extremeForceMagnitudesPresent) {
            guard let maxForce = reader.readInt16(),
                  let minForce = reader.readInt16()
            else { return nil }
            maximumForceNewton = Int(maxForce)
            minimumForceNewton = Int(minForce)
        }

        var maximumTorqueNm: Double?
        var minimumTorqueNm: Double?
        if flags.contains(.extremeTorqueMagnitudesPresent) {
            guard let maxTorque = reader.readInt16(),
                  let minTorque = reader.readInt16()
            else { return nil }
            maximumTorqueNm = Double(maxTorque) / 32.0
            minimumTorqueNm = Double(minTorque) / 32.0
        }

        var maximumAngleDegrees: Double?
        var minimumAngleDegrees: Double?
        if flags.contains(.extremeAnglesPresent) {
            guard let packed = reader.readUInt24() else { return nil }
            let maxRaw = Int(packed & 0x0FFF)
            let minRaw = Int((packed >> 12) & 0x0FFF)
            maximumAngleDegrees = Double(maxRaw) * (360.0 / 4096.0)
            minimumAngleDegrees = Double(minRaw) * (360.0 / 4096.0)
        }

        var topDeadSpotAngleDegrees: Double?
        if flags.contains(.topDeadSpotAnglePresent) {
            guard let raw = reader.readUInt16() else { return nil }
            topDeadSpotAngleDegrees = Double(raw) * 0.5
        }

        var bottomDeadSpotAngleDegrees: Double?
        if flags.contains(.bottomDeadSpotAnglePresent) {
            guard let raw = reader.readUInt16() else { return nil }
            bottomDeadSpotAngleDegrees = Double(raw) * 0.5
        }

        var accumulatedEnergyKJ: Int?
        if flags.contains(.accumulatedEnergyPresent) {
            guard let raw = reader.readUInt16() else { return nil }
            accumulatedEnergyKJ = Int(raw)
        }

        return CyclingPowerMeasurement(
            flags: flags,
            instantaneousPowerWatts: instantaneousPowerWatts,
            pedalPowerBalancePercent: pedalPowerBalancePercent,
            pedalPowerBalanceReferenceIsRight: pedalPowerBalanceReferenceIsRight,
            estimatedLeftBalancePercent: estimatedLeftBalancePercent,
            estimatedRightBalancePercent: estimatedRightBalancePercent,
            accumulatedTorqueNm: accumulatedTorqueNm,
            accumulatedTorqueSource: accumulatedTorqueSource,
            cumulativeWheelRevolutions: cumulativeWheelRevolutions,
            lastWheelEventTime1024: lastWheelEventTime1024,
            cumulativeCrankRevolutions: cumulativeCrankRevolutions,
            lastCrankEventTime1024: lastCrankEventTime1024,
            maximumForceNewton: maximumForceNewton,
            minimumForceNewton: minimumForceNewton,
            maximumTorqueNm: maximumTorqueNm,
            minimumTorqueNm: minimumTorqueNm,
            maximumAngleDegrees: maximumAngleDegrees,
            minimumAngleDegrees: minimumAngleDegrees,
            topDeadSpotAngleDegrees: topDeadSpotAngleDegrees,
            bottomDeadSpotAngleDegrees: bottomDeadSpotAngleDegrees,
            accumulatedEnergyKJ: accumulatedEnergyKJ,
            offsetCompensationIndicator: flags.contains(.offsetCompensationIndicator)
        )
    }
}

private struct ByteReader {
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
