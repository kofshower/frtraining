import Foundation

enum ActivityImportError: Error, LocalizedError {
    case unsupportedFormat
    case parserFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported file format. Please import FIT, TCX, or GPX."
        case let .parserFailed(message):
            return message
        }
    }
}

struct ParsedActivitySummary {
    var date: Date
    var sport: SportType
    var durationSec: Int
    var distanceKm: Double
    var avgHeartRate: Int?
    var avgPower: Int?
    var normalizedPower: Int?
    var notes: String
}

struct ActivitySensorSample {
    let timeSec: Double
    let power: Double?
    let heartRate: Double?
    let altitudeMeters: Double?
}

enum ActivitySourceDataDecoder {
    private static var cache: [UUID: [ActivitySensorSample]] = [:]
    private static var cacheOrder: [UUID] = []
    private static let maxCacheEntries = 48
    private static let cacheLock = NSLock()

    private static func storeCache(_ samples: [ActivitySensorSample], for id: UUID) {
        cache[id] = samples
        if let index = cacheOrder.firstIndex(of: id) {
            cacheOrder.remove(at: index)
        }
        cacheOrder.append(id)
        if cacheOrder.count > maxCacheEntries {
            let overflow = cacheOrder.count - maxCacheEntries
            for _ in 0..<overflow {
                guard let evicted = cacheOrder.first else { break }
                cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
    }

    static func samples(for activity: Activity) -> [ActivitySensorSample] {
        cacheLock.lock()
        let cached = cache[activity.id]
        cacheLock.unlock()
        if let cached {
            return cached
        }
        guard
            let encoded = activity.sourceFileBase64,
            let data = Data(base64Encoded: encoded),
            let fileType = activity.sourceFileType?.lowercased()
        else {
            cacheLock.lock()
            storeCache([], for: activity.id)
            cacheLock.unlock()
            return []
        }

        let parsed: [ActivitySensorSample]
        switch fileType {
        case "fit":
            parsed = (try? FITActivityParser.parseSensorSamples(data: data)) ?? []
        case "tcx":
            parsed = (try? TCXActivityStreamParser.parse(data: data)) ?? []
        case "gpx":
            parsed = (try? GPXActivityStreamParser.parse(data: data)) ?? []
        default:
            parsed = []
        }

        cacheLock.lock()
        storeCache(parsed, for: activity.id)
        cacheLock.unlock()
        return parsed
    }
}

enum ActivityFileImporter {
    static func importFile(at url: URL, profile: AthleteProfile) throws -> Activity {
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)

        let summary: ParsedActivitySummary
        switch ext {
        case "fit":
            summary = try FITActivityParser.parse(data: data)
        case "tcx":
            summary = try TCXActivityParser.parse(data: data)
        case "gpx":
            summary = try GPXActivityParser.parse(data: data)
        default:
            throw ActivityImportError.unsupportedFormat
        }

        let tss = TSSEstimator.estimate(
            durationSec: summary.durationSec,
            sport: summary.sport,
            avgPower: summary.avgPower,
            normalizedPower: summary.normalizedPower,
            avgHeartRate: summary.avgHeartRate,
            profile: profile,
            date: summary.date
        )

        return Activity(
            date: summary.date,
            sport: summary.sport,
            durationSec: max(1, summary.durationSec),
            distanceKm: max(0, summary.distanceKm),
            tss: max(0, tss),
            normalizedPower: summary.normalizedPower ?? summary.avgPower,
            avgHeartRate: summary.avgHeartRate,
            intervals: [],
            notes: summary.notes,
            sourceFileName: url.lastPathComponent,
            sourceFileType: ext,
            sourceFileBase64: data.base64EncodedString()
        )
    }
}

enum TSSEstimator {
    static func estimate(
        durationSec: Int,
        sport: SportType,
        avgPower: Int?,
        normalizedPower: Int?,
        avgHeartRate: Int?,
        profile: AthleteProfile,
        date: Date? = nil
    ) -> Int {
        let hours = Double(durationSec) / 3600.0
        guard hours > 0 else { return 0 }

        let ftp = profile.ftpWatts(for: sport)
        if let power = normalizedPower ?? avgPower, ftp > 0 {
            let intensity = max(0, Double(power) / Double(ftp))
            return Int((hours * intensity * intensity * 100.0).rounded())
        }

        let thresholdHR = profile.thresholdHeartRate(for: sport, on: date ?? Date())
        if let heartRate = avgHeartRate, thresholdHR > 0 {
            let intensity = min(1.35, max(0.4, Double(heartRate) / Double(thresholdHR)))
            return Int((hours * intensity * intensity * 100.0).rounded())
        }

        return Int((hours * 45.0).rounded())
    }

