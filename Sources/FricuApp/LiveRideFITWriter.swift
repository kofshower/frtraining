import Foundation

struct LiveRideSample {
    var timestamp: Date
    var powerWatts: Int?
    var heartRateBPM: Int?
    var cadenceRPM: Double?
    var speedKPH: Double?
    var distanceMeters: Double
    var leftBalancePercent: Double?
    var rightBalancePercent: Double?
}

struct LiveRideSummary {
    var startDate: Date
    var endDate: Date
    var sport: SportType
    var totalElapsedSec: Int
    var totalTimerSec: Int
    var totalDistanceMeters: Double
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var averagePower: Int?
    var maxPower: Int?
    var normalizedPower: Int?
}

enum LiveRideFITWriter {
    private struct FieldDef {
        var number: UInt8
        var size: UInt8
        var baseType: UInt8
    }

    private enum FITBaseType {
        static let uint8: UInt8 = 0x02
        static let uint16: UInt8 = 0x84
        static let uint32: UInt8 = 0x86
        static let uint32z: UInt8 = 0x8C
    }

    private static let fitEpochUnix: TimeInterval = 631_065_600 // 1989-12-31 00:00:00 UTC

    static func export(samples: [LiveRideSample], summary: LiveRideSummary) -> Data {
        let normalizedSamples = normalized(samples: samples, startDate: summary.startDate, endDate: summary.endDate)
        var fitDataSection: [UInt8] = []

        let fileIDFields: [FieldDef] = [
            .init(number: 0, size: 1, baseType: FITBaseType.uint8),   // type
            .init(number: 1, size: 2, baseType: FITBaseType.uint16),  // manufacturer
            .init(number: 2, size: 2, baseType: FITBaseType.uint16),  // product
            .init(number: 3, size: 4, baseType: FITBaseType.uint32z), // serial
            .init(number: 4, size: 4, baseType: FITBaseType.uint32)   // time_created
        ]

        let sessionFields: [FieldDef] = [
            .init(number: 253, size: 4, baseType: FITBaseType.uint32), // timestamp
            .init(number: 5, size: 1, baseType: FITBaseType.uint8),    // sport
            .init(number: 7, size: 4, baseType: FITBaseType.uint32),   // total_elapsed_time (ms)
            .init(number: 8, size: 4, baseType: FITBaseType.uint32),   // total_timer_time (ms)
            .init(number: 9, size: 4, baseType: FITBaseType.uint32),   // total_distance (cm)
            .init(number: 16, size: 1, baseType: FITBaseType.uint8),   // avg_hr
            .init(number: 17, size: 1, baseType: FITBaseType.uint8),   // max_hr
            .init(number: 21, size: 2, baseType: FITBaseType.uint16),  // avg_power
            .init(number: 34, size: 2, baseType: FITBaseType.uint16)   // normalized_power
        ]

        let lapFields: [FieldDef] = [
            .init(number: 253, size: 4, baseType: FITBaseType.uint32), // timestamp
            .init(number: 2, size: 4, baseType: FITBaseType.uint32),   // start_time
            .init(number: 7, size: 4, baseType: FITBaseType.uint32),   // total_elapsed_time (ms)
            .init(number: 8, size: 4, baseType: FITBaseType.uint32),   // total_timer_time (ms)
            .init(number: 9, size: 4, baseType: FITBaseType.uint32),   // total_distance (cm)
            .init(number: 16, size: 1, baseType: FITBaseType.uint8),   // avg_hr
            .init(number: 17, size: 1, baseType: FITBaseType.uint8),   // max_hr
            .init(number: 20, size: 2, baseType: FITBaseType.uint16),  // avg_power
            .init(number: 21, size: 2, baseType: FITBaseType.uint16)   // max_power
        ]

        let recordFields: [FieldDef] = [
            .init(number: 253, size: 4, baseType: FITBaseType.uint32), // timestamp
            .init(number: 3, size: 1, baseType: FITBaseType.uint8),    // heart_rate
            .init(number: 5, size: 4, baseType: FITBaseType.uint32),   // distance (cm)
            .init(number: 7, size: 2, baseType: FITBaseType.uint16),   // power
            .init(number: 30, size: 1, baseType: FITBaseType.uint8),   // left_right_balance (%)
            .init(number: 4, size: 1, baseType: FITBaseType.uint8),    // cadence
            .init(number: 6, size: 2, baseType: FITBaseType.uint16)    // speed (1000 m/s)
        ]

        appendDefinition(localMessage: 0, globalMessage: 0, fields: fileIDFields, to: &fitDataSection)
        appendData(localMessage: 0, payload: fileIDPayload(summary: summary), to: &fitDataSection)

        appendDefinition(localMessage: 1, globalMessage: 18, fields: sessionFields, to: &fitDataSection)
        appendDefinition(localMessage: 2, globalMessage: 19, fields: lapFields, to: &fitDataSection)
        appendDefinition(localMessage: 3, globalMessage: 20, fields: recordFields, to: &fitDataSection)

        for sample in normalizedSamples {
            appendData(localMessage: 3, payload: recordPayload(sample: sample), to: &fitDataSection)
        }

        appendData(localMessage: 2, payload: lapPayload(summary: summary), to: &fitDataSection)
        appendData(localMessage: 1, payload: sessionPayload(summary: summary), to: &fitDataSection)

        return wrappedFITData(dataSection: fitDataSection)
    }