    static func normalizedPower(from watts: [Double]) -> Int? {
        guard watts.count >= 10 else { return nil }
        let avgFourth = watts.reduce(0.0) { $0 + pow($1, 4) } / Double(watts.count)
        return Int(pow(avgFourth, 0.25).rounded())
    }
}

enum TCXActivityParser {
    static func parse(data: Data) throws -> ParsedActivitySummary {
        let delegate = TCXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw ActivityImportError.parserFailed(parser.parserError?.localizedDescription ?? "TCX parser failed")
        }

        guard let summary = delegate.summary() else {
            throw ActivityImportError.parserFailed("TCX file does not contain enough activity data")
        }

        return summary
    }

    private final class TCXParserDelegate: NSObject, XMLParserDelegate {
        private var stack: [String] = []
        private var textBuffer = ""

        private var sport: SportType = .cycling
        private var activityDate: Date?
        private var lapDurationSec: Double = 0
        private var lapDistanceMeters: Double = 0

        private var pointTimes: [Date] = []
        private var heartRates: [Double] = []
        private var powers: [Double] = []

        private var inHeartRateBpm = false
        private var inTrackpoint = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            stack.append(elementName)
            textBuffer = ""

            if elementName == "Activity", let sportRaw = attributeDict["Sport"] {
                sport = mapSport(sportRaw)
            } else if elementName == "HeartRateBpm" {
                inHeartRateBpm = true
            } else if elementName == "Trackpoint" {
                inTrackpoint = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBuffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = stack.dropLast().last ?? ""

            if !value.isEmpty {
                switch elementName {
                case "Id":
                    if parent == "Activity", let parsed = DateParsers.parseISO8601(value) {
                        activityDate = parsed
                    }
                case "TotalTimeSeconds":
                    if stack.contains("Lap"), !stack.contains("Trackpoint") {
                        lapDurationSec += Double(value) ?? 0
                    }
                case "DistanceMeters":
                    if inTrackpoint {
                        // Distance in trackpoints is optional and can be ignored; lap distance is more stable.
                    } else if stack.contains("Lap") {
                        lapDistanceMeters += Double(value) ?? 0
                    }
                case "Time":
                    if inTrackpoint, let parsed = DateParsers.parseISO8601(value) {
                        pointTimes.append(parsed)
                    }
                case "Value":
                    if inTrackpoint, inHeartRateBpm, let hr = Double(value), hr > 0 {
                        heartRates.append(hr)
                    }
                case "Watts":
                    if inTrackpoint, let watts = Double(value), watts > 0 {
                        powers.append(watts)
                    }
                default:
                    break
                }
            }

            if elementName == "HeartRateBpm" {
                inHeartRateBpm = false
            } else if elementName == "Trackpoint" {
                inTrackpoint = false
            }

            _ = stack.popLast()
            textBuffer = ""
        }

        func summary() -> ParsedActivitySummary? {
            let date = activityDate ?? pointTimes.first
            guard let date else { return nil }

            let durationSec: Int = {
                if lapDurationSec > 0 { return Int(lapDurationSec.rounded()) }
                if let first = pointTimes.first, let last = pointTimes.last {
                    return max(1, Int(last.timeIntervalSince(first).rounded()))
                }
                return 0
            }()

            let distanceKm = max(0, lapDistanceMeters / 1000.0)
            let avgHR = heartRates.isEmpty ? nil : Int((heartRates.reduce(0, +) / Double(heartRates.count)).rounded())
            let avgPower = powers.isEmpty ? nil : Int((powers.reduce(0, +) / Double(powers.count)).rounded())
            let np = TSSEstimator.normalizedPower(from: powers)

            return ParsedActivitySummary(
                date: date,
                sport: sport,
                durationSec: max(1, durationSec),
                distanceKm: distanceKm,
                avgHeartRate: avgHR,
                avgPower: avgPower,
                normalizedPower: np,
                notes: "Imported from TCX"
            )
        }

        private func mapSport(_ value: String) -> SportType {
            let raw = value.lowercased()
            if raw.contains("run") { return .running }
            if raw.contains("swim") { return .swimming }
            if raw.contains("bike") || raw.contains("cycle") { return .cycling }
            return .strength
        }
    }
}

enum GPXActivityParser {
    static func parse(data: Data) throws -> ParsedActivitySummary {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw ActivityImportError.parserFailed(parser.parserError?.localizedDescription ?? "GPX parser failed")
        }

        guard let summary = delegate.summary() else {
            throw ActivityImportError.parserFailed("GPX file does not contain enough activity data")
        }

        return summary
    }

    private struct TrackPoint {
        var lat: Double
        var lon: Double
        var time: Date?
        var heartRate: Double?
        var power: Double?
    }

    private final class GPXParserDelegate: NSObject, XMLParserDelegate {
        private var stack: [String] = []
        private var textBuffer = ""

        private var points: [TrackPoint] = []
        private var currentPoint: TrackPoint?
        private var sport: SportType = .cycling

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            stack.append(elementName)
            textBuffer = ""

            if elementName == "trkpt" {
                let lat = Double(attributeDict["lat"] ?? "") ?? 0
                let lon = Double(attributeDict["lon"] ?? "") ?? 0
                currentPoint = TrackPoint(lat: lat, lon: lon, time: nil, heartRate: nil, power: nil)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBuffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            let local = elementName.lowercased()

            if !value.isEmpty {
                switch local {
                case "time":
                    if currentPoint != nil, let parsed = DateParsers.parseISO8601(value) {
                        currentPoint?.time = parsed
                    }
                case "type":
                    sport = mapSport(value)
                case "hr", "heartrate":
                    if currentPoint != nil {
                        currentPoint?.heartRate = Double(value)
                    }
                case "power", "watts":
                    if currentPoint != nil {
                        currentPoint?.power = Double(value)
                    }
                default:
                    break
                }
            }

            if local == "trkpt", let point = currentPoint {
                points.append(point)
                currentPoint = nil
            }

            _ = stack.popLast()
            textBuffer = ""
        }

        func summary() -> ParsedActivitySummary? {
            guard let start = points.compactMap({ $0.time }).min(), let end = points.compactMap({ $0.time }).max() else {
                return nil
            }

            let distanceMeters = points.adjacentPairs().reduce(0.0) { sum, pair in
                sum + Geo.haversineMeters(
                    lat1: pair.0.lat,
                    lon1: pair.0.lon,
                    lat2: pair.1.lat,
                    lon2: pair.1.lon
                )
            }

            let hrs = points.compactMap { $0.heartRate }
            let powers = points.compactMap { $0.power }

            let durationSec = max(1, Int(end.timeIntervalSince(start).rounded()))
            let avgHR = hrs.isEmpty ? nil : Int((hrs.reduce(0, +) / Double(hrs.count)).rounded())
            let avgPower = powers.isEmpty ? nil : Int((powers.reduce(0, +) / Double(powers.count)).rounded())
            let np = TSSEstimator.normalizedPower(from: powers)

            return ParsedActivitySummary(
                date: start,
                sport: sport,
                durationSec: durationSec,
                distanceKm: max(0, distanceMeters / 1000.0),
                avgHeartRate: avgHR,
                avgPower: avgPower,
                normalizedPower: np,
                notes: "Imported from GPX"
            )
        }

        private func mapSport(_ value: String) -> SportType {
            let raw = value.lowercased()
            if raw.contains("run") { return .running }
            if raw.contains("swim") { return .swimming }
            if raw.contains("ride") || raw.contains("bike") || raw.contains("cycle") { return .cycling }
            return .cycling
        }
    }
}

enum FITActivityParser {
    private struct FieldDef {
        var number: Int
        var size: Int
        var baseType: UInt8
    }

    private struct MessageDef {
        var globalMessageNumber: Int
        var littleEndian: Bool
        var fields: [FieldDef]
    }

    private struct SessionAccumulator {
        var date: Date?
        var sport: SportType?
        var durationSec: Int?
        var distanceMeters: Double?
        var avgHeartRate: Int?
        var avgPower: Int?
        var normalizedPower: Int?
    }

    private struct RecordAccumulator {
        var firstTime: Date?
        var lastTime: Date?
        var lastDistanceMeters: Double?
        var heartRates: [Double] = []
        var powers: [Double] = []
    }