    private static func normalized(samples: [LiveRideSample], startDate: Date, endDate: Date) -> [LiveRideSample] {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        if !sorted.isEmpty {
            return sorted
        }
        return [
            LiveRideSample(
                timestamp: startDate,
                powerWatts: nil,
                heartRateBPM: nil,
                cadenceRPM: nil,
                speedKPH: nil,
                distanceMeters: 0,
                leftBalancePercent: nil,
                rightBalancePercent: nil
            ),
            LiveRideSample(
                timestamp: endDate,
                powerWatts: nil,
                heartRateBPM: nil,
                cadenceRPM: nil,
                speedKPH: nil,
                distanceMeters: 0,
                leftBalancePercent: nil,
                rightBalancePercent: nil
            )
        ]
    }

    private static func wrappedFITData(dataSection: [UInt8]) -> Data {
        let headerSize: UInt8 = 14
        let protocolVersion: UInt8 = 0x20
        let profileVersion: UInt16 = 0x08C6
        let dataSize = UInt32(dataSection.count)

        var header: [UInt8] = [
            headerSize,
            protocolVersion,
            UInt8(profileVersion & 0xFF),
            UInt8((profileVersion >> 8) & 0xFF),
            UInt8(dataSize & 0xFF),
            UInt8((dataSize >> 8) & 0xFF),
            UInt8((dataSize >> 16) & 0xFF),
            UInt8((dataSize >> 24) & 0xFF),
            0x2E, 0x46, 0x49, 0x54 // ".FIT"
        ]

        let headerCRC = crc16(header)
        header.append(UInt8(headerCRC & 0xFF))
        header.append(UInt8((headerCRC >> 8) & 0xFF))

        var allBytes = header + dataSection
        let fileCRC = crc16(dataSection)
        allBytes.append(UInt8(fileCRC & 0xFF))
        allBytes.append(UInt8((fileCRC >> 8) & 0xFF))
        return Data(allBytes)
    }

    private static func appendDefinition(localMessage: UInt8, globalMessage: UInt16, fields: [FieldDef], to output: inout [UInt8]) {
        output.append(0x40 | (localMessage & 0x0F))
        output.append(0x00) // reserved
        output.append(0x00) // little endian
        output.append(UInt8(globalMessage & 0xFF))
        output.append(UInt8((globalMessage >> 8) & 0xFF))
        output.append(UInt8(fields.count))
        for field in fields {
            output.append(field.number)
            output.append(field.size)
            output.append(field.baseType)
        }
    }

    private static func appendData(localMessage: UInt8, payload: [UInt8], to output: inout [UInt8]) {
        output.append(localMessage & 0x0F)
        output.append(contentsOf: payload)
    }

    private static func fileIDPayload(summary: LiveRideSummary) -> [UInt8] {
        let created = fitTimestamp(from: summary.startDate)
        var bytes: [UInt8] = []
        bytes.append(4) // activity file
        bytes.append(contentsOf: encodeUInt16(1)) // garmin manufacturer id
        bytes.append(contentsOf: encodeUInt16(1)) // product
        bytes.append(contentsOf: encodeUInt32(1)) // serial
        bytes.append(contentsOf: encodeUInt32(created))
        return bytes
    }