    static func parse(data: Data) throws -> ParsedActivitySummary {
        let bytes = [UInt8](data)
        guard bytes.count >= 14 else {
            throw ActivityImportError.parserFailed("FIT file too small")
        }

        let headerSize = Int(bytes[0])
        guard headerSize >= 12, bytes.count > headerSize else {
            throw ActivityImportError.parserFailed("Invalid FIT header")
        }

        let dataSize = Int(Byte.decodeUInt32LE(bytes, at: 4))
        let start = headerSize
        let end = min(bytes.count, start + dataSize)
        guard end > start else {
            throw ActivityImportError.parserFailed("FIT contains no data records")
        }

        var definitions: [Int: MessageDef] = [:]
        var cursor = start
        var lastTimestamp: UInt32?

        var session = SessionAccumulator()
        var records = RecordAccumulator()

        while cursor < end {
            let header = bytes[cursor]
            cursor += 1

            if header & 0x80 != 0 {
                let localNum = Int((header >> 5) & 0x03)
                guard let definition = definitions[localNum] else {
                    throw ActivityImportError.parserFailed("FIT data references missing local definition")
                }

                var values = try decodeDataMessage(definition: definition, bytes: bytes, cursor: &cursor, end: end)
                if let last = lastTimestamp {
                    let offset = UInt32(header & 0x1F)
                    var reconstructed = (last & ~UInt32(0x1F)) + offset
                    if reconstructed < last {
                        reconstructed += 0x20
                    }
                    lastTimestamp = reconstructed
                    values[253] = .uint(UInt64(reconstructed))
                }
                absorb(definition.globalMessageNumber, values: values, session: &session, records: &records, lastTimestamp: &lastTimestamp)
                continue
            }

            let isDefinition = (header & 0x40) != 0
            let hasDeveloperFields = (header & 0x20) != 0
            let localNum = Int(header & 0x0F)

            if isDefinition {
                guard cursor + 5 <= end else {
                    throw ActivityImportError.parserFailed("FIT definition truncated")
                }

                let architecture = bytes[cursor + 1]
                let littleEndian = architecture == 0
                let globalNum: UInt16 = littleEndian
                    ? Byte.decodeUInt16LE(bytes, at: cursor + 2)
                    : Byte.decodeUInt16BE(bytes, at: cursor + 2)
                let fieldCount = Int(bytes[cursor + 4])
                cursor += 5

                var fields: [FieldDef] = []
                fields.reserveCapacity(fieldCount)
                for _ in 0..<fieldCount {
                    guard cursor + 3 <= end else {
                        throw ActivityImportError.parserFailed("FIT field definition truncated")
                    }
                    fields.append(FieldDef(number: Int(bytes[cursor]), size: Int(bytes[cursor + 1]), baseType: bytes[cursor + 2]))
                    cursor += 3
                }

                if hasDeveloperFields {
                    guard cursor < end else {
                        throw ActivityImportError.parserFailed("FIT developer definition truncated")
                    }
                    let devCount = Int(bytes[cursor])
                    cursor += 1
                    let bytesToSkip = devCount * 3
                    guard cursor + bytesToSkip <= end else {
                        throw ActivityImportError.parserFailed("FIT developer fields truncated")
                    }
                    cursor += bytesToSkip
                }

                definitions[localNum] = MessageDef(globalMessageNumber: Int(globalNum), littleEndian: littleEndian, fields: fields)
            } else {
                guard let definition = definitions[localNum] else {
                    throw ActivityImportError.parserFailed("FIT data references missing local definition")
                }
                let values = try decodeDataMessage(definition: definition, bytes: bytes, cursor: &cursor, end: end)
                absorb(definition.globalMessageNumber, values: values, session: &session, records: &records, lastTimestamp: &lastTimestamp)
            }
        }

        let date = session.date ?? records.firstTime
        guard let date else {
            throw ActivityImportError.parserFailed("FIT file has no valid timestamp")
        }

        let durationSec = session.durationSec ?? {
            guard let first = records.firstTime, let last = records.lastTime else { return 0 }
            return max(1, Int(last.timeIntervalSince(first).rounded()))
        }()

        let distanceKm = (session.distanceMeters ?? records.lastDistanceMeters ?? 0) / 1000.0
        let avgHR = session.avgHeartRate ?? {
            guard !records.heartRates.isEmpty else { return nil }
            return Int((records.heartRates.reduce(0, +) / Double(records.heartRates.count)).rounded())
        }()
        let avgPower = session.avgPower ?? {
            guard !records.powers.isEmpty else { return nil }
            return Int((records.powers.reduce(0, +) / Double(records.powers.count)).rounded())
        }()
        let np = session.normalizedPower ?? TSSEstimator.normalizedPower(from: records.powers)

        return ParsedActivitySummary(
            date: date,
            sport: session.sport ?? .cycling,
            durationSec: max(1, durationSec),
            distanceKm: max(0, distanceKm),
            avgHeartRate: avgHR,
            avgPower: avgPower,
            normalizedPower: np,
            notes: "Imported from FIT"
        )
    }

    static func parseSensorSamples(data: Data) throws -> [ActivitySensorSample] {
        let bytes = [UInt8](data)
        guard bytes.count >= 14 else {
            throw ActivityImportError.parserFailed("FIT file too small")
        }

        let headerSize = Int(bytes[0])
        guard headerSize >= 12, bytes.count > headerSize else {
            throw ActivityImportError.parserFailed("Invalid FIT header")
        }

        let dataSize = Int(Byte.decodeUInt32LE(bytes, at: 4))
        let start = headerSize
        let end = min(bytes.count, start + dataSize)
        guard end > start else {
            throw ActivityImportError.parserFailed("FIT contains no data records")
        }

        var definitions: [Int: MessageDef] = [:]
        var cursor = start
        var lastTimestamp: UInt32?
        var firstTimestamp: UInt32?
        var samples: [ActivitySensorSample] = []

        while cursor < end {
            let header = bytes[cursor]
            cursor += 1

            if header & 0x80 != 0 {
                let localNum = Int((header >> 5) & 0x03)
                guard let definition = definitions[localNum] else {
                    throw ActivityImportError.parserFailed("FIT data references missing local definition")
                }
                var values = try decodeDataMessage(definition: definition, bytes: bytes, cursor: &cursor, end: end)
                if let last = lastTimestamp {
                    let offset = UInt32(header & 0x1F)
                    var reconstructed = (last & ~UInt32(0x1F)) + offset
                    if reconstructed < last {
                        reconstructed += 0x20
                    }
                    lastTimestamp = reconstructed
                    values[253] = .uint(UInt64(reconstructed))
                }
                absorbSensorRecord(
                    definition.globalMessageNumber,
                    values: values,
                    samples: &samples,
                    firstTimestamp: &firstTimestamp,
                    lastTimestamp: &lastTimestamp
                )
                continue
            }

            let isDefinition = (header & 0x40) != 0
            let hasDeveloperFields = (header & 0x20) != 0
            let localNum = Int(header & 0x0F)

            if isDefinition {
                guard cursor + 5 <= end else {
                    throw ActivityImportError.parserFailed("FIT definition truncated")
                }

                let architecture = bytes[cursor + 1]
                let littleEndian = architecture == 0
                let globalNum: UInt16 = littleEndian
                    ? Byte.decodeUInt16LE(bytes, at: cursor + 2)
                    : Byte.decodeUInt16BE(bytes, at: cursor + 2)
                let fieldCount = Int(bytes[cursor + 4])
                cursor += 5

                var fields: [FieldDef] = []
                fields.reserveCapacity(fieldCount)
                for _ in 0..<fieldCount {
                    guard cursor + 3 <= end else {
                        throw ActivityImportError.parserFailed("FIT field definition truncated")
                    }
                    fields.append(FieldDef(number: Int(bytes[cursor]), size: Int(bytes[cursor + 1]), baseType: bytes[cursor + 2]))
                    cursor += 3
                }

                if hasDeveloperFields {
                    guard cursor < end else {
                        throw ActivityImportError.parserFailed("FIT developer definition truncated")
                    }
                    let devCount = Int(bytes[cursor])
                    cursor += 1
                    let bytesToSkip = devCount * 3
                    guard cursor + bytesToSkip <= end else {
                        throw ActivityImportError.parserFailed("FIT developer fields truncated")
                    }
                    cursor += bytesToSkip
                }

                definitions[localNum] = MessageDef(globalMessageNumber: Int(globalNum), littleEndian: littleEndian, fields: fields)
            } else {
                guard let definition = definitions[localNum] else {
                    throw ActivityImportError.parserFailed("FIT data references missing local definition")
                }
                let values = try decodeDataMessage(definition: definition, bytes: bytes, cursor: &cursor, end: end)
                absorbSensorRecord(
                    definition.globalMessageNumber,
                    values: values,
                    samples: &samples,
                    firstTimestamp: &firstTimestamp,
                    lastTimestamp: &lastTimestamp
                )
            }
        }

        return samples.sorted { $0.timeSec < $1.timeSec }
    }

    private enum Value {
        case int(Int64)
        case uint(UInt64)
        case double(Double)
        case string(String)

        var doubleValue: Double? {
            switch self {
            case let .int(v): return Double(v)
            case let .uint(v): return Double(v)
            case let .double(v): return v
            case .string: return nil
            }
        }

        var intValue: Int? {
            switch self {
            case let .int(v): return Int(v)
            case let .uint(v): return Int(v)
            case let .double(v): return Int(v)
            case .string: return nil
            }
        }
    }

    private static func decodeDataMessage(
        definition: MessageDef,
        bytes: [UInt8],
        cursor: inout Int,
        end: Int
    ) throws -> [Int: Value] {
        var values: [Int: Value] = [:]

        for field in definition.fields {
            guard cursor + field.size <= end else {
                throw ActivityImportError.parserFailed("FIT data field truncated")
            }

            let range = cursor..<(cursor + field.size)
            let fieldBytes = Array(bytes[range])
            cursor += field.size

            if let decoded = decodeField(bytes: fieldBytes, baseType: field.baseType, littleEndian: definition.littleEndian) {
                values[field.number] = decoded
            }
        }

        return values
    }