    private static func sessionPayload(summary: LiveRideSummary) -> [UInt8] {
        let end = fitTimestamp(from: summary.endDate)
        let sport = fitSport(summary.sport)
        let elapsedMS = UInt32(max(0, summary.totalElapsedSec) * 1000)
        let timerMS = UInt32(max(0, summary.totalTimerSec) * 1000)
        let distanceCM = UInt32(max(0, Int((summary.totalDistanceMeters * 100.0).rounded())))
        var bytes: [UInt8] = []
        bytes.append(contentsOf: encodeUInt32(end))
        bytes.append(sport)
        bytes.append(contentsOf: encodeUInt32(elapsedMS))
        bytes.append(contentsOf: encodeUInt32(timerMS))
        bytes.append(contentsOf: encodeUInt32(distanceCM))
        bytes.append(encodeUInt8Optional(summary.averageHeartRate))
        bytes.append(encodeUInt8Optional(summary.maxHeartRate))
        bytes.append(contentsOf: encodeUInt16Optional(summary.averagePower))
        bytes.append(contentsOf: encodeUInt16Optional(summary.normalizedPower))
        return bytes
    }

    private static func lapPayload(summary: LiveRideSummary) -> [UInt8] {
        let start = fitTimestamp(from: summary.startDate)
        let end = fitTimestamp(from: summary.endDate)
        let elapsedMS = UInt32(max(0, summary.totalElapsedSec) * 1000)
        let timerMS = UInt32(max(0, summary.totalTimerSec) * 1000)
        let distanceCM = UInt32(max(0, Int((summary.totalDistanceMeters * 100.0).rounded())))
        var bytes: [UInt8] = []
        bytes.append(contentsOf: encodeUInt32(end))
        bytes.append(contentsOf: encodeUInt32(start))
        bytes.append(contentsOf: encodeUInt32(elapsedMS))
        bytes.append(contentsOf: encodeUInt32(timerMS))
        bytes.append(contentsOf: encodeUInt32(distanceCM))
        bytes.append(encodeUInt8Optional(summary.averageHeartRate))
        bytes.append(encodeUInt8Optional(summary.maxHeartRate))
        bytes.append(contentsOf: encodeUInt16Optional(summary.averagePower))
        bytes.append(contentsOf: encodeUInt16Optional(summary.maxPower))
        return bytes
    }

    private static func recordPayload(sample: LiveRideSample) -> [UInt8] {
        let timestamp = fitTimestamp(from: sample.timestamp)
        let distanceCM = UInt32(max(0, Int((sample.distanceMeters * 100.0).rounded())))
        let leftBalancePercent: Int? = {
            if let left = sample.leftBalancePercent, left.isFinite {
                return Int(max(0, min(100, left.rounded())))
            }
            if let right = sample.rightBalancePercent, right.isFinite {
                return Int(max(0, min(100, (100.0 - right).rounded())))
            }
            return nil
        }()
        let speedScaled: Int? = sample.speedKPH.map { kph in
            let mps = kph / 3.6
            return Int((mps * 1000.0).rounded())
        }

        var bytes: [UInt8] = []
        bytes.append(contentsOf: encodeUInt32(timestamp))
        bytes.append(encodeUInt8Optional(sample.heartRateBPM))
        bytes.append(contentsOf: encodeUInt32(distanceCM))
        bytes.append(contentsOf: encodeUInt16Optional(sample.powerWatts))
        bytes.append(encodeUInt8Optional(leftBalancePercent))
        bytes.append(encodeUInt8Optional(sample.cadenceRPM.map { Int($0.rounded()) }))
        bytes.append(contentsOf: encodeUInt16Optional(speedScaled))
        return bytes
    }

    private static func fitSport(_ sport: SportType) -> UInt8 {
        switch sport {
        case .running: return 1
        case .cycling: return 2
        case .swimming: return 5
        case .strength: return 0
        }
    }

    private static func fitTimestamp(from date: Date) -> UInt32 {
        let raw = date.timeIntervalSince1970 - fitEpochUnix
        if !raw.isFinite { return 0 }
        return UInt32(max(0, Int(raw.rounded())))
    }

    private static func encodeUInt8Optional(_ value: Int?) -> UInt8 {
        guard let value else { return 0xFF }
        return UInt8(clamping: max(0, min(254, value)))
    }

    private static func encodeUInt16Optional(_ value: Int?) -> [UInt8] {
        guard let value else { return [0xFF, 0xFF] }
        return encodeUInt16(max(0, min(65534, value)))
    }

    private static func encodeUInt16(_ value: Int) -> [UInt8] {
        let v = UInt16(max(0, min(65535, value)))
        return [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
    }

    private static func encodeUInt32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }

    private static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }
}