    private static func decodeField(bytes: [UInt8], baseType: UInt8, littleEndian: Bool) -> Value? {
        let type = baseType & 0x1F

        switch type {
        case 0, 2, 10, 13:
            guard let first = bytes.first, first != 0xFF else { return nil }
            return .uint(UInt64(first))
        case 1:
            guard let first = bytes.first, first != 0x7F else { return nil }
            return .int(Int64(Int8(bitPattern: first)))
        case 7:
            let chars = bytes.prefix { $0 != 0 }
            guard !chars.isEmpty else { return nil }
            return .string(String(decoding: chars, as: UTF8.self))
        case 131:
            guard bytes.count >= 2 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt16LE(bytes, at: 0) : Byte.decodeUInt16BE(bytes, at: 0)
            if raw == 0x7FFF { return nil }
            return .int(Int64(Int16(bitPattern: raw)))
        case 132, 139:
            guard bytes.count >= 2 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt16LE(bytes, at: 0) : Byte.decodeUInt16BE(bytes, at: 0)
            if raw == 0xFFFF { return nil }
            return .uint(UInt64(raw))
        case 133:
            guard bytes.count >= 4 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt32LE(bytes, at: 0) : Byte.decodeUInt32BE(bytes, at: 0)
            if raw == 0x7FFFFFFF { return nil }
            return .int(Int64(Int32(bitPattern: raw)))
        case 134, 140:
            guard bytes.count >= 4 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt32LE(bytes, at: 0) : Byte.decodeUInt32BE(bytes, at: 0)
            if raw == 0xFFFFFFFF { return nil }
            return .uint(UInt64(raw))
        case 136:
            guard bytes.count >= 4 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt32LE(bytes, at: 0) : Byte.decodeUInt32BE(bytes, at: 0)
            return .double(Double(Float(bitPattern: raw)))
        case 137:
            guard bytes.count >= 8 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt64LE(bytes, at: 0) : Byte.decodeUInt64BE(bytes, at: 0)
            return .double(Double(bitPattern: raw))
        default:
            return nil
        }
    }

    private static func absorb(
        _ globalMessageNumber: Int,
        values: [Int: Value],
        session: inout SessionAccumulator,
        records: inout RecordAccumulator,
        lastTimestamp: inout UInt32?
    ) {
        switch globalMessageNumber {
        case 0:
            // file_id
            if session.sport == nil, let sportVal = values[1]?.intValue {
                session.sport = mapSport(sportVal)
            }
        case 18:
            if let timestamp = fitDate(from: values[253]) {
                session.date = timestamp
                if case let .uint(raw)? = values[253] {
                    lastTimestamp = UInt32(raw)
                }
            }
            if let sportVal = values[5]?.intValue {
                session.sport = mapSport(sportVal)
            }
            if let totalTimer = values[8]?.doubleValue {
                session.durationSec = Int((totalTimer / 1000.0).rounded())
            } else if let elapsed = values[7]?.doubleValue {
                session.durationSec = Int((elapsed / 1000.0).rounded())
            }
            if let distance = values[9]?.doubleValue {
                session.distanceMeters = distance / 100.0
            }
            if let avgHr = values[16]?.intValue {
                session.avgHeartRate = avgHr
            }
            if let avgPower = values[21]?.intValue {
                session.avgPower = avgPower
            }
            if let np = values[34]?.intValue ?? values[48]?.intValue {
                session.normalizedPower = np
            }
        case 20:
            if let timestamp = fitDate(from: values[253]) {
                records.firstTime = minDate(records.firstTime, timestamp)
                records.lastTime = maxDate(records.lastTime, timestamp)
                if case let .uint(raw)? = values[253] {
                    lastTimestamp = UInt32(raw)
                }
            }
            if let distance = values[5]?.doubleValue {
                records.lastDistanceMeters = distance / 100.0
            }
            if let hr = values[3]?.doubleValue, hr > 0 {
                records.heartRates.append(hr)
            }
            if let watts = values[7]?.doubleValue, watts > 0 {
                records.powers.append(watts)
            }
        default:
            break
        }
    }

    private static func absorbSensorRecord(
        _ globalMessageNumber: Int,
        values: [Int: Value],
        samples: inout [ActivitySensorSample],
        firstTimestamp: inout UInt32?,
        lastTimestamp: inout UInt32?
    ) {
        guard globalMessageNumber == 20 else {
            return
        }

        var timestamp: UInt32?
        if case let .uint(raw)? = values[253] {
            timestamp = UInt32(raw)
            lastTimestamp = timestamp
        } else if case let .int(raw)? = values[253], raw >= 0 {
            timestamp = UInt32(raw)
            lastTimestamp = timestamp
        } else if let last = lastTimestamp {
            timestamp = last
        }

        if firstTimestamp == nil, let timestamp {
            firstTimestamp = timestamp
        }

        let timeSec: Double = {
            guard let timestamp else { return Double(samples.count) }
            return Double(timestamp - (firstTimestamp ?? timestamp))
        }()

        let hr = values[3]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
        let power = values[7]?.doubleValue.flatMap { $0 >= 0 ? $0 : nil }
        let altitudeMeters: Double? = {
            let raw = values[78]?.doubleValue ?? values[2]?.doubleValue
            guard let raw, raw.isFinite else { return nil }
            return raw / 5.0 - 500.0
        }()

        guard hr != nil || power != nil || altitudeMeters != nil else {
            return
        }
        samples.append(
            ActivitySensorSample(
                timeSec: timeSec,
                power: power,
                heartRate: hr,
                altitudeMeters: altitudeMeters
            )
        )
    }

    private static func minDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return min(lhs, rhs)
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }

    private static func fitDate(from value: Value?) -> Date? {
        guard let raw = value?.doubleValue else { return nil }
        let fitEpoch = Date(timeIntervalSince1970: 631_065_600) // 1989-12-31 00:00:00 UTC
        return fitEpoch.addingTimeInterval(raw)
    }

    private static func mapSport(_ value: Int) -> SportType {
        switch value {
        case 1: return .running
        case 2: return .cycling
        case 5: return .swimming
        default: return .strength
        }
    }
}

enum TCXActivityStreamParser {
    static func parse(data: Data) throws -> [ActivitySensorSample] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw ActivityImportError.parserFailed(parser.parserError?.localizedDescription ?? "TCX stream parser failed")
        }
        return delegate.samples()
    }

    private struct RawSample {
        let time: Date
        let power: Double?
        let hr: Double?
        let altitude: Double?
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private var stack: [String] = []
        private var textBuffer = ""

        private var inTrackpoint = false
        private var inHeartRateBpm = false

        private var currentTime: Date?
        private var currentPower: Double?
        private var currentHR: Double?
        private var currentAltitude: Double?
        private var rows: [RawSample] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            stack.append(elementName)
            textBuffer = ""
            if elementName == "Trackpoint" {
                inTrackpoint = true
                currentTime = nil
                currentPower = nil
                currentHR = nil
                currentAltitude = nil
            } else if elementName == "HeartRateBpm" {
                inHeartRateBpm = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBuffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                switch elementName {
                case "Time":
                    if inTrackpoint {
                        currentTime = DateParsers.parseISO8601(value)
                    }
                case "Value":
                    if inTrackpoint, inHeartRateBpm {
                        currentHR = Double(value)
                    }
                case "Watts":
                    if inTrackpoint {
                        currentPower = Double(value)
                    }
                case "AltitudeMeters":
                    if inTrackpoint {
                        currentAltitude = Double(value)
                    }
                default:
                    break
                }
            }

            if elementName == "HeartRateBpm" {
                inHeartRateBpm = false
            } else if elementName == "Trackpoint" {
                inTrackpoint = false
                if let currentTime {
                    rows.append(
                        RawSample(
                            time: currentTime,
                            power: currentPower,
                            hr: currentHR,
                            altitude: currentAltitude
                        )
                    )
                }
            }

            _ = stack.popLast()
            textBuffer = ""
        }

        func samples() -> [ActivitySensorSample] {
            guard let start = rows.map(\.time).min() else { return [] }
            return rows.map { row in
                ActivitySensorSample(
                    timeSec: row.time.timeIntervalSince(start),
                    power: row.power,
                    heartRate: row.hr,
                    altitudeMeters: row.altitude
                )
            }.sorted { $0.timeSec < $1.timeSec }
        }
    }
}

enum GPXActivityStreamParser {
    static func parse(data: Data) throws -> [ActivitySensorSample] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw ActivityImportError.parserFailed(parser.parserError?.localizedDescription ?? "GPX stream parser failed")
        }
        return delegate.samples()
    }

    private struct RawSample {
        let time: Date
        let power: Double?
        let hr: Double?
        let altitude: Double?
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private var stack: [String] = []
        private var textBuffer = ""

        private var inTrackpoint = false
        private var currentTime: Date?
        private var currentPower: Double?
        private var currentHR: Double?
        private var currentAltitude: Double?
        private var rows: [RawSample] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            stack.append(elementName)
            textBuffer = ""
            if elementName.lowercased() == "trkpt" {
                inTrackpoint = true
                currentTime = nil
                currentPower = nil
                currentHR = nil
                currentAltitude = nil
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBuffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            let local = elementName.lowercased()
            if !value.isEmpty {
                switch local {
                case "time":
                    if inTrackpoint {
                        currentTime = DateParsers.parseISO8601(value)
                    }
                case "ele":
                    if inTrackpoint {
                        currentAltitude = Double(value)
                    }
                case "hr", "heartrate":
                    if inTrackpoint {
                        currentHR = Double(value)
                    }
                case "power", "watts":
                    if inTrackpoint {
                        currentPower = Double(value)
                    }
                default:
                    break
                }
            }

            if local == "trkpt" {
                inTrackpoint = false
                if let currentTime {
                    rows.append(
                        RawSample(
                            time: currentTime,
                            power: currentPower,
                            hr: currentHR,
                            altitude: currentAltitude
                        )
                    )
                }
            }
            _ = stack.popLast()
            textBuffer = ""
        }

        func samples() -> [ActivitySensorSample] {
            guard let start = rows.map(\.time).min() else { return [] }
            return rows.map { row in
                ActivitySensorSample(
                    timeSec: row.time.timeIntervalSince(start),
                    power: row.power,
                    heartRate: row.hr,
                    altitudeMeters: row.altitude
                )
            }.sorted { $0.timeSec < $1.timeSec }
        }
    }
}

enum DateParsers {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseISO8601(_ value: String) -> Date? {
        if let a = isoWithFraction.date(from: value) { return a }
        if let b = iso.date(from: value) { return b }
        return nil
    }
}

enum Geo {
    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let a = pow(sin(dLat / 2), 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * pow(sin(dLon / 2), 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}

enum Byte {
    static func decodeUInt16LE(_ bytes: [UInt8], at index: Int) -> UInt16 {
        UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    static func decodeUInt16BE(_ bytes: [UInt8], at index: Int) -> UInt16 {
        (UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1])
    }

    static func decodeUInt32LE(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
        | (UInt32(bytes[index + 1]) << 8)
        | (UInt32(bytes[index + 2]) << 16)
        | (UInt32(bytes[index + 3]) << 24)
    }

    static func decodeUInt32BE(_ bytes: [UInt8], at index: Int) -> UInt32 {
        (UInt32(bytes[index]) << 24)
        | (UInt32(bytes[index + 1]) << 16)
        | (UInt32(bytes[index + 2]) << 8)
        | UInt32(bytes[index + 3])
    }

    static func decodeUInt64LE(_ bytes: [UInt8], at index: Int) -> UInt64 {
        UInt64(bytes[index])
        | (UInt64(bytes[index + 1]) << 8)
        | (UInt64(bytes[index + 2]) << 16)
        | (UInt64(bytes[index + 3]) << 24)
        | (UInt64(bytes[index + 4]) << 32)
        | (UInt64(bytes[index + 5]) << 40)
        | (UInt64(bytes[index + 6]) << 48)
        | (UInt64(bytes[index + 7]) << 56)
    }

    static func decodeUInt64BE(_ bytes: [UInt8], at index: Int) -> UInt64 {
        (UInt64(bytes[index]) << 56)
        | (UInt64(bytes[index + 1]) << 48)
        | (UInt64(bytes[index + 2]) << 40)
        | (UInt64(bytes[index + 3]) << 32)
        | (UInt64(bytes[index + 4]) << 24)
        | (UInt64(bytes[index + 5]) << 16)
        | (UInt64(bytes[index + 6]) << 8)
        | UInt64(bytes[index + 7])
    }
}

extension Array {
    func adjacentPairs() -> [(Element, Element)] {
        guard count > 1 else { return [] }
        return (0..<(count - 1)).map { (self[$0], self[$0 + 1]) }
    }
}

enum TCXWriter {
    static func export(activity: Activity) -> Data {
        let iso = ISO8601DateFormatter()
        let start = iso.string(from: activity.date)
        let end = iso.string(from: activity.date.addingTimeInterval(TimeInterval(activity.durationSec)))
        let distanceMeters = max(0, activity.distanceKm * 1000.0)

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
          <Activities>
            <Activity Sport="\(sportForTCX(activity.sport))">
              <Id>\(start)</Id>
              <Lap StartTime="\(start)">
                <TotalTimeSeconds>\(activity.durationSec)</TotalTimeSeconds>
                <DistanceMeters>\(String(format: "%.1f", distanceMeters))</DistanceMeters>
                <Track>
                  <Trackpoint>
                    <Time>\(start)</Time>
                    <DistanceMeters>0</DistanceMeters>
                  </Trackpoint>
                  <Trackpoint>
                    <Time>\(end)</Time>
                    <DistanceMeters>\(String(format: "%.1f", distanceMeters))</DistanceMeters>
                  </Trackpoint>
                </Track>
              </Lap>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """

        return Data(xml.utf8)
    }

    private static func sportForTCX(_ sport: SportType) -> String {
        switch sport {
        case .cycling: return "Biking"
        case .running: return "Running"
        case .swimming: return "Other"
        case .strength: return "Other"
        }
    }
}
